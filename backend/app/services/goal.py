from sqlalchemy.orm import Session

from app.models import Goal
from app.schemas.goal import GoalIn


def get_goal(db: Session, user_id: int) -> Goal | None:
    return db.query(Goal).filter(Goal.user_id == user_id).first()


def upsert_goal(db: Session, goal_in: GoalIn) -> Goal:
    goal = get_goal(db, goal_in.user_id)
    if goal is None:
        goal = Goal(user_id=goal_in.user_id)
        db.add(goal)

    goal.target_minutes = goal_in.target_minutes
    goal.target_bedtime = goal_in.target_bedtime
    goal.target_wake_time = goal_in.target_wake_time

    db.commit()
    return goal
