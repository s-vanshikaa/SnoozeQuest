from datetime import date, datetime, time, timedelta, timezone
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.database.session import SessionLocal
from app.main import app
from app.models import Goal, SleepSession, User, WeeklyAISummary


@pytest.fixture
def db_session():
    session = SessionLocal()
    yield session
    session.close()


@pytest.fixture
def test_user(db_session):
    user = User(name="Test User", email=f"test-{uuid4()}@example.com")
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)

    yield user

    db_session.query(SleepSession).filter(SleepSession.user_id == user.id).delete()
    db_session.query(Goal).filter(Goal.user_id == user.id).delete()
    db_session.query(WeeklyAISummary).filter(WeeklyAISummary.user_id == user.id).delete()
    db_session.delete(user)
    db_session.commit()


@pytest.fixture
def client():
    return TestClient(app)


def create_goal(client, user_id, target_minutes=400, target_bedtime="23:00:00"):
    client.put(
        "/api/v1/goals/current",
        json={
            "user_id": user_id,
            "target_minutes": target_minutes,
            "target_bedtime": target_bedtime,
            "target_wake_time": "07:00:00",
        },
    )


def sync_session(client, user_id, external_id, days_ago, deep, rem, core, awake=20, bedtime=time(23, 0)):
    start = datetime.combine(date.today() - timedelta(days=days_ago), bedtime, tzinfo=timezone.utc)
    end = start + timedelta(minutes=deep + rem + core + awake)
    client.post(
        "/api/v1/sleep/sync",
        json={
            "user_id": user_id,
            "sessions": [
                {
                    "external_id": external_id,
                    "start_time": start.isoformat(),
                    "end_time": end.isoformat(),
                    "deep_minutes": deep,
                    "rem_minutes": rem,
                    "core_minutes": core,
                    "awake_minutes": awake,
                }
            ],
        },
    )
