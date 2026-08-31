from pydantic import BaseModel
from typing import Optional, List
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

# --- Phase 3: AI Predictive Risk Schema ---
class RiskPredictionRequest(BaseModel):
    rainfall_mm: float
    rain_3d_sum: float
    rain_7d_sum: float
    rain_15d_sum: float
    mean_elevation_m: float
    mean_slope_deg: float
    dist_nearest_river_km: float
    impervious_surface_pct: float
    historical_flood_count: float
    days_since_last_flood: float
    state_norm: str

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default"

# --- Phase 4: Volunteer Location & Tracking Schema ---
class VolunteerLocationUpdate(BaseModel):
    latitude: float
    longitude: float
    status: str = "available"  # available / busy / offline
    skills: Optional[str] = None  # e.g., "boat,medical,swimming"