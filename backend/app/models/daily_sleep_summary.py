from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database.base import Base


class DailySleepSummary(Base):
    __tablename__ = "daily_sleep_summaries"
    __table_args__ = (
        UniqueConstraint("user_id", "date", name="uq_daily_sleep_summaries_user_date"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    date: Mapped[date] = mapped_column(Date, nullable=False)
    total_sleep_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    sleep_score: Mapped[int] = mapped_column(Integer, nullable=False)
    goal_met: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
