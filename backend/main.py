# main.py - FastAPI Server for DriveMind Co-Pilot

import os
import sys
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Any

# Ensure parent directory is in path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend.tools import load_state, load_profiles, set_sensor_state
from backend.llm_engine import generate_co_pilot_response
from backend.whisper_engine import transcribe_audio, speak_text_offline

app = FastAPI(title="DriveMind Edge AI API", version="1.0.0")

# Enable CORS for frontend communication (specifically Flutter web or desktop)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatMessage(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    message: str
    chat_history: Optional[List[ChatMessage]] = []

class UpdateStateRequest(BaseModel):
    key: str
    value: Any

class SpeakRequest(BaseModel):
    text: str

@app.get("/")
async def root():
    return {"status": "online", "message": "DriveMind Co-Driver Engine is running locally."}

@app.get("/api/status")
async def get_status():
    """Returns the current simulated vehicle state and user profiles."""
    try:
        state = load_state()
        profiles = load_profiles()
        return {
            "state": state,
            "profiles": profiles
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/status/update")
async def update_status(req: UpdateStateRequest):
    """Updates a sensor or state in the vehicle simulator."""
    try:
        res = set_sensor_state(req.key, req.value)
        return {
            "message": res,
            "state": load_state()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/chat")
async def chat(req: ChatRequest):
    """Handles chat query from the driver, retrieves manual info (RAG), and executes actions."""
    try:
        # Format chat history to simple dictionaries
        history = [{"role": msg.role, "content": msg.content} for msg in req.chat_history] if req.chat_history else []
        
        # Invoke co-pilot response
        result = generate_co_pilot_response(req.message, history)
        
        # Get latest state to return
        state = load_state()
        
        return {
            "reply": result["reply"],
            "actions": result["actions"],
            "executed_results": result["executed_results"],
            "state": state
        }
    except Exception as e:
        print(f"Error in chat endpoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/voice-chat")
async def voice_chat(file: UploadFile = File(...)):
    """Receives recorded audio file, transcribes it, runs co-pilot, and returns the response."""
    temp_file_path = f"temp_{file.filename}"
    try:
        # Save uploaded file
        with open(temp_file_path, "wb") as buffer:
            buffer.write(await file.read())
            
        # Transcribe audio using whisper engine
        user_message = transcribe_audio(temp_file_path)
        print(f"Transcribed voice input: '{user_message}'")
        
        # Run co-pilot on transcribed text
        result = generate_co_pilot_response(user_message)
        state = load_state()
        
        return {
            "transcription": user_message,
            "reply": result["reply"],
            "actions": result["actions"],
            "executed_results": result["executed_results"],
            "state": state
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Clean up temp file
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)

@app.post("/api/speak")
async def speak(req: SpeakRequest):
    """Triggers offline TTS voice synthesis on the driver dashboard computer."""
    try:
        success = speak_text_offline(req.text)
        return {"success": success}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    # Default to run on localhost:8000
    uvicorn.run(app, host="127.0.0.1", port=8000)
