from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import Goal, User
from app.services.goal import get_goal


def get_user_or_404(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return user


def get_goal_or_404(db: Session, user_id: int) -> Goal:
    goal = get_goal(db, user_id)
    if goal is None:
        raise HTTPException(status_code=404, detail="Goal not found")
    return goal
