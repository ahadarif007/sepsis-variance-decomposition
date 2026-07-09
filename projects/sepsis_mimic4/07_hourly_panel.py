"""
07_hourly_panel.py
==================
THE temporal substrate for real-time sepsis prediction. Where script 04
collapses each stay into ONE row of first-24h summaries, this script resamples
every cohort stay onto a regular **hourly grid** and emits one row per
(stay_id, hour) with the physiology observed in that hour — the base table that
onset labelling (08) and the longitudinal report (09) and, ultimately, the
real-time model are built on.

Design
------
* Horizon: hours 0 .. min(LOS, MAX_PANEL_HOURS) measured from ICU `intime`
  (hour 0 = the hour starting at intime). Stays are variable length; the panel
  is right-censored at MAX_PANEL_HOURS (see config-like constant below).
* For each variable and hour we aggregate all readings in that hour
  (count-weighted mean, or hourly min for pressure-type "worst" variables),
  leaving NaN where nothing was charted.
* We then add, per stay and per core variable:
    <var>       the hourly measured value (NaN where not measured)
    <var>_ff    last-observation-carried-forward within the stay
    <var>_tsl   hours since that variable was last actually measured
  This is exactly the shape a causal, only-past-information model consumes:
  the _ff value is what you would "know" at that hour, and _tsl encodes
  irregular sampling (itself a severity signal).
* Big tables (chartevents 3.3 GB, labevents 2.4 GB) are never held whole:
  a chunked streaming aggregator accumulates per-(stay,itemid,hour) partials.

Unit handling mirrors 04: temperature F->C, FiO2 %->fraction, MAP/GCS/SpO2
clipping, GCS = sum of three components.

Output
------
processed_data/hourly_panel.parquet   (one row per stay-hour; typed, compact)
processed_data/hourly_panel_sample.csv (first ~40 stays, for eyeballing in the IDE)
"""
from __future__ import annotations

import argparse
from typing import Iterable, Sequence

import numpy as np
import pandas as pd

import config as C
import utils as U

# --------------------------------------------------------------------------- #
# Horizon
# --------------------------------------------------------------------------- #
MAX_PANEL_HOURS = 72          # right-censor each stay at 72h of ICU time
LAB_LOOKBACK_H = 6.0          # labs from intime-6h count toward hour 0

# Variable -> (itemids, hourly reduction). "mean" = count-weighted mean;
# "min"/"max" = hourly worst value. Temperature/FiO2 are handled specially.
CHART_VARS = {
    "hr":        ([220045], "mean"),
    "resp_rate": ([220210, 224690], "mean"),
    "spo2":      ([220277], "min"),
    "map":       ([220052, 220181], "min"),
    "fio2":      ([223835], "max"),
    "temp_c":    ([223762], "mean"),      # celsius itemid
    "temp_f":    ([223761], "mean"),      # fahrenheit itemid (converted below)
    "gcs_eye":   ([220739], "min"),
    "gcs_verb":  ([223900], "min"),
    "gcs_mot":   ([223901], "min"),
}
LAB_VARS = {
    "lactate":    ([50813], "max"),
    "creatinine": ([50912], "max"),
    "bilirubin":  ([50885], "max"),
    "platelets":  ([51265], "min"),
    "wbc":        ([51301, 51300], "max"),
    "pao2":       ([50821], "min"),
}
VASO = {
    "norepinephrine": 221906, "epinephrine": 221289, "dopamine": 221662,
    "dobutamine": 221653, "vasopressin": 222315, "phenylephrine": 221749,
}

# Core variables that get _ff / _tsl companions (the ones a model/SOFA needs).
CORE_VARS = ["hr", "resp_rate", "spo2", "map", "temp_c", "fio2", "gcs",
             "pao2", "pf_ratio", "lactate", "creatinine", "bilirubin",
             "platelets", "wbc"]


# --------------------------------------------------------------------------- #
# Streaming hourly aggregator (self-contained; does not touch utils' tested fns)
# --------------------------------------------------------------------------- #
def stream_hourly_agg(
    path,
    itemids: Iterable[int],
    windows: pd.DataFrame,
    key_col: str,
    time_col: str = "charttime",
    value_col: str = "valuenum",
    max_hours: int = MAX_PANEL_HOURS,
    chunksize: int = 2_000_000,
) -> pd.DataFrame:
    """
    Stream a big gzipped event table and accumulate per-(stay_id, itemid, hour)
    vmin/vmax/vsum/vcount, where hour = floor((time - intime) / 1h) and only
    hours in [0, max_hours] are kept.

    windows : DataFrame[key_col, stay_id, intime, win_end]  (datetimes).
    Returns : long DataFrame[stay_id, itemid, hour, vmin, vmax, vsum, vcount].
    """
    want = set(int(i) for i in itemids)
    wcols: list[str] = []
    for c in [key_col, "stay_id", "intime", "win_end"]:
        if c not in wcols:
            wcols.append(c)
    win = windows[wcols].copy()
    win[key_col] = pd.to_numeric(win[key_col], errors="coerce")
    win = win.dropna(subset=[key_col])
    win[key_col] = win[key_col].astype("int64")

    reader = pd.read_csv(
        path, usecols=[key_col, time_col, "itemid", value_col],
        parse_dates=[time_col],
        chunksize=chunksize, low_memory=False,
    )
    try:
        from tqdm import tqdm
        reader = tqdm(reader, desc=f"scan {path.name}", unit="chunk")
    except Exception:
        pass

    partials: list[pd.DataFrame] = []
    total = 0
    for chunk in reader:
        total += len(chunk)
        sub = chunk[chunk["itemid"].isin(want)]
        if sub.empty:
            continue
        sub = sub.dropna(subset=[key_col, value_col]).copy()
        sub[key_col] = pd.to_numeric(sub[key_col], errors="coerce")
        sub[value_col] = pd.to_numeric(sub[value_col], errors="coerce")
        sub = sub.dropna(subset=[key_col, value_col])
        if sub.empty:
            continue
        sub[key_col] = sub[key_col].astype("int64")

        m = sub.merge(win, on=key_col, how="inner")
        if m.empty:
            continue
        rel_h = (m[time_col] - m["intime"]).dt.total_seconds() / 3600.0
        m = m.assign(hour=np.floor(rel_h).astype("int64"))
        m = m[(m["hour"] >= 0) & (m["hour"] <= max_hours) &
              (m[time_col] <= m["win_end"])]
        if m.empty:
            continue
        g = m.groupby(["stay_id", "itemid", "hour"])[value_col].agg(
            vmin="min", vmax="max", vsum="sum", vcount="count").reset_index()
        partials.append(g)
        # Periodically fold partials to keep memory bounded.
        if len(partials) >= 40:
            partials = [_combine_partials(partials)]

    U.log(f"{path.name}: scanned {total:,} rows")
    if not partials:
        return pd.DataFrame(
            columns=["stay_id", "itemid", "hour", "vmin", "vmax", "vsum", "vcount"])
    return _combine_partials(partials)


def _combine_partials(partials: list[pd.DataFrame]) -> pd.DataFrame:
    allp = pd.concat(partials, ignore_index=True)
    return allp.groupby(["stay_id", "itemid", "hour"]).agg(
        vmin=("vmin", "min"), vmax=("vmax", "max"),
        vsum=("vsum", "sum"), vcount=("vcount", "sum")).reset_index()


def fold_variable(long: pd.DataFrame, itemids: Sequence[int], how: str) -> pd.Series:
    """Reduce long partials for one variable to a per-(stay_id, hour) Series."""
    sub = long[long["itemid"].isin([int(i) for i in itemids])]
    if sub.empty:
        return pd.Series(dtype="float64")
    if how == "mean":
        g = sub.groupby(["stay_id", "hour"]).agg(
            vsum=("vsum", "sum"), vcount=("vcount", "sum"))
        return (g["vsum"] / g["vcount"]).rename("value")
    if how == "min":
        return sub.groupby(["stay_id", "hour"])["vmin"].min().rename("value")
    if how == "max":
        return sub.groupby(["stay_id", "hour"])["vmax"].max().rename("value")
    raise ValueError(how)


# --------------------------------------------------------------------------- #
# Vasopressors and urine, binned to the hourly grid
# --------------------------------------------------------------------------- #
def hourly_vaso(stays: pd.DataFrame) -> pd.DataFrame:
    """Per (stay_id, hour): weight-based rates + presence flags, expanded over
    each infusion's [starttime, endtime] span."""
    win = stays.set_index("stay_id")[["intime", "win_end"]]
    keep = set(VASO.values())
    cols = ["stay_id", "itemid", "starttime", "endtime", "rate", "rateuom"]
    rows: list[pd.DataFrame] = []
    for chunk in pd.read_csv(C.FILES["inputevents"], usecols=cols,
                             parse_dates=["starttime", "endtime"],
                             chunksize=1_000_000,
                             low_memory=False):
        sub = chunk[chunk["itemid"].isin(keep)]
        sub = sub[sub["stay_id"].isin(win.index)]
        if not sub.empty:
            rows.append(sub)
    if not rows:
        return pd.DataFrame(columns=["stay_id", "hour"])
    iv = pd.concat(rows, ignore_index=True).join(win, on="stay_id")
    iv["rate"] = pd.to_numeric(iv["rate"], errors="coerce")
    iv = iv.dropna(subset=["starttime"])
    iv["endtime"] = iv["endtime"].fillna(iv["starttime"])
    # Hour span each infusion covers (clipped to [0, MAX]).
    h0 = np.floor((iv["starttime"] - iv["intime"]).dt.total_seconds() / 3600.0)
    h1 = np.floor((iv["endtime"] - iv["intime"]).dt.total_seconds() / 3600.0)
    iv["h0"] = np.clip(h0, 0, MAX_PANEL_HOURS).astype("int64")
    iv["h1"] = np.clip(h1, 0, MAX_PANEL_HOURS).astype("int64")
    iv = iv[(h1 >= 0) & (h0 <= MAX_PANEL_HOURS)]

    # Expand each row to the hours it covers.
    expanded: list[pd.DataFrame] = []
    for name, gid in VASO.items():
        g = iv[iv["itemid"] == gid]
        if g.empty:
            continue
        reps = (g["h1"] - g["h0"] + 1).clip(lower=1).astype(int)
        stay_rep = np.repeat(g["stay_id"].to_numpy(), reps)
        rate_rep = np.repeat(g["rate"].to_numpy(), reps)
        uom_rep = np.repeat(g["rateuom"].to_numpy(), reps)
        hour_rep = np.concatenate([np.arange(a, b + 1)
                                   for a, b in zip(g["h0"], g["h1"])])
        expanded.append(pd.DataFrame({
            "stay_id": stay_rep, "hour": hour_rep, "drug": name,
            "rate": rate_rep, "rateuom": uom_rep}))
    if not expanded:
        return pd.DataFrame(columns=["stay_id", "hour"])
    ex = pd.concat(expanded, ignore_index=True)
    ex["wb_rate"] = np.where(ex["rateuom"] == "mcg/kg/min", ex["rate"], np.nan)

    grp = ex.groupby(["stay_id", "hour"])
    out = pd.DataFrame(index=grp.size().index)
    ne = ex[ex["drug"].isin(["norepinephrine", "epinephrine"])]
    dop = ex[ex["drug"] == "dopamine"]
    out["norepi_epi_rate"] = ne.groupby(["stay_id", "hour"])["wb_rate"].max()
    out["dopamine_rate"] = dop.groupby(["stay_id", "hour"])["wb_rate"].max()
    out["norepi_epi_any"] = ne.groupby(["stay_id", "hour"]).size().reindex(out.index).fillna(0) > 0
    out["dopamine_any"] = dop.groupby(["stay_id", "hour"]).size().reindex(out.index).fillna(0) > 0
    out["dobutamine_any"] = ex[ex["drug"] == "dobutamine"].groupby(["stay_id", "hour"]).size().reindex(out.index).fillna(0) > 0
    out["other_vaso_any"] = ex[ex["drug"].isin(["phenylephrine", "vasopressin"])].groupby(["stay_id", "hour"]).size().reindex(out.index).fillna(0) > 0
    for c in ["norepi_epi_any", "dopamine_any", "dobutamine_any", "other_vaso_any"]:
        out[c] = out[c].fillna(False).astype(bool)
    out["vaso_any"] = out[["norepi_epi_any", "dopamine_any",
                           "dobutamine_any", "other_vaso_any"]].any(axis=1)
    return out.reset_index()


def hourly_urine(stays: pd.DataFrame) -> pd.DataFrame:
    """Per (stay_id, hour): urine volume (mL) charted in that hour."""
    win = stays.set_index("stay_id")[["intime", "win_end"]]
    keep = set(C.URINE_OUTPUT_ITEMIDS)
    cols = ["stay_id", "itemid", "charttime", "value"]
    rows: list[pd.DataFrame] = []
    for chunk in pd.read_csv(C.FILES["outputevents"], usecols=cols,
                             parse_dates=["charttime"],
                             chunksize=1_000_000, low_memory=False):
        sub = chunk[chunk["itemid"].isin(keep)]
        sub = sub[sub["stay_id"].isin(win.index)]
        if not sub.empty:
            rows.append(sub)
    if not rows:
        return pd.DataFrame(columns=["stay_id", "hour", "urine_ml"])
    oe = pd.concat(rows, ignore_index=True).join(win, on="stay_id")
    rel_h = (oe["charttime"] - oe["intime"]).dt.total_seconds() / 3600.0
    oe = oe.assign(hour=np.floor(rel_h).astype("int64"))
    oe = oe[(oe["hour"] >= 0) & (oe["hour"] <= MAX_PANEL_HOURS)]
    oe["value"] = pd.to_numeric(oe["value"], errors="coerce").clip(lower=0)
    return (oe.groupby(["stay_id", "hour"])["value"].sum()
            .rename("urine_ml").reset_index())


# --------------------------------------------------------------------------- #
# Panel assembly
# --------------------------------------------------------------------------- #
def build_grid(stays: pd.DataFrame) -> pd.DataFrame:
    """Dense (stay_id, hour) grid, hour 0..H_stay per stay."""
    h_stay = np.floor(np.minimum(stays["los_hours"].to_numpy(),
                                 float(MAX_PANEL_HOURS))).astype(int)
    h_stay = np.clip(h_stay, 0, MAX_PANEL_HOURS)
    reps = h_stay + 1
    stay_rep = np.repeat(stays["stay_id"].to_numpy(), reps)
    hour_rep = np.concatenate([np.arange(0, n) for n in reps])
    return pd.DataFrame({"stay_id": stay_rep.astype("int64"),
                         "hour": hour_rep.astype("int64")})


def add_ff_tsl(panel: pd.DataFrame, var: str) -> None:
    """Add <var>_ff (LOCF within stay) and <var>_tsl (hours since measured)."""
    g = panel.groupby("stay_id", sort=False)
    panel[f"{var}_ff"] = g[var].ffill()
    # hours since last actual measurement: 0 where measured, else grows by 1.
    measured = panel[var].notna()
    # index of last measured hour, forward-filled
    hour_when_meas = panel["hour"].where(measured)
    last_meas_hour = panel.groupby("stay_id", sort=False)
    panel[f"{var}_tsl"] = (panel["hour"]
                           - hour_when_meas.groupby(panel["stay_id"]).ffill())


def main() -> None:
    ap = argparse.ArgumentParser(description="Build the hourly patient panel.")
    ap.add_argument("--limit", type=int, default=None,
                    help="only process the first N stays (debug)")
    args = ap.parse_args()

    U.log("loading cohort ...")
    cohort = U.load("cohort", C.OUTPUT_DIR, parse_dates=["intime", "outtime"])
    cohort["hadm_id"] = pd.to_numeric(cohort["hadm_id"], errors="coerce")
    stays = cohort[["stay_id", "subject_id", "hadm_id", "intime",
                    "los_hours"]].copy()
    stays["stay_id"] = stays["stay_id"].astype("int64")
    if args.limit:
        stays = stays.head(args.limit).copy()
    stays["win_end"] = stays["intime"] + pd.Timedelta(hours=MAX_PANEL_HOURS)
    U.log(f"cohort: {len(stays):,} stays; horizon {MAX_PANEL_HOURS}h")

    chart_windows = stays[["stay_id", "intime", "win_end"]].copy()
    lab_windows = (stays.dropna(subset=["hadm_id"])
                   .assign(intime=stays["intime"] - pd.Timedelta(hours=LAB_LOOKBACK_H))
                   [["hadm_id", "stay_id", "intime", "win_end"]]
                   .drop_duplicates("hadm_id"))

    # ---- stream the big tables ----
    chart_ids = [i for ids, _ in CHART_VARS.values() for i in ids]
    U.log("streaming chartevents (slow) ...")
    chart_long = stream_hourly_agg(C.FILES["chartevents"], chart_ids,
                                   chart_windows, key_col="stay_id")
    lab_ids = [i for ids, _ in LAB_VARS.values() for i in ids]
    U.log("streaming labevents ...")
    lab_long = stream_hourly_agg(C.FILES["labevents"], lab_ids,
                                 lab_windows, key_col="hadm_id")

    # ---- fold each variable into a per-(stay,hour) column ----
    U.log("folding variables onto the hourly grid ...")
    panel = build_grid(stays).set_index(["stay_id", "hour"])

    for var, (ids, how) in CHART_VARS.items():
        s = fold_variable(chart_long, ids, how)
        panel[var] = s
    for var, (ids, how) in LAB_VARS.items():
        s = fold_variable(lab_long, ids, how)
        panel[var] = s
    panel = panel.reset_index()

    # ---- unit conversions (mirror 04) ----
    tf_as_c = (panel["temp_f"] - 32.0) * 5.0 / 9.0
    panel["temp_c"] = panel[["temp_c"]].join(tf_as_c.rename("tfc")).max(axis=1)
    panel["temp_c"] = panel["temp_c"].clip(lower=25, upper=45)
    panel = panel.drop(columns=["temp_f"])
    panel["fio2"] = panel["fio2"].where(panel["fio2"] <= 1.0,
                                        panel["fio2"] / 100.0).clip(0.21, 1.0)
    panel["map"] = panel["map"].clip(lower=10, upper=250)
    panel["spo2"] = panel["spo2"].clip(lower=0, upper=100)
    panel["gcs"] = (panel["gcs_eye"] + panel["gcs_verb"]
                    + panel["gcs_mot"]).clip(lower=3, upper=15)
    panel = panel.drop(columns=["gcs_eye", "gcs_verb", "gcs_mot"])
    panel["pf_ratio"] = panel["pao2"] / panel["fio2"]

    # ---- vasopressors + urine ----
    U.log("binning vasopressors (inputevents) ...")
    vaso = hourly_vaso(stays)
    U.log("binning urine (outputevents) ...")
    urine = hourly_urine(stays)
    if not vaso.empty:
        panel = panel.merge(vaso, on=["stay_id", "hour"], how="left")
    if not urine.empty:
        panel = panel.merge(urine, on=["stay_id", "hour"], how="left")
    for c in ["norepi_epi_any", "dopamine_any", "dobutamine_any",
              "other_vaso_any", "vaso_any"]:
        if c in panel.columns:
            panel[c] = panel[c].fillna(False).astype(bool)
        else:
            panel[c] = False
    panel["urine_ml"] = panel.get("urine_ml", pd.Series(index=panel.index)).fillna(0.0)

    # ---- forward-fill + time-since-last for the core variables ----
    U.log("computing forward-fill + time-since-last ...")
    panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
    for var in CORE_VARS:
        if var in panel.columns:
            add_ff_tsl(panel, var)

    # compact dtypes
    float_cols = panel.select_dtypes(include=["float64"]).columns
    panel[float_cols] = panel[float_cols].astype("float32")

    # ---- persist ----
    U.log("=" * 56)
    U.log(f"hourly_panel: {len(panel):,} stay-hours across "
          f"{panel['stay_id'].nunique():,} stays "
          f"(mean {len(panel)/panel['stay_id'].nunique():.1f} h/stay)")
    for v in ["hr", "map", "lactate", "gcs", "pf_ratio"]:
        cov = panel[v].notna().mean()
        U.log(f"  hourly coverage {v:<10s}: {cov:.1%} of hours measured")
    out_pq = C.OUTPUT_DIR / "hourly_panel.parquet"
    panel.to_parquet(out_pq, index=False)
    U.log(f"wrote {out_pq.name} ({U.human_size(out_pq.stat().st_size)})")
    # small CSV sample for the IDE
    sample_ids = stays["stay_id"].head(40)
    panel[panel["stay_id"].isin(sample_ids)].to_csv(
        C.OUTPUT_DIR / "hourly_panel_sample.csv", index=False)
    U.log("wrote hourly_panel_sample.csv (first 40 stays)")


if __name__ == "__main__":
    main()
