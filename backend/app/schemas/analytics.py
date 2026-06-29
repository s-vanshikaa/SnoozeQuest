from pydantic import BaseModel


class AnalyticsOut(BaseModel):
    average_sleep_minutes: float
    average_sleep_score: float
    goal_completion_rate: float
    bedtime_consistency_minutes: float
    duration_change_minutes: float
