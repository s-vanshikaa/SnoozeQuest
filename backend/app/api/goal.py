from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.deps import get_user_or_404
from app.database.session import get_db
from app.schemas.goal import GoalIn, GoalOut
from app.services.goal import get_goal, upsert_goal

router = APIRouter(prefix="/api/v1/goals", tags=["goals"])


@router.get("/current", response_model=GoalOut)
def get_current_goal(user_id: int, db: Session = Depends(get_db)) -> GoalOut:
    get_user_or_404(db, user_id)

    goal = get_goal(db, user_id)
    if goal is None:
        raise HTTPException(status_code=404, detail="Goal not found")
    return goal


@router.put("/current", response_model=GoalOut)
def update_current_goal(payload: GoalIn, db: Session = Depends(get_db)) -> GoalOut:
    get_user_or_404(db, payload.user_id)

    return upsert_goal(db, payload)
