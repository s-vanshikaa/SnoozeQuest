from datetime import date, datetime, time, timedelta, timezone

from app.services.analytics import calculate_sleep_score


def _create_goal(client, user_id, target_minutes=400, target_bedtime="23:00:00"):
    client.put(
        "/api/v1/goals/current",
        json={
            "user_id": user_id,
            "target_minutes": target_minutes,
            "target_bedtime": target_bedtime,
            "target_wake_time": "07:00:00",
        },
    )


def _sync_session(client, user_id, external_id, days_ago, deep, rem, core, awake=20):
    start = datetime.combine(date.today() - timedelta(days=days_ago), time(23, 0), tzinfo=timezone.utc)
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


def test_analytics_requires_existing_goal(client, test_user):
    response = client.get("/api/v1/analytics", params={"user_id": test_user.id})

    assert response.status_code == 404


def test_analytics_handles_empty_dataset(client, test_user):
    _create_goal(client, test_user.id)

    response = client.get("/api/v1/analytics", params={"user_id": test_user.id})

    assert response.status_code == 200
    body = response.json()
    assert body == {
        "average_sleep_minutes": 0,
        "average_sleep_score": 0,
        "goal_completion_rate": 0,
        "bedtime_consistency_minutes": 0,
        "duration_change_minutes": 0,
    }


def test_analytics_computes_deterministic_aggregates(client, test_user):
    _create_goal(client, test_user.id, target_minutes=400, target_bedtime="23:00:00")
    _sync_session(client, test_user.id, "analytics-a", days_ago=3, deep=100, rem=100, core=100)
    _sync_session(client, test_user.id, "analytics-b", days_ago=1, deep=150, rem=150, core=150)

    response = client.get("/api/v1/analytics", params={"user_id": test_user.id, "days": 7})

    assert response.status_code == 200
    body = response.json()

    score_a = calculate_sleep_score(total_minutes=300, target_minutes=400, bedtime_deviation=0, goal_met=False)
    score_b = calculate_sleep_score(total_minutes=450, target_minutes=400, bedtime_deviation=0, goal_met=True)

    assert body["average_sleep_minutes"] == 375.0
    assert body["average_sleep_score"] == (score_a + score_b) / 2
    assert body["goal_completion_rate"] == 0.5
    assert body["bedtime_consistency_minutes"] == 0.0
    assert body["duration_change_minutes"] == 150.0


def test_analytics_rejects_invalid_days(client, test_user):
    _create_goal(client, test_user.id)

    response = client.get("/api/v1/analytics", params={"user_id": test_user.id, "days": 0})

    assert response.status_code == 422


def test_analytics_rejects_unknown_user(client):
    response = client.get("/api/v1/analytics", params={"user_id": 999_999_999})

    assert response.status_code == 404
