from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Enum
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from geoalchemy2 import Geometry  # The mapping engine from the web version
import enum
from .database import Base

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
    reports = relationship("Report", back_populates="owner")

class Report(Base):
    __tablename__ = "reports"
    id = Column(Integer, primary_key=True, index=True)
    description = Column(String)
    image_url = Column(String, nullable=True) 
    status = Column(String, default="pending") 
    client_timestamp = Column(DateTime(timezone=True), server_default=func.now())
    
    # 📍 POSTGIS UPGRADE: Stores coordinates as a searchable geographic point
    location = Column(Geometry(geometry_type='POINT', srid=4326))
    
    user_id = Column(Integer, ForeignKey("users.id"))
    owner = relationship("User", back_populates="reports")

class Shelter(Base):
    __tablename__ = "shelters"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    capacity = Column(Integer)
    current_occupancy = Column(Integer, default=0)
    
    # 📍 POSTGIS UPGRADE
    location = Column(Geometry(geometry_type='POINT', srid=4326))