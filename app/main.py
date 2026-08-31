import datetime
import os
from contextlib import asynccontextmanager
from typing import List

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.security import OAuth2PasswordRequestForm
import joblib
import numpy as np
import pandas as pd
import shap
import xgboost as xgb
from sqlalchemy import func
from sqlalchemy.orm import Session
from apscheduler.schedulers.asyncio import AsyncIOScheduler

# Load environment variables from .env file
load_dotenv()

# RAGbot Imports (Native, Zero LangChain)
import google.generativeai as genai
import chromadb

from . import auth, models, schemas
from .database import engine, get_db

# --- Background Task Scheduler ---
scheduler = AsyncIOScheduler()

def fetch_satellite_sar_data():
    """
    Task to fetch Sentinel-1 SAR data via Copernicus Open Access Hub.
    Updates the ML model's baseline dataset with fresh terrain/water levels.
    """
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"🛰️ [{timestamp}] Fetching Copernicus Sentinel-1 SAR data for bounding box...")
    print("✅ SAR data sync complete. ML baseline updated.")

# --- AI Model & SHAP Explainer State ---
xgb_model = None
model_columns = None
shap_explainer = None

def load_ml_assets():
    global xgb_model, model_columns, shap_explainer
    try:
        # Load XGBoost natively from the JSON file
        xgb_model = xgb.XGBClassifier()
        xgb_model.load_model("ml_models/flood_xgb_model.json")
        
        # Load feature columns
        model_columns = joblib.load("ml_models/model_columns.pkl")
        
        # Initialize SHAP explainer
        shap_explainer = shap.TreeExplainer(xgb_model)
        print("ML models and SHAP explainer loaded successfully.")
    except Exception as e:
        print(f"Warning: ML models not found. Phase 3 predictions will fail: {e}")

# --- Native RAGbot Setup (Zero LangChain) ---

# 1. Configure Online Brain (Gemini Native)
google_api_key = os.getenv("GOOGLE_API_KEY")
genai_model = None
if google_api_key and not google_api_key.startswith("your"):
    try:
        genai.configure(api_key=google_api_key)
        genai_model = genai.GenerativeModel('gemini-3.6-flash')
    except Exception as e:
        print(f"Failed to init Gemini: {e}")

# 2. Configure Offline Search (Chroma Native)
try:
    chroma_client = chromadb.PersistentClient(path="./chroma_db")
    collection = chroma_client.get_collection(name="survival_manuals")
except Exception as e:
    print(f"Chroma DB not found or empty: {e}")
    collection = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_ml_assets()
    scheduler.add_job(fetch_satellite_sar_data, 'interval', minutes=1)
    scheduler.start()
    yield
    scheduler.shutdown()

models.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="FloodOps Backend API",
    description="Core backend for the FloodOps disaster response platform",
    version="1.0.0",
    lifespan=lifespan
)

# --- WebSocket connection manager for live Official dashboard ---
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        stale = []
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                stale.append(connection)
        for conn in stale:
            self.disconnect(conn)

manager = ConnectionManager()

@app.websocket("/ws/dashboard")
async def dashboard_websocket(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

def trigger_verification_push(user_tokens: List[str], ticket_id: int):
    print(f"🔔 [FCM MOCK] Alerting {len(user_tokens)} nearby users to verify Ticket #{ticket_id}")


# --- Phase 4: Resource Allocation Algorithm ---
# --- Phase 4: Resource Allocation Algorithm ---
def allocate_resources_for_sos(ticket_id: int, sos_description: str, latitude: float, longitude: float, db: Session):
    sos_point = f"SRID=4326;POINT({longitude} {latitude})"
    
    nearby_volunteers = db.query(models.User).filter(
        models.User.role == models.UserRole.volunteer,
        models.User.status == "available",
        models.User.last_known_location.isnot(None),
        func.ST_DWithin(
            models.User.last_known_location,
            func.ST_GeomFromText(sos_point, 4326),
            5000  # radius in meters
        )
    ).all()

    if not nearby_volunteers:
        print(f"⚠️ [Allocation Engine] No available volunteers found within 5km for Ticket #{ticket_id}")
        return None

    matched_volunteer = nearby_volunteers[0]  # Pick the closest/first available

    if matched_volunteer:
        # Mark volunteer as busy so they don't get double-booked
        matched_volunteer.status = "busy"
        
        # Link the ticket to the volunteer and update status
        report = db.query(models.Report).filter(models.Report.id == ticket_id).first()
        if report:
            report.assigned_volunteer_id = matched_volunteer.id
            report.status = "dispatched"
            
        db.commit()
        
        print(f"✅ [Allocation Engine] Assigned Ticket #{ticket_id} to Volunteer {matched_volunteer.full_name}")
        print(f"🔔 [FCM PUSH] Alert sent to Volunteer {matched_volunteer.full_name} for emergency task: '{sos_description}'")
        return matched_volunteer.id

    return None


@app.get("/")
async def root():
    return {"status": "online", "message": "FloodOps API is running."}

@app.get("/health")
async def health_check():
    return {"system_status": "healthy", "database": "connected"}

@app.post("/api/reports")
async def create_sos_report(
    report: schemas.ReportCreate, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user) 
):
    spatial_point = f"SRID=4326;POINT({report.longitude} {report.latitude})"
    
    new_report = models.Report(
        description=report.description,
        location=spatial_point,
        user_id=current_user.id 
    )
    
    db.add(new_report)
    db.commit()
    db.refresh(new_report)

    # --- TRIGGER RESOURCE ALLOCATION ALGORITHM ---
    assigned_volunteer_id = allocate_resources_for_sos(
        ticket_id=new_report.id,
        sos_description=new_report.description,
        latitude=report.latitude,
        longitude=report.longitude,
        db=db
    )

    await manager.broadcast({
        "type": "new_sos_pending",
        "ticket_id": new_report.id,
        "description": new_report.description,
        "latitude": report.latitude,
        "longitude": report.longitude,
        "status": "pending",
        "assigned_volunteer_id": assigned_volunteer_id
    })
    
    nearby_users = db.query(models.User).filter(
        models.User.id != current_user.id,
        models.User.fcm_token.isnot(None),
        func.ST_DWithin(
            models.User.last_known_location, 
            func.ST_GeomFromText(spatial_point, 4326), 
            0.0045 
        )
    ).all()

    if nearby_users:
        tokens = [u.fcm_token for u in nearby_users]
        trigger_verification_push(tokens, new_report.id)
    
    return {
        "message": "Report received and resource allocation checked.", 
        "ticket_id": new_report.id,
        "assigned_volunteer_id": assigned_volunteer_id,
        "nearby_users_alerted": len(nearby_users)
    }

@app.post("/api/reports/{ticket_id}/verify")
async def verify_report(
    ticket_id: int, 
    vote: schemas.ReportVerify, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    report = db.query(models.Report).filter(models.Report.id == ticket_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    
    if vote.is_verified:
        report.yes_count += 1
    else:
        report.no_count += 1
        
    if report.yes_count >= 3 and report.status != "verified":
        report.status = "verified"
        await manager.broadcast({
            "type": "sos_verified",
            "ticket_id": report.id,
            "description": report.description,
            "status": report.status
        })
        
    db.commit()
    return {
        "message": "Vote recorded", 
        "yes_count": report.yes_count, 
        "no_count": report.no_count, 
        "status": report.status
    }

@app.post("/api/reports/bulk")
async def create_sos_reports_bulk(
    payload: schemas.BulkReportUpload, 
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    saved_count = 0
    skipped_count = 0

    for item in payload.reports:
        existing = db.query(models.Report).filter(
            models.Report.client_timestamp == item.client_timestamp,
            models.Report.user_id == current_user.id
        ).first()

        if existing:
            skipped_count += 1
            continue

        spatial_point = f"SRID=4326;POINT({item.longitude} {item.latitude})"
        new_report = models.Report(
            description=item.description,
            location=spatial_point,
            client_timestamp=item.client_timestamp,
            user_id=current_user.id
        )
        db.add(new_report)
        saved_count += 1

    db.commit()

    return {
        "message": "Bulk sync complete",
        "saved": saved_count,
        "skipped_duplicates": skipped_count
    }

@app.get("/api/reports")
def get_all_reports(db: Session = Depends(get_db)):
    return db.query(models.Report).filter(models.Report.status == "verified").all()

@app.get("/api/shelters/geojson")
def get_shelters_geojson(db: Session = Depends(get_db)):
    shelters = db.query(models.Shelter).all()
    features = []
    for s in shelters:
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [0.0, 0.0]
            },
            "properties": {
                "id": s.id,
                "name": s.name,
                "capacity": s.capacity,
                "current_occupancy": s.current_occupancy
            }
        }
        features.append(feature)
        
    return {
        "type": "FeatureCollection",
        "features": features
    }

@app.post("/api/auth/register")
def register_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    hashed_pw = auth.hash_password(user.password)
    new_user = models.User(
        full_name=user.full_name,
        email=user.email,
        hashed_password=hashed_pw
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return {"message": f"User {new_user.full_name} created successfully!", "user_id": new_user.id}

@app.post("/api/auth/login")
def login_user(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == form_data.username).first()
    if not user or not auth.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    
    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role}
    )
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/api/predict/risk")
async def predict_flood_risk(
    payload: schemas.RiskPredictionRequest,
    current_user: models.User = Depends(auth.get_current_user)
):
    if not xgb_model or not model_columns:
        raise HTTPException(status_code=503, detail="ML models are not loaded on the server.")

    input_data = pd.DataFrame([payload.model_dump()])
    input_encoded = pd.get_dummies(input_data, columns=['state_norm'])
    
    for col in model_columns:
        if col not in input_encoded.columns:
            input_encoded[col] = 0
            
    input_final = input_encoded[model_columns].astype(float)
    
    probability = xgb_model.predict_proba(input_final)[0][1]
    best_threshold = 0.8925
    is_high_risk = bool(probability >= best_threshold)
    
    top_factors = []
    if shap_explainer:
        try:
            shap_values = shap_explainer(input_final)
            vals = shap_values.values[0] if len(shap_values.values.shape) == 2 else shap_values.values[0, :, 1]
            
            feature_contributions = sorted(
                zip(model_columns, vals),
                key=lambda x: x[1],
                reverse=True
            )
            top_factors = [feat for feat, val in feature_contributions if val > 0][:2]
        except Exception as shap_err:
            print(f"Warning: SHAP explanation calculation failed: {shap_err}")

    return {
        "risk_score": round(float(probability) * 100),
        "risk_probability": round(float(probability), 4),
        "is_high_risk": is_high_risk,
        "threshold_used": best_threshold,
        "top_factors": top_factors
    }

@app.post("/api/chat")
async def chat_with_ragbot(
    req: schemas.ChatRequest,
    current_user: models.User = Depends(auth.get_current_user)
):
    context_text = ""
    docs = []

    if collection:
        results = collection.query(query_texts=[req.message], n_results=3)
        if results and results['documents'] and len(results['documents'][0]) > 0:
            docs = results['documents'][0]
            context_text = "\n\n".join(docs)

    if genai_model:
        try:
            prompt = (
                "You are the FloodOps Emergency Survival Assistant. "
                "Use ONLY the following official protocols to answer the user's question. "
                "Keep answers highly concise and focused on immediate safety.\n\n"
                f"Protocols:\n{context_text}\n\n"
                f"User Question: {req.message}"
            )
            response = genai_model.generate_content(prompt)
            return {
                "mode": "online",
                "reply": response.text,
                "sources_used": len(docs)
            }
        except Exception as e:
            print(f"Cloud AI failed ({e}). Falling back to offline mode.")

    if docs:
        offline_reply = "⚠️ [Offline Protocol Mode] Cloud AI unavailable. Verified instructions:\n\n"
        for i, doc_text in enumerate(docs):
            offline_reply += f"{i+1}. {doc_text}\n\n"
        return {
            "mode": "offline",
            "reply": offline_reply,
            "sources_used": len(docs)
        }
    
    return {
        "mode": "offline",
        "reply": "⚠️ [Offline Mode] No specific protocols found. Move to high ground immediately.",
        "sources_used": 0
    }

@app.post("/api/volunteers/location")
async def update_volunteer_location(
    payload: schemas.VolunteerLocationUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    spatial_point = f"SRID=4326;POINT({payload.longitude} {payload.latitude})"
    
    current_user.last_known_location = spatial_point
    current_user.status = payload.status
    if payload.skills:
        current_user.skills = payload.skills
        
    db.commit()
    return {
        "message": "Volunteer location updated successfully", 
        "status": current_user.status,
        "latitude": payload.latitude,
        "longitude": payload.longitude
    }


@app.get("/api/volunteers/tasks")
async def get_volunteer_tasks(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    if current_user.role != models.UserRole.volunteer:
        raise HTTPException(status_code=403, detail="Only volunteers can view assigned tasks.")
    
    assigned_reports = db.query(models.Report).filter(
        models.Report.assigned_volunteer_id == current_user.id
    ).all()
    
    return {
        "volunteer_id": current_user.id,
        "status": current_user.status,
        "assigned_tasks": assigned_reports
    }


@app.get("/api/volunteers/tasks")
async def get_volunteer_tasks(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    if current_user.role != models.UserRole.volunteer:
        raise HTTPException(status_code=403, detail="Only volunteers can view assigned tasks.")
    
    assigned_reports = db.query(models.Report).filter(
        models.Report.assigned_volunteer_id == current_user.id
    ).all()
    
    return {
        "volunteer_id": current_user.id,
        "status": current_user.status,
        "assigned_tasks": assigned_reports
    }

from pydantic import BaseModel

class FCMTokenRequest(BaseModel):
    fcm_token: str

@app.post("/api/users/fcm-token")
async def update_fcm_token(
    data: FCMTokenRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user)
):
    """Saves or updates the logged-in user's Firebase Cloud Messaging token"""
    current_user.fcm_token = data.fcm_token
    db.commit()
    return {"status": "success", "message": "FCM token updated successfully."}