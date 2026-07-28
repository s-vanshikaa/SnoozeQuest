from fastapi import FastAPI

from app.api.analytics import router as analytics_router
from app.api.goal import router as goal_router
from app.api.health import router as health_router
from app.api.insights import router as insights_router
from app.api.leaderboard import router as leaderboard_router
from app.api.sleep import router as sleep_router

app = FastAPI(title="SnoozeQuest API")

app.include_router(health_router)
app.include_router(sleep_router)
app.include_router(goal_router)
app.include_router(analytics_router)
app.include_router(leaderboard_router)
app.include_router(insights_router)
