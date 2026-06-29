from datetime import date, datetime, time, timedelta
from statistics import mean, pstdev

from sqlalchemy.orm import Session

from app.models import Goal, SleepSession
from app.schemas.analytics import AnalyticsOut
from app.services.sleep import list_sessions

BASELINE_SLEEP_MINUTES = 480


def session_sleep_minutes(session: SleepSession) -> int:
    return session.deep_minutes + session.rem_minutes + session.core_minutes


def _minutes_of_day(moment: datetime | time) -> int:
    return moment.hour * 60 + moment.minute


def bedtime_deviation_minutes(start_time: datetime, target_bedtime: time) -> int:
    diff = abs(_minutes_of_day(start_time) - _minutes_of_day(target_bedtime))
    return min(diff, 1440 - diff)


def calculate_sleep_score(
    total_minutes: int, target_minutes: int, bedtime_deviation: int, goal_met: bool
) -> int:
    duration_score = min(100, round((total_minutes / BASELINE_SLEEP_MINUTES) * 100))
    bedtime_score = max(0, 100 - bedtime_deviation)
    goal_score = 100 if goal_met else 40
    return round(duration_score * 0.5 + bedtime_score * 0.3 + goal_score * 0.2)


def score_sessions(sessions: list[SleepSession], goal: Goal) -> list[int]:
    scores = []
    for session in sessions:
        total_minutes = session_sleep_minutes(session)
        scores.append(
            calculate_sleep_score(
                total_minutes=total_minutes,
                target_minutes=goal.target_minutes,
                bedtime_deviation=bedtime_deviation_minutes(session.start_time, goal.target_bedtime),
                goal_met=total_minutes >= goal.target_minutes,
            )
        )
    return scores


def calculate_analytics(db: Session, user_id: int, goal: Goal, days: int) -> AnalyticsOut:
    end_date = date.today()
    start_date = end_date - timedelta(days=days - 1)
    sessions = list_sessions(db, user_id, start_date, end_date)

    if not sessions:
        return AnalyticsOut(
            average_sleep_minutes=0,
            average_sleep_score=0,
            goal_completion_rate=0,
            bedtime_consistency_minutes=0,
            duration_change_minutes=0,
        )

    durations = [session_sleep_minutes(s) for s in sessions]
    scores = score_sessions(sessions, goal)
    goals_met = sum(1 for d in durations if d >= goal.target_minutes)
    bedtime_minutes_of_day = [_minutes_of_day(s.start_time) for s in sessions]

    chronological_durations = [session_sleep_minutes(s) for s in sorted(sessions, key=lambda s: s.start_time)]
    midpoint = len(chronological_durations) // 2
    duration_change = (
        mean(chronological_durations[midpoint:]) - mean(chronological_durations[:midpoint])
        if midpoint > 0
        else 0
    )

    return AnalyticsOut(
        average_sleep_minutes=mean(durations),
        average_sleep_score=mean(scores),
        goal_completion_rate=goals_met / len(sessions),
        bedtime_consistency_minutes=pstdev(bedtime_minutes_of_day),
        duration_change_minutes=duration_change,
    )
