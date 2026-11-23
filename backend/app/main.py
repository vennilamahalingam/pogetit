"""FastAPI entry point. Run from backend/:  uvicorn app.main:app --host 0.0.0.0 --port 8000"""
from fastapi import FastAPI

from app.routes import quests

app = FastAPI(title="PoGetIt API")
app.include_router(quests.router)


@app.get("/health")
def health():
    return {"ok": True}
