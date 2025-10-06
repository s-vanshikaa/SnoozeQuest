def test_get_current_goal_returns_404_when_missing(client, test_user):
    response = client.get("/api/v1/goals/current", params={"user_id": test_user.id})

    assert response.status_code == 404


def test_put_creates_goal_when_missing(client, test_user):
    payload = {
        "user_id": test_user.id,
        "target_minutes": 480,
        "target_bedtime": "23:00:00",
        "target_wake_time": "07:00:00",
    }

    response = client.put("/api/v1/goals/current", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["user_id"] == test_user.id
    assert body["target_minutes"] == 480


def test_put_updates_existing_goal(client, test_user):
    first = {
        "user_id": test_user.id,
        "target_minutes": 420,
        "target_bedtime": "23:00:00",
        "target_wake_time": "07:00:00",
    }
    client.put("/api/v1/goals/current", json=first)

    second = {**first, "target_minutes": 450, "target_bedtime": "22:30:00"}
    response = client.put("/api/v1/goals/current", json=second)

    assert response.status_code == 200
    assert response.json()["target_minutes"] == 450

    listed = client.get("/api/v1/goals/current", params={"user_id": test_user.id})
    assert listed.json()["target_minutes"] == 450
    assert listed.json()["target_bedtime"] == "22:30:00"


def test_put_rejects_non_positive_target_minutes(client, test_user):
    payload = {
        "user_id": test_user.id,
        "target_minutes": 0,
        "target_bedtime": "23:00:00",
        "target_wake_time": "07:00:00",
    }

    response = client.put("/api/v1/goals/current", json=payload)

    assert response.status_code == 422


def test_put_rejects_unknown_user(client):
    payload = {
        "user_id": 999_999_999,
        "target_minutes": 480,
        "target_bedtime": "23:00:00",
        "target_wake_time": "07:00:00",
    }

    response = client.put("/api/v1/goals/current", json=payload)

    assert response.status_code == 404


def test_get_current_goal_rejects_unknown_user(client):
    response = client.get("/api/v1/goals/current", params={"user_id": 999_999_999})

    assert response.status_code == 404
