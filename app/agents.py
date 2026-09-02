from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.database import get_db
from app.schemas import AgentRunLogResponse
from app.agent_manager import run_floodops_agents

router = APIRouter(prefix="/api/agents", tags=["Agents"])

class AgentTriggerPayload(BaseModel):
    district: str
    incident_data: str

@router.post("/trigger", response_model=AgentRunLogResponse)
def trigger_agent_workflow(payload: AgentTriggerPayload, db: Session = Depends(get_db)):
    try:
        log_record = run_floodops_agents(db, payload.district, payload.incident_data)
        return log_record
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))