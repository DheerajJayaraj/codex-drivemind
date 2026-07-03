# Root entry point that routes to backend/main.py for backwards compatibility and ease of run

import uvicorn
from backend.main import app

if __name__ == "__main__":
    print("Starting DriveMind Edge AI Backend Server from root main.py...")
    uvicorn.run("backend.main:app", host="127.0.0.1", port=8000, reload=True)