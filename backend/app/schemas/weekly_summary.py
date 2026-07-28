from datetime import date

from pydantic import BaseModel


class WeeklyMetricsOut(BaseModel):
    average_sleep_minutes: float
    duration_change_minutes: float
    bedtime_change_minutes: float
    goal_completion_rate: float
    average_sleep_score: float


class WeeklyInsightOut(BaseModel):
    week_start_date: date
    metrics: WeeklyMetricsOut
    summary_text: str | None
