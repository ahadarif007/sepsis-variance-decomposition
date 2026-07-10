from datetime import datetime, timezone

from sqlalchemy import (
    Boolean, Column, DateTime, Float, Integer, JSON, SmallInteger,
    String, Text, func,
)

from .database import Base


class Stay(Base):
    __tablename__ = "stays"

    stay_id = Column(String(100), primary_key=True)
    patient_id = Column(String(100), nullable=False, index=True)
    admission_time = Column(DateTime(timezone=True), nullable=False)
    discharge_time = Column(DateTime(timezone=True), nullable=True)
    age = Column(SmallInteger, nullable=False)
    sex = Column(String(1), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Observation(Base):
    __tablename__ = "observations"

    id = Column(Integer, primary_key=True, autoincrement=True)
    stay_id = Column(String(100), nullable=False, index=True)
    patient_id = Column(String(100), nullable=False, index=True)
    timestamp = Column(DateTime(timezone=True), nullable=False)
    parameter = Column(String(50), nullable=False)
    value = Column(Float, nullable=False)
    source = Column(String(100), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Score(Base):
    __tablename__ = "scores"

    id = Column(Integer, primary_key=True, autoincrement=True)
    stay_id = Column(String(100), nullable=False, index=True)
    patient_id = Column(String(100), nullable=False, index=True)
    scored_at = Column(DateTime(timezone=True), server_default=func.now())
    hours_since_adm = Column(Float, nullable=False)
    risk_score = Column(Float, nullable=False)
    sepsis_risk = Column(Boolean, nullable=False)
    sofa_total = Column(SmallInteger, nullable=True)
    threshold_used = Column(String(30), nullable=False)
    model_version = Column(String(100), nullable=False)
    feature_vector = Column(JSON, nullable=False)
