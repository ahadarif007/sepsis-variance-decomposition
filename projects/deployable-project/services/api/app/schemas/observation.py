import math
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator

VALID_PARAMETERS = {
    "heart_rate", "sbp", "dbp", "map", "resp_rate", "spo2", "temp_c", "gcs_total",
    "lactate", "creatinine", "wbc", "platelets", "bilirubin", "pao2", "fio2", "pf_ratio",
    "norepinephrine", "epinephrine", "dopamine", "dobutamine", "vasopressin", "phenylephrine",
    "urine_output",
}

UNIT_RANGES = {
    "heart_rate": (0, 300),
    "sbp": (0, 350),
    "dbp": (0, 250),
    "map": (10, 250),
    "resp_rate": (0, 80),
    "spo2": (0, 100),
    "temp_c": (25, 45),
    "gcs_total": (3, 15),
    "lactate": (0, 50),
    "creatinine": (0, 30),
    "wbc": (0, 200),
    "platelets": (0, 1500),
    "bilirubin": (0, 60),
    "pao2": (0, 700),
    "fio2": (0.21, 1.0),
    "pf_ratio": (0, 700),
    "urine_output": (0, 5000),
}


class ObservationIn(BaseModel):
    patient_id: str = Field(..., min_length=1, max_length=100)
    stay_id: str = Field(..., min_length=1, max_length=100)
    timestamp: datetime
    parameter: str
    value: float
    unit: Optional[str] = None
    source: Optional[str] = None

    @field_validator("parameter")
    @classmethod
    def validate_parameter(cls, v: str) -> str:
        v = v.lower().strip()
        if v not in VALID_PARAMETERS:
            raise ValueError(f"Unknown parameter '{v}'. Valid: {sorted(VALID_PARAMETERS)}")
        return v

    @field_validator("value")
    @classmethod
    def validate_value(cls, v: float) -> float:
        if not math.isfinite(v):
            raise ValueError("Value must be finite")
        return v


class ObservationBatchIn(BaseModel):
    observations: list[ObservationIn] = Field(..., min_length=1, max_length=1000)


class SepsisResult(BaseModel):
    patient_id: str
    stay_id: str
    risk_score: float
    sepsis_risk: bool
    threshold_used: str
    threshold_value: float
    hours_since_admission: float
    sofa_total: int
    scored_at: datetime
    feature_vector: dict


class PatientSepsisStatus(BaseModel):
    patient_id: str
    stay_id: Optional[str]
    sepsis_risk: bool
    risk_score: Optional[float]
    scored_at: Optional[datetime]
    hours_since_admission: Optional[float]
    message: str
