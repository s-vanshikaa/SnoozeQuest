from datetime import date, timedelta
from statistics import mean

from sqlalchemy.orm import Session

from app.models import User
from app.schemas.leaderboard import LeaderboardEntryOut
from app.services.analytics import score_sessions, session_sleep_minutes
from app.services.goal import get_goal
from app.services.sleep import list_sessions

WINDOW_DAYS = 7


def get_leaderboard(db: Session) -> list[LeaderboardEntryOut]:
    end_date = date.today()
    start_date = end_date - timedelta(days=WINDOW_DAYS - 1)

    scored_users = []
    for user in db.query(User).order_by(User.id).all():
        goal = get_goal(db, user.id)
        if goal is None:
            continue

        sessions = list_sessions(db, user.id, start_date, end_date)
        if not sessions:
            continue

        average_score = mean(score_sessions(sessions, goal))
        goals_met = sum(1 for s in sessions if session_sleep_minutes(s) >= goal.target_minutes)
        scored_users.append((user, average_score, goals_met))

    scored_users.sort(key=lambda entry: (-entry[1], entry[0].id))

    return [
        LeaderboardEntryOut(
            id=user.id,
            name=user.name,
            rank=rank,
            average_score=average_score,
            goals_met=goals_met,
        )
        for rank, (user, average_score, goals_met) in enumerate(scored_users, start=1)
    ]
