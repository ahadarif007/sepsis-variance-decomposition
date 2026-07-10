"""SOFA organ sub-score calculations.

Implements the Sequential Organ Failure Assessment score
per Vincent et al. (1996), using the same thresholds as the
research pipeline (05_sofa_sepsis3.py).
"""

from typing import Optional


def respiration_score(pf_ratio: Optional[float]) -> int:
    if pf_ratio is None:
        return 0
    if pf_ratio < 100:
        return 4
    if pf_ratio < 200:
        return 3
    if pf_ratio < 300:
        return 2
    if pf_ratio < 400:
        return 1
    return 0


def coagulation_score(platelets: Optional[float]) -> int:
    if platelets is None:
        return 0
    if platelets < 20:
        return 4
    if platelets < 50:
        return 3
    if platelets < 100:
        return 2
    if platelets < 150:
        return 1
    return 0


def liver_score(bilirubin: Optional[float]) -> int:
    if bilirubin is None:
        return 0
    if bilirubin >= 12.0:
        return 4
    if bilirubin >= 6.0:
        return 3
    if bilirubin >= 2.0:
        return 2
    if bilirubin >= 1.2:
        return 1
    return 0


def cardiovascular_score(
    map_val: Optional[float], vasopressor_active: bool = False
) -> int:
    if vasopressor_active:
        return 3
    if map_val is None:
        return 0
    if map_val < 70:
        return 1
    return 0


def cns_score(gcs: Optional[float]) -> int:
    if gcs is None:
        return 0
    if gcs < 6:
        return 4
    if gcs < 10:
        return 3
    if gcs < 13:
        return 2
    if gcs < 15:
        return 1
    return 0


def renal_score(creatinine: Optional[float], urine_24h: Optional[float] = None) -> int:
    score = 0
    if creatinine is not None:
        if creatinine >= 5.0:
            score = 4
        elif creatinine >= 3.5:
            score = 3
        elif creatinine >= 2.0:
            score = 2
        elif creatinine >= 1.2:
            score = 1
    if urine_24h is not None:
        if urine_24h < 200:
            score = max(score, 4)
        elif urine_24h < 500:
            score = max(score, 3)
    return score


def compute_sofa(
    pf_ratio: Optional[float] = None,
    platelets: Optional[float] = None,
    bilirubin: Optional[float] = None,
    map_val: Optional[float] = None,
    vasopressor_active: bool = False,
    gcs: Optional[float] = None,
    creatinine: Optional[float] = None,
    urine_24h: Optional[float] = None,
) -> int:
    return (
        respiration_score(pf_ratio)
        + coagulation_score(platelets)
        + liver_score(bilirubin)
        + cardiovascular_score(map_val, vasopressor_active)
        + cns_score(gcs)
        + renal_score(creatinine, urine_24h)
    )
