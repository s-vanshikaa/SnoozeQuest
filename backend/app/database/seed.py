"""Development seed data. Run with: python -m app.database.seed"""

import random
from datetime import date, datetime, time, timedelta, timezone

from app.database.session import SessionLocal
from app.models import DailySleepSummary, Goal, SleepSession, User, WeeklyAISummary

random.seed(42)

USER_NAMES = [
    "Ava Chen",
    "Liam Patel",
    "Maya Rodriguez",
    "Noah Kim",
    "Zoe Thompson",
    "Ethan Osei",
    "Priya Sharma",
    "Jack Nguyen",
    "Sofia Rossi",
    "Owen Murphy",
]

DAYS_OF_HISTORY = 30
RECENT_SESSION_DAYS = 10


def seed() -> None:
    db = SessionLocal()
    try:
        if db.query(User).first() is not None:
            print("Database already seeded, skipping.")
            return

        today = date.today()
        users: list[User] = []

        for name in USER_NAMES:
            email = f"{name.lower().replace(' ', '.')}@example.com"
            user = User(name=name, email=email)
            db.add(user)
            db.flush()
            users.append(user)

            target_minutes = random.choice([420, 450, 480])
            db.add(
                Goal(
                    user_id=user.id,
                    target_minutes=target_minutes,
                    target_bedtime=time(23, random.choice([0, 15, 30, 45])),
                    target_wake_time=time(7, random.choice([0, 15, 30, 45])),
                )
            )

            for days_ago in range(DAYS_OF_HISTORY):
                summary_date = today - timedelta(days=days_ago)
                total_minutes = random.randint(330, 540)
                goal_met = total_minutes >= target_minutes
                db.add(
                    DailySleepSummary(
                        user_id=user.id,
                        date=summary_date,
                        total_sleep_minutes=total_minutes,
                        sleep_score=random.randint(60, 100) if goal_met else random.randint(30, 70),
                        goal_met=goal_met,
                    )
                )

            for days_ago in range(RECENT_SESSION_DAYS):
                session_date = today - timedelta(days=days_ago)
                start_time = datetime.combine(
                    session_date - timedelta(days=1),
                    time(23, random.choice([0, 15, 30, 45])),
                    tzinfo=timezone.utc,
                )
                duration_minutes = random.randint(330, 540)
                end_time = start_time + timedelta(minutes=duration_minutes)
                awake_minutes = random.randint(5, 30)
                asleep_minutes = duration_minutes - awake_minutes
                deep_minutes = round(asleep_minutes * 0.2)
                rem_minutes = round(asleep_minutes * 0.25)
                core_minutes = asleep_minutes - deep_minutes - rem_minutes

                db.add(
                    SleepSession(
                        user_id=user.id,
                        external_id=f"seed-{user.id}-{session_date.isoformat()}",
                        start_time=start_time,
                        end_time=end_time,
                        deep_minutes=deep_minutes,
                        rem_minutes=rem_minutes,
                        core_minutes=core_minutes,
                        awake_minutes=awake_minutes,
                    )
                )

            last_week_start = today - timedelta(days=today.weekday() + 7)
            db.add(
                WeeklyAISummary(
                    user_id=user.id,
                    week_start_date=last_week_start,
                    summary_text=(
                        f"You averaged around {target_minutes // 60}h of sleep last week "
                        "and stayed close to your bedtime goal most nights."
                    ),
                )
            )

        db.commit()
        print(f"Seeded {len(users)} users with goals, sleep sessions, and summaries.")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
