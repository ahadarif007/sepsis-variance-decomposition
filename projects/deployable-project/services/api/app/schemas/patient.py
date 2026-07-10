from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class StayIn(BaseModel):
    patient_id: str = Field(..., min_length=1, max_length=100)
    stay_id: str = Field(..., min_length=1, max_length=100)
    admission_time: datetime
    age: int = Field(..., ge=0, le=150)
    sex: str = Field(..., pattern=r"^[MFmf]$")


class StayOut(BaseModel):
    patient_id: str
    stay_id: str
    admission_time: datetime
    age: int
    sex: str
    is_active: bool
    created_at: datetime
