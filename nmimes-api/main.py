import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import get_settings
from routers import leaderboard, parents, sessions, students, teach_it_back, webhooks
from services.redis_client import close_redis_client, init_redis_client
from services.supabase_client import close_supabase_client, init_supabase_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up Nmimes API...")
    await init_supabase_client()
    await init_redis_client()
    yield
    logger.info("Shutting down Nmimes API...")
    await close_supabase_client()
    await close_redis_client()


settings = get_settings()

app = FastAPI(
    title="Nmimes API",
    description="Backend API for the Nmimes AI tutoring app",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.flutter_app_origin],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(sessions.router)
app.include_router(teach_it_back.router)
app.include_router(leaderboard.router)
app.include_router(webhooks.router)
app.include_router(students.router)
app.include_router(parents.router)


@app.get("/health")
async def health_check() -> dict:
    return {"status": "ok"}
