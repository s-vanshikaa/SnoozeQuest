from datetime import date
from typing import Literal

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
    # "ai" when the text was written by the model (fresh or cached), "fallback" when the
    # model was unavailable or there was nothing to summarise and the app wrote it itself.
    summary_source: Literal["ai", "fallback"] = "ai"


class NightFeatures(BaseModel):
    """The signals sent to the model for one night. Deliberately excludes raw HealthKit
    metadata such as external ids, source names and per-sample timestamps.
    """

    date: date
    total_sleep_minutes: int
    deep_minutes: int
    rem_minutes: int
    core_minutes: int
    awake_minutes: int
    bedtime_deviation_minutes: int
    sleep_score: int

    @classmethod
    def signal_names(cls) -> list[str]:
        return [name for name in cls.model_fields if name != "date"]


class WeeklyFeatures(BaseModel):
    """Structured representation of one week of sleep: per-night signals plus the weekly
    aggregates and the goal they are judged against.
    """

    week_start_date: date
    goal_target_minutes: int
    goal_bedtime: str
    nights: list[NightFeatures]
    metrics: WeeklyMetricsOut

    @property
    def signal_count(self) -> int:
        """How many individual numeric sleep signals the model is given."""
        return len(self.nights) * len(NightFeatures.signal_names())
