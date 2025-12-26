from datetime import date

from app.models import Goal, SleepSession
from app.schemas.weekly_summary import NightFeatures, WeeklyFeatures
from app.services.analytics import bedtime_deviation_minutes, score_sessions, session_sleep_minutes
from app.services.weekly_summary import metrics_from_sessions


def build_weekly_features(sessions: list[SleepSession], goal: Goal, week_start: date) -> WeeklyFeatures:
    """One entry per night with seven signals each (a full week is 49), plus the aggregates.

    `sessions` must already be sorted by start time. Only derived numbers leave this function;
    identifiers and raw timestamps from the source data are not carried over.
    """
    scores = score_sessions(sessions, goal)
    nights = [
        NightFeatures(
            date=session.start_time.date(),
            total_sleep_minutes=session_sleep_minutes(session),
            deep_minutes=session.deep_minutes,
            rem_minutes=session.rem_minutes,
            core_minutes=session.core_minutes,
            awake_minutes=session.awake_minutes,
            bedtime_deviation_minutes=bedtime_deviation_minutes(session.start_time, goal.target_bedtime),
            sleep_score=score,
        )
        for session, score in zip(sessions, scores)
    ]
    return WeeklyFeatures(
        week_start_date=week_start,
        goal_target_minutes=goal.target_minutes,
        goal_bedtime=goal.target_bedtime.strftime("%H:%M"),
        nights=nights,
        metrics=metrics_from_sessions(sessions, goal),
    )
