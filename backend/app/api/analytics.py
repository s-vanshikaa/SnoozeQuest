from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import get_goal_or_404, get_user_or_404
from app.database.session import get_db
from app.schemas.analytics import AnalyticsOut
from app.services.analytics import calculate_analytics

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])


@router.get("", response_model=AnalyticsOut)
def get_analytics(
    user_id: int,
    days: int = Query(default=7, ge=1),
    db: Session = Depends(get_db),
) -> AnalyticsOut:
    get_user_or_404(db, user_id)
    goal = get_goal_or_404(db, user_id)

    return calculate_analytics(db, user_id, goal, days)
