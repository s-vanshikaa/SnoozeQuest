from datetime import date, timedelta

import anthropic

from app.api.insights import get_anthropic_client
from app.main import app
from app.schemas.weekly_summary import WeeklyMetricsOut
from app.services.ai_insight import generate_insight_text, get_weekly_insight
from app.services.goal import get_goal
from app.services.weekly_summary import most_recent_completed_week_start
from tests.conftest import create_goal, sync_session


class _FakeMessages:
    def __init__(self, response=None, error=None):
        self.response = response
        self.error = error

    def create(self, **kwargs):
        if self.error is not None:
            raise self.error
        return self.response


class _FakeAnthropicClient:
    def __init__(self, response=None, error=None):
        self.messages = _FakeMessages(response=response, error=error)


class _FakeTextBlock:
    type = "text"

    def __init__(self, text):
        self.text = text


class _FakeResponse:
    def __init__(self, text):
        self.content = [_FakeTextBlock(text)]


SAMPLE_METRICS = WeeklyMetricsOut(
    average_sleep_minutes=420,
    duration_change_minutes=10,
    bedtime_change_minutes=-5,
    goal_completion_rate=0.6,
    average_sleep_score=80,
)

WEEK_START = date.today() - timedelta(days=27)


def test_most_recent_completed_week_start_is_the_monday_before_last():
    # Wednesday 2026-01-14: this week's Monday is 2026-01-12, so the most recently
    # *completed* week is the one before that.
    assert most_recent_completed_week_start(date(2026, 1, 14)) == date(2026, 1, 5)


def test_most_recent_completed_week_start_on_a_monday():
    assert most_recent_completed_week_start(date(2026, 1, 12)) == date(2026, 1, 5)


def test_generate_insight_text_returns_text_from_a_successful_response():
    fake_client = _FakeAnthropicClient(response=_FakeResponse("Great week overall."))

    result = generate_insight_text(fake_client, SAMPLE_METRICS)

    assert result == "Great week overall."


def test_generate_insight_text_returns_none_on_provider_failure():
    fake_client = _FakeAnthropicClient(error=anthropic.AnthropicError("simulated provider failure"))

    result = generate_insight_text(fake_client, SAMPLE_METRICS)

    assert result is None


def test_generate_insight_text_returns_none_on_non_anthropic_errors_too():
    # The real SDK raises a plain TypeError (not AnthropicError) when it can't resolve
    # credentials — this must degrade gracefully exactly like a typed SDK error.
    fake_client = _FakeAnthropicClient(error=TypeError("Could not resolve authentication method"))

    result = generate_insight_text(fake_client, SAMPLE_METRICS)

    assert result is None


def test_get_weekly_insight_caches_the_generated_summary(client, db_session, test_user):
    create_goal(client, test_user.id, target_minutes=400, target_bedtime="23:00:00")
    days_ago = (date.today() - WEEK_START).days
    sync_session(client, test_user.id, "insight-a", days_ago=days_ago, deep=100, rem=100, core=100)
    goal = get_goal(db_session, test_user.id)
    fake_client = _FakeAnthropicClient(response=_FakeResponse("First result."))

    first = get_weekly_insight(db_session, fake_client, test_user.id, goal, WEEK_START)
    # If this weren't cached, the second call would surface this instead.
    fake_client.messages.response = _FakeResponse("Should not be used.")
    second = get_weekly_insight(db_session, fake_client, test_user.id, goal, WEEK_START)

    assert first.summary_text == "First result."
    assert second.summary_text == "First result."


def test_get_weekly_insight_returns_metrics_with_no_summary_on_provider_failure(client, db_session, test_user):
    create_goal(client, test_user.id, target_minutes=400, target_bedtime="23:00:00")
    days_ago = (date.today() - WEEK_START).days
    sync_session(client, test_user.id, "insight-b", days_ago=days_ago, deep=100, rem=100, core=100)
    goal = get_goal(db_session, test_user.id)
    fake_client = _FakeAnthropicClient(error=anthropic.AnthropicError("simulated provider failure"))

    result = get_weekly_insight(db_session, fake_client, test_user.id, goal, WEEK_START)

    assert result.summary_text is None
    assert result.metrics.average_sleep_minutes == 300.0


def _override_anthropic_client(fake_client):
    app.dependency_overrides[get_anthropic_client] = lambda: fake_client


def _clear_anthropic_override():
    app.dependency_overrides.pop(get_anthropic_client, None)


def test_route_returns_metrics_even_when_ai_is_unavailable(client, test_user):
    create_goal(client, test_user.id, target_minutes=400, target_bedtime="23:00:00")
    week_start = most_recent_completed_week_start(date.today())
    days_ago = (date.today() - (week_start + timedelta(days=1))).days
    sync_session(client, test_user.id, "route-insight-a", days_ago=days_ago, deep=100, rem=100, core=100)

    _override_anthropic_client(_FakeAnthropicClient(error=anthropic.AnthropicError("simulated failure")))
    try:
        response = client.get("/api/v1/insights", params={"user_id": test_user.id})
    finally:
        _clear_anthropic_override()

    assert response.status_code == 200
    body = response.json()
    assert body["summary_text"] is None
    assert body["metrics"]["average_sleep_minutes"] == 300.0
    assert body["week_start_date"] == week_start.isoformat()


def test_route_returns_generated_summary(client, test_user):
    create_goal(client, test_user.id, target_minutes=400, target_bedtime="23:00:00")
    week_start = most_recent_completed_week_start(date.today())
    days_ago = (date.today() - (week_start + timedelta(days=1))).days
    sync_session(client, test_user.id, "route-insight-b", days_ago=days_ago, deep=200, rem=100, core=100)

    _override_anthropic_client(_FakeAnthropicClient(response=_FakeResponse("You slept well this week.")))
    try:
        response = client.get("/api/v1/insights", params={"user_id": test_user.id})
    finally:
        _clear_anthropic_override()

    assert response.status_code == 200
    assert response.json()["summary_text"] == "You slept well this week."


def test_route_rejects_unknown_user(client):
    response = client.get("/api/v1/insights", params={"user_id": 999_999_999})

    assert response.status_code == 404


def test_route_requires_existing_goal(client, test_user):
    response = client.get("/api/v1/insights", params={"user_id": test_user.id})

    assert response.status_code == 404
