"""Feature engine: transforms raw observations into the 26-feature scoring vector.

Reproduces the exact feature definitions from the research pipeline:
- Forward-filled (LOCF) vitals and labs
- Informative missingness binary flags (1 = NOT measured, 0 = measured)
- 6-hour trajectory slopes
- qSOFA, SIRS, and total SOFA scores
"""

from datetime import datetime, timedelta
from typing import Optional

from .sofa import compute_sofa


def compute_qsofa(
    resp_rate: Optional[float],
    gcs: Optional[float],
    map_val: Optional[float],
) -> int:
    score = 0
    if resp_rate is not None and resp_rate >= 22:
        score += 1
    if gcs is not None and gcs < 15:
        score += 1
    if map_val is not None and map_val < 70:
        score += 1
    return score


def compute_sirs(
    hr: Optional[float],
    resp_rate: Optional[float],
    temp_c: Optional[float],
    wbc: Optional[float],
) -> int:
    score = 0
    if hr is not None and hr > 90:
        score += 1
    if resp_rate is not None and resp_rate > 20:
        score += 1
    if temp_c is not None and (temp_c < 36 or temp_c > 38):
        score += 1
    if wbc is not None and (wbc < 4 or wbc > 12):
        score += 1
    return score


def build_feature_vector(
    observations: list[dict],
    admission_time: datetime,
    age: int,
    sex: str,
    model_config: dict,
) -> dict:
    """Build the 26-feature vector from a list of observations.

    Each observation is a dict with keys: timestamp, parameter, value.
    Missingness convention: _msg = 1 means the value was NOT measured.
    """
    now = max((obs["timestamp"] for obs in observations), default=admission_time)
    hours_since_adm = (now - admission_time).total_seconds() / 3600

    latest = _get_latest_values(observations)
    six_hours_ago = now - timedelta(hours=6)
    values_6h_ago = _get_values_at_time(observations, six_hours_ago)

    has_vasopressor = any(
        obs["parameter"]
        in ("norepinephrine", "epinephrine", "dopamine", "dobutamine", "vasopressin", "phenylephrine")
        for obs in observations
    )

    hr = latest.get("heart_rate")
    resp_rate = latest.get("resp_rate")
    map_val = latest.get("map")
    spo2 = latest.get("spo2")
    temp_c = latest.get("temp_c")
    gcs = latest.get("gcs_total")
    lactate = latest.get("lactate")
    creatinine = latest.get("creatinine")
    wbc = latest.get("wbc")
    platelets = latest.get("platelets")
    bilirubin = latest.get("bilirubin")
    pao2 = latest.get("pao2")
    fio2 = latest.get("fio2")

    pf_ratio = None
    if pao2 is not None and fio2 is not None and fio2 > 0:
        pf_ratio = pao2 / fio2
    elif latest.get("pf_ratio") is not None:
        pf_ratio = latest.get("pf_ratio")

    sofa_total = compute_sofa(
        pf_ratio=pf_ratio,
        platelets=platelets,
        bilirubin=bilirubin,
        map_val=map_val,
        vasopressor_active=has_vasopressor,
        gcs=gcs,
        creatinine=creatinine,
    )
    qsofa = compute_qsofa(resp_rate, gcs, map_val)
    sirs = compute_sirs(hr, resp_rate, temp_c, wbc)

    # Missingness flags: 1 = NOT measured, 0 = measured
    measured_params = set(obs["parameter"] for obs in observations)
    lactate_msg = 0.0 if "lactate" in measured_params else 1.0
    creatinine_msg = 0.0 if "creatinine" in measured_params else 1.0
    wbc_msg = 0.0 if "wbc" in measured_params else 1.0
    pf_ratio_msg = 0.0 if ("pao2" in measured_params or "pf_ratio" in measured_params) else 1.0

    # 6-hour trajectory slopes
    hr_now = latest.get("heart_rate")
    hr_prev = values_6h_ago.get("heart_rate")
    resp_now = latest.get("resp_rate")
    resp_prev = values_6h_ago.get("resp_rate")
    map_now = latest.get("map")
    map_prev = values_6h_ago.get("map")
    spo2_now = latest.get("spo2")
    spo2_prev = values_6h_ago.get("spo2")

    can_compute_hr = hr_now is not None and hr_prev is not None
    can_compute_resp = resp_now is not None and resp_prev is not None
    can_compute_map = map_now is not None and map_prev is not None
    can_compute_spo2 = spo2_now is not None and spo2_prev is not None

    hr_slope6 = (hr_now - hr_prev) if can_compute_hr else 0.0
    resp_slope6 = (resp_now - resp_prev) if can_compute_resp else 0.0
    map_slope6 = (map_now - map_prev) if can_compute_map else 0.0
    spo2_slope6 = (spo2_now - spo2_prev) if can_compute_spo2 else 0.0

    # Slope missingness: 1 = CANNOT compute, 0 = can compute
    hr_slope6_msg = 0.0 if can_compute_hr else 1.0
    resp_slope6_msg = 0.0 if can_compute_resp else 1.0
    map_slope6_msg = 0.0 if can_compute_map else 1.0
    spo2_slope6_msg = 0.0 if can_compute_spo2 else 1.0

    # Imputation
    medians = model_config.get("imputation_medians", {})

    feature_vector = {
        "hr": hr if hr is not None else medians.get("hr", 81.0),
        "resp_rate": resp_rate if resp_rate is not None else medians.get("resp_rate", 18.0),
        "map": map_val if map_val is not None else medians.get("map", 78.0),
        "spo2": spo2 if spo2 is not None else medians.get("spo2", 97.0),
        "temp_c": temp_c if temp_c is not None else medians.get("temp_c", 36.83),
        "gcs": gcs if gcs is not None else medians.get("gcs", 15.0),
        "sofa_total": float(sofa_total),
        "qsofa": float(qsofa),
        "sirs": float(sirs),
        "lactate_msg": lactate_msg,
        "lactate": lactate if lactate is not None else medians.get("lactate", 1.6),
        "creatinine_msg": creatinine_msg,
        "creatinine": creatinine if creatinine is not None else medians.get("creatinine", 0.9),
        "wbc_msg": wbc_msg,
        "wbc": wbc if wbc is not None else medians.get("wbc", 10.4),
        "pf_ratio_msg": pf_ratio_msg,
        "pf_ratio": pf_ratio if pf_ratio is not None else medians.get("pf_ratio", 407.0),
        "hr_slope6_msg": hr_slope6_msg,
        "hr_slope6": hr_slope6,
        "resp_rate_slope6_msg": resp_slope6_msg,
        "resp_rate_slope6": resp_slope6,
        "map_slope6_msg": map_slope6_msg,
        "map_slope6": map_slope6,
        "spo2_slope6_msg": spo2_slope6_msg,
        "spo2_slope6": spo2_slope6,
        "age": float(age),
        "female": 1.0 if sex.upper() == "F" else 0.0,
    }

    return feature_vector


def _get_latest_values(observations: list[dict]) -> dict:
    """Get the most recent value for each parameter (LOCF)."""
    latest = {}
    sorted_obs = sorted(observations, key=lambda x: x["timestamp"])
    for obs in sorted_obs:
        latest[obs["parameter"]] = obs["value"]
    return latest


def _get_values_at_time(observations: list[dict], target_time: datetime) -> dict:
    """Get the most recent value for each parameter at or before target_time."""
    values = {}
    for obs in sorted(observations, key=lambda x: x["timestamp"]):
        if obs["timestamp"] <= target_time:
            values[obs["parameter"]] = obs["value"]
    return values
