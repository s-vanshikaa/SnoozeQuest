import logging
from datetime import date

import anthropic
from sqlalchemy.orm import Session

from app.models import Goal, WeeklyAISummary
from app.schemas.weekly_summary import WeeklyInsightOut, WeeklyMetricsOut
from app.services.weekly_summary import calculate_weekly_metrics

logger = logging.getLogger(__name__)

MODEL = "claude-opus-5"

SYSTEM_PROMPT = (
    "You write short, friendly weekly sleep summaries for a sleep-tracking app. "
    "You are given deterministic metrics already computed by the app — use only those "
    "numbers, and do not invent or estimate any metric not provided. "
    "Write 2-3 sentences interpreting the metrics in plain, encouraging language. "
    "Do not give medical advice, diagnoses, or treatment recommendations — "
    "you are describing sleep patterns, not assessing health."
)


def _build_prompt(metrics: WeeklyMetricsOut) -> str:
    return (
        f"Average sleep this week: {metrics.average_sleep_minutes:.0f} minutes.\n"
        f"Sleep duration trend within the week (second half vs first half): "
        f"{metrics.duration_change_minutes:+.0f} minutes.\n"
        f"Bedtime consistency trend within the week (second half vs first half, "
        f"relative to the goal bedtime): {metrics.bedtime_change_minutes:+.0f} minutes.\n"
        f"Goal completion rate: {metrics.goal_completion_rate:.0%}.\n"
        f"Average sleep score: {metrics.average_sleep_score:.0f} out of 100."
    )


def generate_insight_text(client: anthropic.Anthropic, metrics: WeeklyMetricsOut) -> str | None:
    # Deliberately broad: this must never surface a 500 to the caller, including failures
    # the SDK itself doesn't raise as AnthropicError (e.g. missing credentials raise a
    # plain TypeError from inside the client's own request-building code).
    try:
        response = client.messages.create(
            model=MODEL,
            max_tokens=300,
            output_config={"effort": "low"},
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": _build_prompt(metrics)}],
        )
        return next((block.text for block in response.content if block.type == "text"), None)
    except Exception:
        logger.warning("AI weekly insight generation failed", exc_info=True)
        return None


def get_weekly_insight(
    db: Session, client: anthropic.Anthropic, user_id: int, goal: Goal, week_start: date
) -> WeeklyInsightOut:
    metrics = calculate_weekly_metrics(db, user_id, goal, week_start)

    cached = (
        db.query(WeeklyAISummary)
        .filter(WeeklyAISummary.user_id == user_id, WeeklyAISummary.week_start_date == week_start)
        .first()
    )
    if cached is not None:
        return WeeklyInsightOut(week_start_date=week_start, metrics=metrics, summary_text=cached.summary_text)

    summary_text = generate_insight_text(client, metrics)
    if summary_text is not None:
        db.add(WeeklyAISummary(user_id=user_id, week_start_date=week_start, summary_text=summary_text))
        db.commit()

    return WeeklyInsightOut(week_start_date=week_start, metrics=metrics, summary_text=summary_text)
