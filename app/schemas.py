from pydantic import BaseModel, ConfigDict
from typing import Optional, List, Dict, Any
from datetime import datetime

class ReportCreate(BaseModel):
    description: str
    latitude: float
    longitude: float
    user_id: int  # For now, we manually pass the user ID until we set up login

class ReportVerify(BaseModel):
    is_verified: bool

class UserCreate(BaseModel):
    full_name: str
    email: str
    password: str

class UserLogin(BaseModel):
    email: str
    password: str

class BulkReportItem(BaseModel):
    description: str
    latitude: float
    longitude: float
    client_timestamp: datetime

class BulkReportUpload(BaseModel):
    reports: List[BulkReportItem]
class RiskPredictionRequest(BaseModel):
    rainfall_mm: float
    river_discharge: float
    elevation_m: float
    slope_deg: float
    dist_nearest_river_km: float
    rainfall_mm_3d_sum: float
    rainfall_mm_7d_sum: float
    rainfall_mm_15d_sum: float
    river_discharge_3d_sum: float
    river_discharge_7d_sum: float
    river_discharge_15d_sum: float
    historical_flood_count: float

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default"

class VolunteerLocationUpdate(BaseModel):
    latitude: float
    longitude: float
    status: str = "available"  # available / busy / offline
    skills: Optional[str] = None  # e.g., "boat,medical,swimming"

class PredictionResponse(BaseModel):
    id: int
    district: str
    risk_class: int
    
    model_config = ConfigDict(from_attributes=True)

class AlertResponse(BaseModel):
    id: int
    district: str
    alert_level: str
    message: str
    
    model_config = ConfigDict(from_attributes=True)

class AgentRunLogResponse(BaseModel):
    id: int
    run_id: str
    district: str
    status: str
    coordinator_summary: str
    execution_chain: List[Dict[str, Any]]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)