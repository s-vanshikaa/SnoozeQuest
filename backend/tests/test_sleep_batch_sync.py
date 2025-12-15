from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.database.session import SessionLocal
from app.models import SleepSession, User
from app.schemas.sleep import MAX_SESSIONS_PER_SYNC

BASE_START = datetime(2026, 1, 1, 23, 0, tzinfo=timezone.utc)


def _session(external_id: str, night: int = 0, minutes: int = 480) -> dict:
    start = BASE_START + timedelta(days=night)
    return {
        "external_id": external_id,
        "start_time": start.isoformat(),
        "end_time": (start + timedelta(minutes=minutes)).isoformat(),
        "deep_minutes": 90,
        "rem_minutes": 100,
        "core_minutes": 260,
        "awake_minutes": 30,
    }


def _batch(user_id: int, count: int, prefix: str = "batch", minutes: int = 480) -> dict:
    return {
        "user_id": user_id,
        "sessions": [_session(f"{prefix}-{i}", night=i, minutes=minutes) for i in range(count)],
    }


def _row_count(user_id: int) -> int:
    db = SessionLocal()
    try:
        return db.query(SleepSession).filter(SleepSession.user_id == user_id).count()
    finally:
        db.close()


def test_sync_rejects_an_empty_batch(client, test_user):
    response = client.post("/api/v1/sleep/sync", json={"user_id": test_user.id, "sessions": []})

    assert response.status_code == 422


def test_sync_of_one_session_returns_it(client, test_user):
    response = client.post("/api/v1/sleep/sync", json=_batch(test_user.id, 1))

    assert response.status_code == 200
    assert response.json()["synced"] == 1
    assert _row_count(test_user.id) == 1


@pytest.mark.parametrize("count", [100, 101, 250, MAX_SESSIONS_PER_SYNC])
def test_sync_persists_every_session_in_a_large_batch(client, test_user, count):
    response = client.post("/api/v1/sleep/sync", json=_batch(test_user.id, count))

    assert response.status_code == 200
    body = response.json()
    assert body["synced"] == count
    assert len(body["sessions"]) == count
    assert _row_count(test_user.id) == count


def test_sync_returns_sessions_in_the_order_they_were_sent(client, test_user):
    payload = _batch(test_user.id, 5)
    payload["sessions"].reverse()

    response = client.post("/api/v1/sleep/sync", json=payload)

    sent = [s["external_id"] for s in payload["sessions"]]
    assert [s["external_id"] for s in response.json()["sessions"]] == sent


def test_sync_rejects_a_batch_over_the_request_limit(client, test_user):
    response = client.post("/api/v1/sleep/sync", json=_batch(test_user.id, MAX_SESSIONS_PER_SYNC + 1))

    assert response.status_code == 422
    assert _row_count(test_user.id) == 0


def test_syncing_the_same_batch_twice_creates_no_duplicates(client, test_user):
    payload = _batch(test_user.id, 100)

    first = client.post("/api/v1/sleep/sync", json=payload).json()
    second = client.post("/api/v1/sleep/sync", json=payload).json()

    assert _row_count(test_user.id) == 100
    assert [s["id"] for s in first["sessions"]] == [s["id"] for s in second["sessions"]]
    assert [s["created_at"] for s in first["sessions"]] == [s["created_at"] for s in second["sessions"]]


def test_a_client_retry_after_the_server_already_accepted_the_request_is_a_no_op(client, test_user):
    # The server committed the first request but the response never reached the client,
    # so the client sends the identical payload again.
    payload = _batch(test_user.id, 40)
    client.post("/api/v1/sleep/sync", json=payload)

    retry = client.post("/api/v1/sleep/sync", json=payload)

    assert retry.status_code == 200
    assert retry.json()["synced"] == 40
    assert _row_count(test_user.id) == 40


def test_resync_applies_the_latest_values_to_the_existing_row(client, test_user):
    client.post("/api/v1/sleep/sync", json=_batch(test_user.id, 3, minutes=400))

    response = client.post("/api/v1/sleep/sync", json=_batch(test_user.id, 3, minutes=450))

    for index, returned in enumerate(response.json()["sessions"]):
        start = BASE_START + timedelta(days=index)
        assert datetime.fromisoformat(returned["end_time"]) == start + timedelta(minutes=450)
    assert _row_count(test_user.id) == 3


def test_the_same_external_id_twice_in_one_request_keeps_the_last_one(client, test_user):
    payload = {
        "user_id": test_user.id,
        "sessions": [_session("repeat", minutes=400), _session("repeat", minutes=450)],
    }

    response = client.post("/api/v1/sleep/sync", json=payload)

    assert response.status_code == 200
    assert response.json()["synced"] == 1
    assert _row_count(test_user.id) == 1
    assert datetime.fromisoformat(response.json()["sessions"][0]["end_time"]) == BASE_START + timedelta(minutes=450)


def test_one_invalid_session_rejects_the_whole_batch_without_writing_anything(client, test_user):
    payload = _batch(test_user.id, 3)
    payload["sessions"][1]["end_time"] = payload["sessions"][1]["start_time"]

    response = client.post("/api/v1/sleep/sync", json=payload)

    assert response.status_code == 422
    assert _row_count(test_user.id) == 0


def test_sessions_with_the_same_external_id_are_kept_separate_per_user(client, test_user):
    other = client.post("/api/v1/sleep/sync", json=_batch(test_user.id, 2, prefix="shared"))
    assert other.status_code == 200
    db = SessionLocal()
    second_user = User(name="Second User", email=f"second-{uuid4()}@example.com")
    db.add(second_user)
    db.commit()
    db.refresh(second_user)
    try:
        response = client.post("/api/v1/sleep/sync", json=_batch(second_user.id, 2, prefix="shared"))

        assert response.status_code == 200
        assert _row_count(test_user.id) == 2
        assert _row_count(second_user.id) == 2
    finally:
        db.query(SleepSession).filter(SleepSession.user_id == second_user.id).delete()
        db.delete(second_user)
        db.commit()
        db.close()


def test_concurrent_requests_for_the_same_sessions_never_duplicate_or_fail(client, test_user):
    payload = _batch(test_user.id, 100)

    def send(_):
        return client.post("/api/v1/sleep/sync", json=payload).status_code

    with ThreadPoolExecutor(max_workers=8) as pool:
        statuses = list(pool.map(send, range(16)))

    assert statuses == [200] * 16
    assert _row_count(test_user.id) == 100
