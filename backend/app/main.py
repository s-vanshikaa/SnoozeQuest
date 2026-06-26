from fastapi import FastAPI

from app.api.goal import router as goal_router
from app.api.health import router as health_router
from app.api.sleep import router as sleep_router

app = FastAPI(title="SnoozeQuest API")

app.include_router(health_router)
app.include_router(sleep_router)
app.include_router(goal_router)
