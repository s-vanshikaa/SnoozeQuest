from datetime import date, datetime, time, timedelta, timezone


def _create_goal(client, user_id, target_minutes=400):
    client.put(
        "/api/v1/goals/current",
        json={
            "user_id": user_id,
            "target_minutes": target_minutes,
            "target_bedtime": "23:00:00",
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


def test_user_without_sessions_is_excluded_from_leaderboard(client, test_user):
    _create_goal(client, test_user.id)

    response = client.get("/api/v1/leaderboard")

    assert response.status_code == 200
    ids = [entry["id"] for entry in response.json()]
    assert test_user.id not in ids


def test_leaderboard_includes_user_with_sessions_and_is_ranked(client, test_user):
    _create_goal(client, test_user.id, target_minutes=400)
    _sync_session(client, test_user.id, "leaderboard-a", days_ago=2, deep=150, rem=150, core=150)
    _sync_session(client, test_user.id, "leaderboard-b", days_ago=1, deep=150, rem=150, core=150)

    response = client.get("/api/v1/leaderboard")

    assert response.status_code == 200
    entries = response.json()

    matching = [e for e in entries if e["id"] == test_user.id]
    assert len(matching) == 1
    assert matching[0]["goals_met"] == 2

    scores = [e["average_score"] for e in entries]
    assert scores == sorted(scores, reverse=True)

    ranks = [e["rank"] for e in entries]
    assert ranks == list(range(1, len(entries) + 1))
