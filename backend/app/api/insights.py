from datetime import date

import anthropic
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_goal_or_404, get_user_or_404
from app.database.session import get_db
from app.schemas.weekly_summary import WeeklyInsightOut
from app.services.ai_insight import get_weekly_insight
from app.services.weekly_summary import most_recent_completed_week_start

router = APIRouter(prefix="/api/v1/insights", tags=["insights"])


def get_anthropic_client() -> anthropic.Anthropic:
    return anthropic.Anthropic()


@router.get("", response_model=WeeklyInsightOut)
def get_weekly_insight_route(
    user_id: int,
    db: Session = Depends(get_db),
    client: anthropic.Anthropic = Depends(get_anthropic_client),
) -> WeeklyInsightOut:
    get_user_or_404(db, user_id)
    goal = get_goal_or_404(db, user_id)
    week_start = most_recent_completed_week_start(date.today())

    return get_weekly_insight(db, client, user_id, goal, week_start)
