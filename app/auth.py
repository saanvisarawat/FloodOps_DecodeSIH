import os
from datetime import datetime, timedelta
from jose import JWTError, jwt
import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from .database import get_db
from . import models

# Load secret from environment variables to prevent security flaws in production
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "floodops_super_secret_hackathon_key_2026")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 1440  # Tokens last 24 hours

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/auth/login")

def hash_password(password: str):
    pwd_bytes = password.encode('utf-8')[:72]
    hashed = bcrypt.hashpw(pwd_bytes, bcrypt.gensalt())
    return hashed.decode('utf-8')

def verify_password(plain_password: str, hashed_password: str):
    pwd_bytes = plain_password.encode('utf-8')[:72]
    return bcrypt.checkpw(pwd_bytes, hashed_password.encode('utf-8'))

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        role: str = payload.get("role")
        if email is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
        
    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None:
        raise credentials_exception
    return user

def require_official(current_user: models.User = Depends(get_current_user)):
    if current_user.role != models.UserRole.official:
        raise HTTPException(status_code=403, detail="Access denied: Flood Officials only.")
    return current_user

def require_volunteer(current_user: models.User = Depends(get_current_user)):
    if current_user.role not in [models.UserRole.volunteer, models.UserRole.official]:
        raise HTTPException(status_code=403, detail="Access denied: Volunteers only.")
    return current_user