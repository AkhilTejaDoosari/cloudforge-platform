import os
import time

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError

APP_START_TIME = time.time()

# DATABASE_URL is injected via environment variable (docker-compose, k8s Secret, etc).
# Never hard-code credentials here.
DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://cloudforge:cloudforge@localhost:5432/cloudforge"
)

# CORS origins are configurable so the frontend container/domain can differ per environment.
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")

app = FastAPI(title="CloudForge Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET"],
    allow_headers=["*"],
)

# pool_pre_ping avoids handing out dead connections after DB restarts/network blips.
_engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=5, max_overflow=5)


@app.get("/health")
def health():
    """Pure liveness signal: is the process up? No external dependencies.
    This is what Kubernetes liveness probes will call in Phase 3."""
    return {
        "status": "ok",
        "uptime_seconds": round(time.time() - APP_START_TIME, 2),
    }


@app.get("/api/status")
def status():
    """Readiness-style check: reports whether the backend can reach PostgreSQL.
    Used by the frontend to display real end-to-end system status."""
    db_status = "disconnected"
    db_error = None
    try:
        with _engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        db_status = "connected"
    except SQLAlchemyError as exc:
        db_error = str(exc.__class__.__name__)

    return {
        "backend": "ok",
        "database": db_status,
        "database_error": db_error,
    }


@app.get("/")
def root():
    return {"service": "cloudforge-backend", "docs": "/docs"}
