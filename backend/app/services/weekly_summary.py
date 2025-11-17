from datetime import date, timedelta
from statistics import mean

from sqlalchemy.orm import Session

from app.models import Goal
from app.schemas.weekly_summary import WeeklyMetricsOut
from app.services.analytics import bedtime_deviation_minutes, score_sessions, session_sleep_minutes
from app.services.sleep import list_sessions


def most_recent_completed_week_start(today: date) -> date:
    current_week_start = today - timedelta(days=today.weekday())
    return current_week_start - timedelta(days=7)


def calculate_weekly_metrics(db: Session, user_id: int, goal: Goal, week_start: date) -> WeeklyMetricsOut:
    week_end = week_start + timedelta(days=6)
    sessions = sorted(list_sessions(db, user_id, week_start, week_end), key=lambda s: s.start_time)

    if not sessions:
        return WeeklyMetricsOut(
            average_sleep_minutes=0,
            duration_change_minutes=0,
            bedtime_change_minutes=0,
            goal_completion_rate=0,
            average_sleep_score=0,
        )

    durations = [session_sleep_minutes(s) for s in sessions]
    scores = score_sessions(sessions, goal)
    bedtime_deviations = [bedtime_deviation_minutes(s.start_time, goal.target_bedtime) for s in sessions]
    goals_met = sum(1 for d in durations if d >= goal.target_minutes)

    midpoint = len(sessions) // 2
    duration_change = mean(durations[midpoint:]) - mean(durations[:midpoint]) if midpoint > 0 else 0
    bedtime_change = (
        mean(bedtime_deviations[midpoint:]) - mean(bedtime_deviations[:midpoint]) if midpoint > 0 else 0
    )

    return WeeklyMetricsOut(
        average_sleep_minutes=mean(durations),
        duration_change_minutes=duration_change,
        bedtime_change_minutes=bedtime_change,
        goal_completion_rate=goals_met / len(sessions),
        average_sleep_score=mean(scores),
    )
