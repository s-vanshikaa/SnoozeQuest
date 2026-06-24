from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.database.session import SessionLocal
from app.main import app
from app.models import SleepSession, User


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
    db_session.delete(user)
    db_session.commit()


@pytest.fixture
def client():
    return TestClient(app)
