from fastapi import FastAPI, Depends
from sqlalchemy.orm import Session
from .database import engine, get_db
from . import models, schemas, auth
from fastapi import FastAPI, Depends, HTTPException

# 1. This line triggers the database creation in Supabase
models.Base.metadata.create_all(bind=engine)

# 2. THIS is the 'app' variable that Uvicorn is looking for!
app = FastAPI(
    title="FloodOps Backend API",
    description="Core backend for the FloodOps disaster response platform",
    version="1.0.0"
)

# 3. Our basic endpoints
@app.get("/")
async def root():
    return {"status": "online", "message": "FloodOps API is running."}

@app.get("/health")
async def health_check():
    return {"system_status": "healthy", "database": "connected"}

# 4. NEW: SOS Report Endpoint (Data Ingestion)
# 4. NEW: SOS Report Endpoint (LOCKED DOWN)
@app.post("/api/reports")
def create_sos_report(
    report: schemas.ReportCreate, 
    db: Session = Depends(get_db),
    # THIS is the new lock! It forces FastAPI to check the JWT token.
    current_user: models.User = Depends(auth.get_current_user) 
):
    
    spatial_point = f"SRID=4326;POINT({report.longitude} {report.latitude})"
    
    new_report = models.Report(
        description=report.description,
        location=spatial_point,
        image_url=report.image_url,
        # We no longer trust the app to tell us the user ID. 
        # We extract it directly from the secure JWT token!
        user_id=current_user.id 
    )
    
    db.add(new_report)
    db.commit()
    db.refresh(new_report)
    
    return {"message": "SOS Report received successfully!", "ticket_id": new_report.id}

# 5. NEW: Offline Maps Shelter Data (GeoJSON)
@app.get("/api/shelters/geojson")
def get_shelters_geojson(db: Session = Depends(get_db)):
    # Fetch all shelters from the database
    shelters = db.query(models.Shelter).all()
    
    # Format them into a standard GeoJSON FeatureCollection structure
    features = []
    for s in shelters:
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                # GeoJSON standard format requires [Longitude, Latitude] order
                "coordinates": [0.0, 0.0]  # We will extract actual PostGIS coordinates here later
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

# 6. NEW: User Registration Endpoint
@app.post("/api/auth/register")
def register_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    # 1. Hash the plain-text password
    hashed_pw = auth.hash_password(user.password)
    
    # 2. Package it into the Database Model
    new_user = models.User(
        full_name=user.full_name,
        email=user.email,
        hashed_password=hashed_pw
    )
    
    # 3. Save it to Supabase
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    return {"message": f"User {new_user.full_name} created successfully!", "user_id": new_user.id}

# 7. NEW: User Login Endpoint (Generates JWT Token)
@app.post("/api/auth/login")
def login_user(user_credentials: schemas.UserLogin, db: Session = Depends(get_db)):
    # 1. Find the user in the database by their email
    user = db.query(models.User).filter(models.User.email == user_credentials.email).first()
    
    # 2. If user doesn't exist, or the password doesn't match the hash, kick them out
    if not user or not auth.verify_password(user_credentials.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    
    # 3. Create the JWT Security Token
    # We pack their email and their specific role (citizen/volunteer/official) inside it
    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role}
    )
    
    return {"access_token": access_token, "token_type": "bearer"}