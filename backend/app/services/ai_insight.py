import logging
from datetime import date

import anthropic
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import Goal, WeeklyAISummary
from app.schemas.weekly_summary import WeeklyFeatures, WeeklyInsightOut
from app.services.weekly_features import build_weekly_features
from app.services.weekly_summary import load_week_sessions

logger = logging.getLogger(__name__)

MODEL = "claude-opus-5"

SYSTEM_PROMPT = (
    "You write short, friendly weekly sleep summaries for a sleep-tracking app. "
    "You are given deterministic per-night signals and weekly metrics already computed by the app "
    "— use only those numbers, and do not invent or estimate any metric not provided. "
    "Write 2-3 sentences interpreting the week in plain, encouraging language. "
    "Do not give medical advice, diagnoses, or treatment recommendations — "
    "you are describing sleep patterns, not assessing health."
)

_WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


def _weekday(day: date) -> str:
    return _WEEKDAYS[day.weekday()]


def _duration(minutes: float) -> str:
    total = round(minutes)
    return f"{total // 60}h {total % 60:02d}m"


def build_prompt(features: WeeklyFeatures) -> str:
    metrics = features.metrics
    lines = [
        f"Week starting {features.week_start_date.isoformat()}. "
        f"Goal: {features.goal_target_minutes} minutes of sleep, bedtime {features.goal_bedtime}.",
        "Per-night signals (minutes, except score out of 100; bedtime_off is the distance from the goal bedtime):",
    ]
    for night in features.nights:
        lines.append(
            f"{night.date.isoformat()} ({_weekday(night.date)}): "
            f"total={night.total_sleep_minutes} deep={night.deep_minutes} rem={night.rem_minutes} "
            f"core={night.core_minutes} awake={night.awake_minutes} "
            f"bedtime_off={night.bedtime_deviation_minutes} score={night.sleep_score}"
        )
    lines += [
        "Weekly metrics:",
        f"Average sleep: {metrics.average_sleep_minutes:.0f} minutes.",
        f"Sleep duration trend (second half vs first half of the week): "
        f"{metrics.duration_change_minutes:+.0f} minutes.",
        f"Bedtime consistency trend (second half vs first half, relative to the goal bedtime): "
        f"{metrics.bedtime_change_minutes:+.0f} minutes.",
        f"Goal completion rate: {metrics.goal_completion_rate:.0%}.",
        f"Average sleep score: {metrics.average_sleep_score:.0f} out of 100.",
    ]
    return "\n".join(lines)


def build_fallback_summary(features: WeeklyFeatures) -> str:
    """A plain-language summary written without the model, used when it is unavailable.

    Fully determined by `features`: the same week always produces the same text.
    """
    nights = features.nights
    if not nights:
        return f"No sleep was recorded for the week starting {features.week_start_date.isoformat()}."

    metrics = features.metrics
    count = len(nights)
    goal_met = sum(1 for night in nights if night.total_sleep_minutes >= features.goal_target_minutes)
    best = max(nights, key=lambda night: (night.sleep_score, -night.date.toordinal()))

    sentences = [
        f"You averaged {_duration(metrics.average_sleep_minutes)} of sleep over {count} "
        f"{'night' if count == 1 else 'nights'} this week, with an average sleep score of "
        f"{round(metrics.average_sleep_score)} out of 100.",
        f"You reached your {_duration(features.goal_target_minutes)} sleep goal on {goal_met} of {count} "
        f"{'night' if count == 1 else 'nights'}.",
    ]
    if count >= 2:
        change = round(metrics.duration_change_minutes)
        if abs(change) < 15:
            sentences.append("Your sleep length stayed steady from the first half of the week to the second.")
        elif change > 0:
            sentences.append(f"Your sleep got longer in the second half of the week (+{change} min on average).")
        else:
            sentences.append(f"Your sleep got shorter in the second half of the week ({change} min on average).")
    sentences.append(
        f"Your best night was {_weekday(best.date)} {best.date.isoformat()} with a score of {best.sleep_score}."
    )
    return " ".join(sentences)


def generate_insight_text(client: anthropic.Anthropic, features: WeeklyFeatures) -> str | None:
    # Deliberately broad: this must never surface a 500 to the caller, including failures
    # the SDK itself doesn't raise as AnthropicError (e.g. missing credentials raise a
    # plain TypeError from inside the client's own request-building code).
    try:
        response = client.messages.create(
            model=MODEL,
            max_tokens=300,
            output_config={"effort": "low"},
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": build_prompt(features)}],
        )
        text = next((block.text for block in response.content if block.type == "text"), None)
        return text if text and text.strip() else None
    except Exception:
        logger.warning("AI weekly insight generation failed", exc_info=True)
        return None


def _cached_summary(db: Session, user_id: int, week_start: date) -> WeeklyAISummary | None:
    return (
        db.query(WeeklyAISummary)
        .filter(WeeklyAISummary.user_id == user_id, WeeklyAISummary.week_start_date == week_start)
        .first()
    )


def _fallback_insight(features: WeeklyFeatures) -> WeeklyInsightOut:
    return WeeklyInsightOut(
        week_start_date=features.week_start_date,
        metrics=features.metrics,
        summary_text=build_fallback_summary(features),
        summary_source="fallback",
    )


def get_weekly_insight(
    db: Session, client: anthropic.Anthropic, user_id: int, goal: Goal, week_start: date
) -> WeeklyInsightOut:
    features = build_weekly_features(load_week_sessions(db, user_id, week_start), goal, week_start)

    cached = _cached_summary(db, user_id, week_start)
    if cached is not None:
        return WeeklyInsightOut(
            week_start_date=week_start, metrics=features.metrics, summary_text=cached.summary_text
        )

    if not features.nights:
        return _fallback_insight(features)  # nothing to summarise, so don't spend a model call

    # Only one request per (user, week) may generate: the rest wait here, then find the
    # result in the cache. The lock is held until this transaction commits or rolls back.
    db.execute(select(func.pg_advisory_xact_lock(user_id, week_start.toordinal())))
    cached = _cached_summary(db, user_id, week_start)
    if cached is not None:
        return WeeklyInsightOut(
            week_start_date=week_start, metrics=features.metrics, summary_text=cached.summary_text
        )

    summary_text = generate_insight_text(client, features)
    if summary_text is None:
        db.rollback()  # release the lock
        # Not cached: the next request should try the model again rather than keep the fallback.
        return _fallback_insight(features)

    db.execute(
        insert(WeeklyAISummary)
        .values(user_id=user_id, week_start_date=week_start, summary_text=summary_text)
        .on_conflict_do_nothing(constraint="uq_weekly_ai_summaries_user_week")
    )
    db.commit()
    return WeeklyInsightOut(week_start_date=week_start, metrics=features.metrics, summary_text=summary_text)
