"""Observation ingestion + immediate sepsis scoring endpoint."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import load_model_config, get_settings
from ..core.feature_engine import build_feature_vector
from ..core.scoring import compute_risk_score, is_sepsis_risk
from ..db.database import get_db
from ..db.models import Observation, Score, Stay
from ..schemas.observation import (
    ObservationIn,
    ObservationBatchIn,
    SepsisResult,
    UNIT_RANGES,
)

router = APIRouter(prefix="/api/v1", tags=["observations"])


def _ensure_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def _normalize_observation(obs: ObservationIn) -> tuple[str, float]:
    """Apply unit conversions. Returns (canonical_parameter, normalized_value)."""
    param = obs.parameter
    value = obs.value

    if param == "temp_c" and value > 50:
        value = (value - 32) * 5.0 / 9.0

    if param == "fio2" and value > 1.0:
        value = value / 100.0
        value = max(0.21, min(1.0, value))

    if param == "map":
        value = max(10.0, min(250.0, value))

    if param == "gcs_total":
        value = max(3.0, min(15.0, value))

    if param in UNIT_RANGES:
        lo, hi = UNIT_RANGES[param]
        if value < lo or value > hi:
            raise HTTPException(
                status_code=422,
                detail=f"{param} value {value} outside valid range [{lo}, {hi}]",
            )

    return param, value


async def _score_patient(stay: Stay, db: AsyncSession) -> SepsisResult:
    """Fetch all observations for a stay, build features, and score."""
    model_config = load_model_config()
    settings = get_settings()

    result = await db.execute(
        select(Observation)
        .where(Observation.stay_id == stay.stay_id)
        .order_by(Observation.timestamp)
    )
    obs_rows = result.scalars().all()

    if not obs_rows:
        raise HTTPException(status_code=400, detail="No observations found for this stay")

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
    threshold_value = model_config.get(
        f"threshold_{threshold_name}", model_config.get("threshold_youden", 0.033)
    )

    score_record = Score(
        stay_id=stay.stay_id,
        patient_id=stay.patient_id,
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

    return SepsisResult(
        patient_id=stay.patient_id,
        stay_id=stay.stay_id,
        risk_score=round(risk_score, 6),
        sepsis_risk=sepsis_flag,
        threshold_used=threshold_name,
        threshold_value=threshold_value,
        hours_since_admission=round(hours_since_adm, 2),
        sofa_total=int(feature_vector["sofa_total"]),
        scored_at=now,
        feature_vector=feature_vector,
    )


@router.post("/observations", response_model=SepsisResult)
async def ingest_observation(obs: ObservationIn, db: AsyncSession = Depends(get_db)):
    """Ingest a single observation and return immediate sepsis risk assessment."""
    param, value = _normalize_observation(obs)

    stay = await db.get(Stay, obs.stay_id)
    if stay is None:
        raise HTTPException(
            status_code=404,
            detail=f"Stay '{obs.stay_id}' not found. Register it first via POST /api/v1/stays",
        )

    observation = Observation(
        stay_id=obs.stay_id,
        patient_id=obs.patient_id,
        timestamp=obs.timestamp,
        parameter=param,
        value=value,
        source=obs.source,
    )
    db.add(observation)
    await db.flush()

    return await _score_patient(stay, db)


@router.post("/observations/batch", response_model=list[SepsisResult])
async def ingest_batch(batch: ObservationBatchIn, db: AsyncSession = Depends(get_db)):
    """Ingest a batch of observations. Returns one sepsis result per affected stay."""
    stay_ids = set()

    for obs in batch.observations:
        param, value = _normalize_observation(obs)
        observation = Observation(
            stay_id=obs.stay_id,
            patient_id=obs.patient_id,
            timestamp=obs.timestamp,
            parameter=param,
            value=value,
            source=obs.source,
        )
        db.add(observation)
        stay_ids.add(obs.stay_id)

    await db.flush()

    results = []
    for stay_id in stay_ids:
        stay = await db.get(Stay, stay_id)
        if stay is None:
            continue
        result = await _score_patient(stay, db)
        results.append(result)

    return results
