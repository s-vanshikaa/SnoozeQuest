from datetime import datetime, timedelta, timezone


def _session_payload(external_id: str, start: datetime, minutes: int = 480) -> dict:
    end = start + timedelta(minutes=minutes)
    return {
        "external_id": external_id,
        "start_time": start.isoformat(),
        "end_time": end.isoformat(),
        "deep_minutes": 90,
        "rem_minutes": 100,
        "core_minutes": 260,
        "awake_minutes": 30,
    }


def test_sync_persists_sessions(client, test_user):
    start = datetime(2026, 1, 1, 23, 0, tzinfo=timezone.utc)
    payload = {"user_id": test_user.id, "sessions": [_session_payload("session-1", start)]}

    response = client.post("/api/v1/sleep/sync", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["synced"] == 1
    assert body["sessions"][0]["external_id"] == "session-1"


def test_sync_is_idempotent_for_duplicate_external_id(client, test_user):
    start = datetime(2026, 1, 2, 23, 0, tzinfo=timezone.utc)
    payload = {"user_id": test_user.id, "sessions": [_session_payload("session-dup", start)]}

    first = client.post("/api/v1/sleep/sync", json=payload)
    second = client.post("/api/v1/sleep/sync", json=payload)

    assert first.json()["sessions"][0]["id"] == second.json()["sessions"][0]["id"]

    listed = client.get("/api/v1/sleep", params={"user_id": test_user.id})
    matching = [s for s in listed.json() if s["external_id"] == "session-dup"]
    assert len(matching) == 1


def test_sync_updates_existing_session_on_resync(client, test_user):
    start = datetime(2026, 1, 6, 23, 0, tzinfo=timezone.utc)
    payload = {"user_id": test_user.id, "sessions": [_session_payload("session-resync", start, minutes=400)]}
    client.post("/api/v1/sleep/sync", json=payload)

    expected_end = start + timedelta(minutes=450)
    payload["sessions"][0] = _session_payload("session-resync", start, minutes=450)
    response = client.post("/api/v1/sleep/sync", json=payload)

    returned_end = datetime.fromisoformat(response.json()["sessions"][0]["end_time"])
    assert returned_end == expected_end
    listed = client.get("/api/v1/sleep", params={"user_id": test_user.id})
    matching = [s for s in listed.json() if s["external_id"] == "session-resync"]
    assert len(matching) == 1


def test_sync_rejects_invalid_time_range(client, test_user):
    start = datetime(2026, 1, 3, 23, 0, tzinfo=timezone.utc)
    session = _session_payload("session-invalid", start)
    session["end_time"] = start.isoformat()
    payload = {"user_id": test_user.id, "sessions": [session]}

    response = client.post("/api/v1/sleep/sync", json=payload)

    assert response.status_code == 422


def test_sync_rejects_unknown_user(client):
    start = datetime(2026, 1, 4, 23, 0, tzinfo=timezone.utc)
    payload = {"user_id": 999_999_999, "sessions": [_session_payload("session-nouser", start)]}

    response = client.post("/api/v1/sleep/sync", json=payload)

    assert response.status_code == 404


def test_list_sessions_filters_by_date(client, test_user):
    day1 = datetime(2026, 2, 1, 23, 0, tzinfo=timezone.utc)
    day2 = datetime(2026, 2, 5, 23, 0, tzinfo=timezone.utc)
    payload = {
        "user_id": test_user.id,
        "sessions": [_session_payload("day1", day1), _session_payload("day2", day2)],
    }
    client.post("/api/v1/sleep/sync", json=payload)

    response = client.get(
        "/api/v1/sleep",
        params={"user_id": test_user.id, "start_date": "2026-02-01", "end_date": "2026-02-01"},
    )

    external_ids = {s["external_id"] for s in response.json()}
    assert external_ids == {"day1"}


def test_list_sessions_rejects_unknown_user(client):
    response = client.get("/api/v1/sleep", params={"user_id": 999_999_999})

    assert response.status_code == 404
