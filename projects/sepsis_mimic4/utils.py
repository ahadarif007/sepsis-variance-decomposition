"""
utils.py
========
Reusable helpers shared across the pipeline. The important one is
`read_filtered`, which streams a large gzipped MIMIC table in chunks and keeps
only the rows you care about (e.g. a handful of itemids out of chartevents),
so you never have to load a multi-GB file into memory at once.
"""
from __future__ import annotations

import gzip
import sys
import time
from pathlib import Path
from typing import Iterable, Sequence

import pandas as pd

# Optional pretty progress bar; degrades gracefully if tqdm isn't installed.
try:
    from tqdm import tqdm
    _HAS_TQDM = True
except Exception:  # pragma: no cover
    _HAS_TQDM = False


# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
def log(msg: str) -> None:
    """Timestamped stderr log so it doesn't pollute piped stdout."""
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", file=sys.stderr, flush=True)


def human_size(num_bytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if num_bytes < 1024:
            return f"{num_bytes:,.1f} {unit}"
        num_bytes /= 1024
    return f"{num_bytes:,.1f} PB"


# --------------------------------------------------------------------------- #
# Reading
# --------------------------------------------------------------------------- #
def read_table(
    path: Path,
    columns: Sequence[str] | None = None,
    dtype: dict | None = None,
    nrows: int | None = None,
    parse_dates: Sequence[str] | None = None,
) -> pd.DataFrame:
    """Straightforward read of a (small/medium) gzipped CSV."""
    return pd.read_csv(
        path,
        usecols=columns,
        dtype=dtype,
        nrows=nrows,
        parse_dates=parse_dates,
        compression="gzip",
        low_memory=False,
    )


def read_filtered(
    path: Path,
    filter_col: str,
    keep_values: Iterable,
    columns: Sequence[str] | None = None,
    dtype: dict | None = None,
    parse_dates: Sequence[str] | None = None,
    chunksize: int = 2_000_000,
    show_progress: bool = True,
) -> pd.DataFrame:
    """
    Stream a large gzipped CSV in chunks, keeping only rows where
    `filter_col` is in `keep_values`. Returns the concatenated result.

    Example (pull only lactate + creatinine out of labevents):
        df = read_filtered(
            FILES["labevents"],
            filter_col="itemid",
            keep_values={50813, 50912},
            columns=["subject_id","hadm_id","charttime","itemid","valuenum","valueuom"],
            parse_dates=["charttime"],
        )
    """
    keep = set(keep_values)
    reader = pd.read_csv(
        path,
        usecols=columns,
        dtype=dtype,
        parse_dates=parse_dates,
        compression="gzip",
        chunksize=chunksize,
        low_memory=False,
    )

    iterator = reader
    if show_progress and _HAS_TQDM:
        iterator = tqdm(reader, desc=f"scan {path.name}", unit="chunk")

    kept: list[pd.DataFrame] = []
    total_rows = 0
    for chunk in iterator:
        total_rows += len(chunk)
        sub = chunk[chunk[filter_col].isin(keep)]
        if not sub.empty:
            kept.append(sub)

    log(f"{path.name}: scanned {total_rows:,} rows, kept "
        f"{sum(len(k) for k in kept):,}")
    if kept:
        return pd.concat(kept, ignore_index=True)
    # Return an empty frame with the right columns if nothing matched.
    return pd.DataFrame(columns=list(columns) if columns else None)


def count_rows(path: Path, chunksize: int = 5_000_000) -> int:
    """Exact row count by streaming. Slow on the biggest tables; use sparingly."""
    n = 0
    for chunk in pd.read_csv(
        path, usecols=[0], compression="gzip", chunksize=chunksize, low_memory=False
    ):
        n += len(chunk)
    return n


def peek_header(path: Path) -> list[str]:
    """Read just the CSV header line from a gzipped file."""
    with gzip.open(path, "rt") as fh:
        return fh.readline().rstrip("\n").split(",")


# --------------------------------------------------------------------------- #
# Writing
# --------------------------------------------------------------------------- #
def save(df: pd.DataFrame, name: str, out_dir: Path, fmt: str = "parquet") -> Path:
    """
    Persist a dataframe to processed_data. Parquet by default (fast + typed);
    pass fmt='csv' if you need to eyeball it in a spreadsheet.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    if fmt == "parquet":
        path = out_dir / f"{name}.parquet"
        df.to_parquet(path, index=False)
    elif fmt == "csv":
        path = out_dir / f"{name}.csv"
        df.to_csv(path, index=False)
    else:
        raise ValueError(f"Unknown fmt: {fmt}")
    log(f"wrote {path.name}  ({len(df):,} rows, {human_size(path.stat().st_size)})")
    return path


def load(name: str, out_dir: Path,
         parse_dates: Sequence[str] | None = None) -> pd.DataFrame:
    """
    Load a previously saved intermediate (tries csv then parquet).

    CSV carries no dtypes, so pass `parse_dates` for any datetime columns you
    need to do time arithmetic on — otherwise they load as strings and pandas
    will refuse `string - Timedelta`. (Parquet is already typed, so the
    argument is only applied to the CSV path.)
    """
    csv = out_dir / f"{name}.csv"
    if csv.exists():
        return pd.read_csv(csv, low_memory=False, parse_dates=parse_dates)
    pq = out_dir / f"{name}.parquet"
    if pq.exists():
        return pd.read_parquet(pq)
    raise FileNotFoundError(f"No intermediate named '{name}' in {out_dir}")


# --------------------------------------------------------------------------- #
# Dictionary helpers
# --------------------------------------------------------------------------- #
def load_dict_items(path: Path) -> pd.DataFrame:
    """Load d_items (icu) — itemid -> label/linksto/category/unit."""
    return read_table(path)


def search_labels(d: pd.DataFrame, terms: Iterable[str],
                  label_col: str = "label") -> pd.DataFrame:
    """Case-insensitive substring search over a dictionary's label column."""
    labels = d[label_col].astype("string").str.lower()
    mask = pd.Series(False, index=d.index)
    for t in terms:
        mask |= labels.str.contains(t.lower(), na=False, regex=False)
    return d[mask]


def match_antibiotics(drug_series: pd.Series, antibiotics: Sequence[str]) -> pd.Series:
    """Boolean mask: True where a drug name contains any antibiotic substring."""
    drug = drug_series.astype("string").str.lower()
    mask = pd.Series(False, index=drug.index)
    for ab in antibiotics:
        mask |= drug.str.contains(ab, na=False, regex=False)
    return mask


# --------------------------------------------------------------------------- #
# Streaming windowed aggregation (for the big event tables)
# --------------------------------------------------------------------------- #
def stream_windowed_agg(
    path: Path,
    itemids: Iterable[int],
    windows: pd.DataFrame,
    key_col: str = "stay_id",
    time_col: str = "charttime",
    value_col: str = "valuenum",
    chunksize: int = 2_000_000,
    show_progress: bool = True,
) -> pd.DataFrame:
    """
    Memory-safe per-(stay_id, itemid) aggregation over a per-stay time window.

    Streams a large gzipped event table in chunks. For each chunk it keeps only
    rows whose `itemid` is requested, joins them to `windows` on `key_col`, drops
    rows whose `time_col` falls outside that stay's [win_start, win_end], and
    accumulates partial min / max / sum / count per (stay_id, itemid). The
    partials are combined at the end, so the full table is never held in memory.

    Parameters
    ----------
    windows : DataFrame with columns [key_col, "stay_id", "win_start", "win_end"].
              `key_col` is the column the event table joins on:
                - chartevents / inputevents / outputevents -> "stay_id"
                - labevents (no stay_id) -> "hadm_id"
              win_start / win_end must be datetimes.

    Returns
    -------
    DataFrame[stay_id, itemid, vmin, vmax, vmean, vcount]  (long format).
    """
    path = Path(path)
    want = set(int(i) for i in itemids)
    # Dedupe column list so key_col == "stay_id" (chartevents) doesn't double-select.
    wcols: list[str] = []
    for c in [key_col, "stay_id", "win_start", "win_end"]:
        if c not in wcols:
            wcols.append(c)
    win = windows[wcols].copy()
    win[key_col] = pd.to_numeric(win[key_col], errors="coerce")
    win = win.dropna(subset=[key_col])
    win[key_col] = win[key_col].astype("int64")

    usecols = [key_col, time_col, "itemid", value_col]
    reader = pd.read_csv(
        path, usecols=usecols, parse_dates=[time_col],
        compression="gzip", chunksize=chunksize, low_memory=False,
    )
    if show_progress and _HAS_TQDM:
        reader = tqdm(reader, desc=f"scan {path.name}", unit="chunk")

    partials: list[pd.DataFrame] = []
    total = 0
    for chunk in reader:
        total += len(chunk)
        sub = chunk[chunk["itemid"].isin(want)]
        if sub.empty:
            continue
        sub = sub.dropna(subset=[key_col, value_col]).copy()
        if sub.empty:
            continue
        sub[key_col] = pd.to_numeric(sub[key_col], errors="coerce")
        sub[value_col] = pd.to_numeric(sub[value_col], errors="coerce")
        sub = sub.dropna(subset=[key_col, value_col])
        sub[key_col] = sub[key_col].astype("int64")

        m = sub.merge(win, on=key_col, how="inner")
        if m.empty:
            continue
        in_win = (m[time_col] >= m["win_start"]) & (m[time_col] <= m["win_end"])
        m = m[in_win]
        if m.empty:
            continue

        g = m.groupby(["stay_id", "itemid"])[value_col].agg(
            vmin="min", vmax="max", vsum="sum", vcount="count"
        ).reset_index()
        partials.append(g)

    if not partials:
        log(f"{path.name}: scanned {total:,} rows, kept 0 in-window")
        return pd.DataFrame(
            columns=["stay_id", "itemid", "vmin", "vmax", "vmean", "vcount"]
        )

    allp = pd.concat(partials, ignore_index=True)
    out = allp.groupby(["stay_id", "itemid"]).agg(
        vmin=("vmin", "min"), vmax=("vmax", "max"),
        vsum=("vsum", "sum"), vcount=("vcount", "sum"),
    ).reset_index()
    out["vmean"] = out["vsum"] / out["vcount"]
    out = out.drop(columns=["vsum"])
    log(f"{path.name}: scanned {total:,} rows, "
        f"{out['stay_id'].nunique():,} stays x {out['itemid'].nunique()} itemids")
    return out[["stay_id", "itemid", "vmin", "vmax", "vmean", "vcount"]]
