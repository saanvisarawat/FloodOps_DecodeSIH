from pydantic import BaseModel
from typing import Optional

class ReportCreate(BaseModel):
    description: str
    latitude: float
    longitude: float
    image_url: Optional[str] = None
    user_id: int  # For now, we manually pass the user ID until we set up login

class UserCreate(BaseModel):
    full_name: str
    email: str
    password: str

class UserLogin(BaseModel):
    email: str
    password: str