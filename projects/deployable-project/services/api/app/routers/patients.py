"""Patient management and sepsis status lookup endpoints."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import load_model_config, get_settings
from ..core.feature_engine import build_feature_vector
from ..core.scoring import compute_risk_score, is_sepsis_risk
from ..db.database import get_db
from ..db.models import Observation, Score, Stay
from ..schemas.observation import PatientSepsisStatus
from ..schemas.patient import StayIn, StayOut

router = APIRouter(prefix="/api/v1", tags=["patients"])


def _ensure_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


@router.post("/stays", response_model=StayOut, status_code=201)
async def register_stay(stay_in: StayIn, db: AsyncSession = Depends(get_db)):
    """Register a new ICU stay. Must be called before ingesting observations."""
    existing = await db.get(Stay, stay_in.stay_id)
    if existing is not None:
        raise HTTPException(status_code=409, detail=f"Stay '{stay_in.stay_id}' already exists")

    stay = Stay(
        stay_id=stay_in.stay_id,
        patient_id=stay_in.patient_id,
        admission_time=stay_in.admission_time,
        age=stay_in.age,
        sex=stay_in.sex.upper(),
        is_active=True,
    )
    db.add(stay)
    await db.commit()
    await db.refresh(stay)

    return StayOut(
        patient_id=stay.patient_id,
        stay_id=stay.stay_id,
        admission_time=stay.admission_time,
        age=stay.age,
        sex=stay.sex,
        is_active=stay.is_active,
        created_at=stay.created_at,
    )


@router.post("/stays/{stay_id}/discharge")
async def discharge_stay(stay_id: str, db: AsyncSession = Depends(get_db)):
    """Mark a stay as discharged."""
    stay = await db.get(Stay, stay_id)
    if stay is None:
        raise HTTPException(status_code=404, detail=f"Stay '{stay_id}' not found")

    stay.is_active = False
    stay.discharge_time = datetime.now(timezone.utc)
    await db.commit()

    return {"stay_id": stay_id, "status": "discharged"}


@router.get("/patients/{patient_id}/sepsis-status", response_model=PatientSepsisStatus)
async def get_sepsis_status(patient_id: str, db: AsyncSession = Depends(get_db)):
    """Check if a patient is at risk of sepsis. Returns a boolean answer.

    Finds the patient's most recent active stay, computes features from
    all stored observations, scores them, and returns the result.
    """
    result = await db.execute(
        select(Stay)
        .where(Stay.patient_id == patient_id, Stay.is_active == True)
        .order_by(Stay.admission_time.desc())
        .limit(1)
    )
    stay = result.scalar_one_or_none()

    if stay is None:
        return PatientSepsisStatus(
            patient_id=patient_id,
            stay_id=None,
            sepsis_risk=False,
            risk_score=None,
            scored_at=None,
            hours_since_admission=None,
            message="No active ICU stay found for this patient",
        )

    obs_result = await db.execute(
        select(Observation)
        .where(Observation.stay_id == stay.stay_id)
        .order_by(Observation.timestamp)
    )
    obs_rows = obs_result.scalars().all()

    if not obs_rows:
        return PatientSepsisStatus(
            patient_id=patient_id,
            stay_id=stay.stay_id,
            sepsis_risk=False,
            risk_score=None,
            scored_at=None,
            hours_since_admission=None,
            message="No observations recorded yet for this stay",
        )

    model_config = load_model_config()
    settings = get_settings()
    adm_time = _ensure_utc(stay.admission_time)

    observations = [
        {"timestamp": _ensure_utc(o.timestamp), "parameter": o.parameter, "value": o.value}
        for o in obs_rows
    ]

    latest_obs_time = max(o["timestamp"] for o in observations)
    now = max(latest_obs_time, datetime.now(timezone.utc))
    hours_since_adm = (now - adm_time).total_seconds() / 3600

    feature_vector = build_feature_vector(
        observations=observations,
        admission_time=adm_time,
        age=stay.age,
        sex=stay.sex,
        model_config=model_config,
    )

    risk_score = compute_risk_score(feature_vector, model_config, hours_since_adm)
    threshold_name = settings.scoring_threshold
    sepsis_flag = is_sepsis_risk(risk_score, model_config, threshold=threshold_name)

    score_record = Score(
        stay_id=stay.stay_id,
        patient_id=patient_id,
        hours_since_adm=hours_since_adm,
        risk_score=risk_score,
        sepsis_risk=sepsis_flag,
        sofa_total=int(feature_vector["sofa_total"]),
        threshold_used=threshold_name,
        model_version=model_config["model_name"],
        feature_vector=feature_vector,
    )
    db.add(score_record)
    await db.commit()

    return PatientSepsisStatus(
        patient_id=patient_id,
        stay_id=stay.stay_id,
        sepsis_risk=sepsis_flag,
        risk_score=round(risk_score, 6),
        scored_at=now,
        hours_since_admission=round(hours_since_adm, 2),
        message="Sepsis risk detected" if sepsis_flag else "No sepsis risk detected",
    )


@router.get("/stays/active", response_model=list[StayOut])
async def list_active_stays(db: AsyncSession = Depends(get_db)):
    """List all currently active ICU stays."""
    result = await db.execute(
        select(Stay).where(Stay.is_active == True).order_by(Stay.admission_time.desc())
    )
    stays = result.scalars().all()
    return [
        StayOut(
            patient_id=s.patient_id,
            stay_id=s.stay_id,
            admission_time=s.admission_time,
            age=s.age,
            sex=s.sex,
            is_active=s.is_active,
            created_at=s.created_at,
        )
        for s in stays
    ]
