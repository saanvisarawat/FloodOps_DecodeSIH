import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from dotenv import load_dotenv

# 1. Load the secret variables from the .env file
load_dotenv()

# 2. Get the database URL (You will get this from Supabase/Neon)
# Example format: "postgresql://user:password@host:port/dbname"
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")

# 3. Create the SQLAlchemy Engine
engine = create_engine(SQLALCHEMY_DATABASE_URL)

# 4. Create a SessionLocal class
# Each instance of this class will be an actual database session
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 5. Create a Base class
# We will use this later to create our database tables (Users, Reports)
Base = declarative_base()

# 6. Dependency function to get the database session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()