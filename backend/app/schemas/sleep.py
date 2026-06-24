from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator


class SleepSessionIn(BaseModel):
    external_id: str = Field(min_length=1)
    start_time: datetime
    end_time: datetime
    deep_minutes: int = Field(ge=0)
    rem_minutes: int = Field(ge=0)
    core_minutes: int = Field(ge=0)
    awake_minutes: int = Field(ge=0)

    @model_validator(mode="after")
    def check_time_range(self) -> "SleepSessionIn":
        if self.end_time <= self.start_time:
            raise ValueError("end_time must be after start_time")
        return self


class SleepSyncRequest(BaseModel):
    user_id: int
    sessions: list[SleepSessionIn] = Field(min_length=1)


class SleepSessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    external_id: str
    start_time: datetime
    end_time: datetime
    deep_minutes: int
    rem_minutes: int
    core_minutes: int
    awake_minutes: int
    created_at: datetime


class SleepSyncResponse(BaseModel):
    synced: int
    sessions: list[SleepSessionOut]
