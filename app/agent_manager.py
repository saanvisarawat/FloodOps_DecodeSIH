import os
import uuid
import json
import datetime
import google.generativeai as genai
from sqlalchemy.orm import Session
from .models import AgentRunLog, AlertRecord

genai.configure(api_key=os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))
llm = genai.GenerativeModel('gemini-3.5-flash')

def run_floodops_agents(db: Session, district: str, incident_data: str):
    run_id = str(uuid.uuid4())
    execution_chain = []
    
    try:
        prompt_1 = f"Analyze flood data for {district}: {incident_data}. Output a strict threat level assessment in 2 sentences."
        response_1 = llm.generate_content(prompt_1).text
        execution_chain.append({"agent": "Risk Analyst", "output": response_1})
        prompt_2 = f"Based on this analyst report: {response_1}, allocate specific rescue units, boats, and shelters for {district}."
        response_2 = llm.generate_content(prompt_2).text
        execution_chain.append({"agent": "Resource Allocator", "output": response_2})
        prompt_3 = (
            f"Turn this allocation plan into a rapid public SMS alert: {response_2}. "
            "Respond ONLY with a valid JSON object containing exactly these keys: "
            "'alert_level' (CRITICAL, HIGH, or MODERATE), 'message' (the 1-sentence SMS), and 'helpline' (a generic 4-digit number like 1070)."
        )
        response_3 = llm.generate_content(prompt_3).text
        clean_json_str = response_3.replace("```json", "").replace("```", "").strip()
        comms_data = json.loads(clean_json_str)
        execution_chain.append({"agent": "Communications", "output": comms_data})
        new_alert = AlertRecord(
            district=district,
            alert_level=comms_data.get("alert_level", "HIGH"),
            message=comms_data.get("message", "Emergency alert generated."),
            helpline=comms_data.get("helpline", "1070")
        )
        db.add(new_alert)
        prompt_4 = f"Summarize the operation for {district} into a 3-bullet executive summary based on the allocations."
        final_summary = llm.generate_content(prompt_4).text
        execution_chain.append({"agent": "Coordinator", "output": final_summary})
        new_log = AgentRunLog(
            run_id=run_id,
            district=district,
            status="SUCCESS",
            coordinator_summary=final_summary,
            execution_chain=execution_chain,
            created_at=datetime.datetime.utcnow()
        )
        db.add(new_log)
        db.commit()
        db.refresh(new_log)
        
        return new_log

    except Exception as e:
        db.rollback()
        error_log = AgentRunLog(
            run_id=run_id,
            district=district,
            status="FAILED",
            coordinator_summary=f"Agent chain failed: {str(e)}",
            execution_chain=execution_chain,
            created_at=datetime.datetime.utcnow()
        )
        db.add(error_log)
        db.commit()
        raise e