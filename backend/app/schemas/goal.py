from datetime import datetime, time

from pydantic import BaseModel, ConfigDict, Field


class GoalIn(BaseModel):
    user_id: int
    target_minutes: int = Field(gt=0)
    target_bedtime: time
    target_wake_time: time


class GoalOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    target_minutes: int
    target_bedtime: time
    target_wake_time: time
    updated_at: datetime
