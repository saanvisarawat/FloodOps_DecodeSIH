import datetime
import enum
from typing import Optional, List, Dict, Any

from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Enum, JSON
from sqlalchemy.orm import relationship, Mapped, mapped_column
from sqlalchemy.sql import func
from geoalchemy2 import Geometry

from .database import Base


# ==========================================
# ENUMS & EXISTING CORE MODELS
# ==========================================

class UserRole(str, enum.Enum):
    citizen = "citizen"
    volunteer = "volunteer"
    official = "official"


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String, index=True)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    role = Column(Enum(UserRole), default=UserRole.citizen)
    status = Column(String, default="available")  # available, busy, offline
    skills = Column(String, nullable=True)        # e.g., "boat,medical,swimming"
    last_known_location = Column(Geometry(geometry_type='POINT', srid=4326), nullable=True)
    fcm_token = Column(String, nullable=True)
    
    reports = relationship("Report", foreign_keys="[Report.user_id]", back_populates="owner")
    assigned_reports = relationship("Report", foreign_keys="[Report.assigned_volunteer_id]", back_populates="assigned_volunteer")


class Report(Base):
    __tablename__ = "reports"

    id = Column(Integer, primary_key=True, index=True)
    description = Column(String)
    
    yes_count = Column(Integer, default=0)
    no_count = Column(Integer, default=0)
    
    status = Column(String, default="pending") 
    client_timestamp = Column(DateTime(timezone=True), server_default=func.now())
    location = Column(Geometry(geometry_type='POINT', srid=4326))
    
    user_id = Column(Integer, ForeignKey("users.id"))
    owner = relationship("User", foreign_keys=[user_id], back_populates="reports")
    assigned_volunteer_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    assigned_volunteer = relationship("User", foreign_keys=[assigned_volunteer_id], back_populates="assigned_reports")


class Shelter(Base):
    __tablename__ = "shelters"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    capacity = Column(Integer)
    current_occupancy = Column(Integer, default=0)
    location = Column(Geometry(geometry_type='POINT', srid=4326))


# ==========================================
# AGENTS & ML PREDICTION MODELS
# ==========================================

class PredictionRecord(Base):
    __tablename__ = "predictions"

    id: Mapped[int] = mapped_column(primary_key=True)
    district: Mapped[str] = mapped_column(index=True)
    final_jjas: Mapped[float]
    final_annual: Mapped[float]
    risk_class: Mapped[int]


class AlertRecord(Base):
    __tablename__ = "alerts"

    id: Mapped[int] = mapped_column(primary_key=True)
    district: Mapped[str] = mapped_column(index=True)
    alert_level: Mapped[str] 
    message: Mapped[str]
    helpline: Mapped[Optional[str]] = mapped_column(nullable=True)


class AgentRunLog(Base):
    __tablename__ = "agent_run_logs"

    id: Mapped[int] = mapped_column(primary_key=True)
    run_id: Mapped[str] = mapped_column(unique=True, index=True)
    district: Mapped[str] = mapped_column(index=True)
    status: Mapped[str]
    coordinator_summary: Mapped[str]
    execution_chain: Mapped[List[Dict[str, Any]]] = mapped_column(JSON)
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime, default=datetime.datetime.utcnow)