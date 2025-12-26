import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, time as clock_time, timedelta, timezone

import anthropic

from app.api.insights import get_anthropic_client
from app.database.session import SessionLocal
from app.main import app
from app.models import Goal, SleepSession, WeeklyAISummary
from app.services.ai_insight import build_fallback_summary, build_prompt, generate_insight_text, get_weekly_insight
from app.services.goal import get_goal
from app.services.weekly_features import build_weekly_features
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


class _CountingClient(_FakeAnthropicClient):
    """Counts provider calls; `delay` keeps a call in flight long enough for others to overlap."""

    def __init__(self, text="Counted summary.", delay=0.0, error=None):
        super().__init__(response=_FakeResponse(text), error=error)
        self.calls = 0
        self._lock = threading.Lock()
        inner = self.messages

        class _Messages:
            def create(messages_self, **kwargs):
                with self._lock:
                    self.calls += 1
                time.sleep(delay)
                return inner.create(**kwargs)

        self.messages = _Messages()


def _goal() -> Goal:
    return Goal(user_id=0, target_minutes=420, target_bedtime=clock_time(23, 0), target_wake_time=clock_time(7, 0))


def _night(day_offset: int, deep=90, rem=100, core=230, awake=25, bedtime=clock_time(23, 15)) -> SleepSession:
    start = datetime.combine(date(2026, 1, 5) + timedelta(days=day_offset), bedtime, tzinfo=timezone.utc)
    return SleepSession(
        user_id=0, external_id=f"secret-external-id-{day_offset}", start_time=start,
        end_time=start + timedelta(minutes=deep + rem + core + awake),
        deep_minutes=deep, rem_minutes=rem, core_minutes=core, awake_minutes=awake,
    )


def _features(nights: int = 7):
    sessions = [_night(i, core=230 + i * 5) for i in range(nights)]
    return build_weekly_features(sessions, _goal(), date(2026, 1, 5))


SAMPLE_FEATURES = _features()

WEEK_START = date.today() - timedelta(days=27)


def test_most_recent_completed_week_start_is_the_monday_before_last():
    # Wednesday 2026-01-14: this week's Monday is 2026-01-12, so the most recently
    # *completed* week is the one before that.
    assert most_recent_completed_week_start(date(2026, 1, 14)) == date(2026, 1, 5)


def test_most_recent_completed_week_start_on_a_monday():
    assert most_recent_completed_week_start(date(2026, 1, 12)) == date(2026, 1, 5)


def test_generate_insight_text_returns_text_from_a_successful_response():
    fake_client = _FakeAnthropicClient(response=_FakeResponse("Great week overall."))

    result = generate_insight_text(fake_client, SAMPLE_FEATURES)

    assert result == "Great week overall."


def test_generate_insight_text_returns_none_on_provider_failure():
    fake_client = _FakeAnthropicClient(error=anthropic.AnthropicError("simulated provider failure"))

    result = generate_insight_text(fake_client, SAMPLE_FEATURES)

    assert result is None


def test_generate_insight_text_returns_none_on_non_anthropic_errors_too():
    # The real SDK raises a plain TypeError (not AnthropicError) when it can't resolve
    # credentials — this must degrade gracefully exactly like a typed SDK error.
    fake_client = _FakeAnthropicClient(error=TypeError("Could not resolve authentication method"))

    result = generate_insight_text(fake_client, SAMPLE_FEATURES)

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


def test_get_weekly_insight_falls_back_to_a_deterministic_summary_on_provider_failure(client, db_session, test_user):
    create_goal(client, test_user.id, target_minutes=400, target_bedtime="23:00:00")
    days_ago = (date.today() - WEEK_START).days
    sync_session(client, test_user.id, "insight-b", days_ago=days_ago, deep=100, rem=100, core=100)
    goal = get_goal(db_session, test_user.id)
    fake_client = _FakeAnthropicClient(error=anthropic.AnthropicError("simulated provider failure"))

    result = get_weekly_insight(db_session, fake_client, test_user.id, goal, WEEK_START)

    assert result.summary_source == "fallback"
    assert result.summary_text and "5h 00m" in result.summary_text
    assert result.metrics.average_sleep_minutes == 300.0


def _override_anthropic_client(fake_client):
    app.dependency_overrides[get_anthropic_client] = lambda: fake_client


def _clear_anthropic_override():
    app.dependency_overrides.pop(get_anthropic_client, None)


def test_route_returns_a_fallback_summary_when_ai_is_unavailable(client, test_user):
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
    assert body["summary_source"] == "fallback"
    assert "5h 00m" in body["summary_text"]
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
    assert response.json()["summary_source"] == "ai"


def test_route_rejects_unknown_user(client):
    response = client.get("/api/v1/insights", params={"user_id": 999_999_999})

    assert response.status_code == 404


def test_route_requires_existing_goal(client, test_user):
    response = client.get("/api/v1/insights", params={"user_id": test_user.id})

    assert response.status_code == 404


# --- structured features in the prompt --------------------------------------------------


def test_the_prompt_carries_every_nightly_signal_for_a_full_week():
    prompt = build_prompt(SAMPLE_FEATURES)

    night_lines = [line for line in prompt.splitlines() if "total=" in line]
    assert len(night_lines) == 7
    for line in night_lines:
        for signal in ("total=", "deep=", "rem=", "core=", "awake=", "bedtime_off=", "score="):
            assert signal in line
    assert SAMPLE_FEATURES.signal_count == 49


def test_the_prompt_excludes_raw_source_metadata():
    prompt = build_prompt(SAMPLE_FEATURES)

    assert "secret-external-id" not in prompt
    assert "T23:15" not in prompt  # no raw timestamps, only dates and derived minutes
    assert "user" not in prompt.lower()


def test_the_prompt_still_includes_the_weekly_aggregates():
    prompt = build_prompt(SAMPLE_FEATURES)

    assert "Average sleep:" in prompt
    assert "Goal completion rate:" in prompt
    assert "Average sleep score:" in prompt


# --- deterministic fallback -------------------------------------------------------------


def test_the_fallback_summary_is_deterministic_and_uses_the_real_numbers():
    first = build_fallback_summary(_features())
    second = build_fallback_summary(_features())

    assert first == second
    assert "7 nights" in first
    assert "goal on 7 of 7 nights" in first  # every night is 445-475 minutes against a 420 goal


def test_the_fallback_summary_describes_a_week_with_no_data():
    text = build_fallback_summary(_features(nights=0))

    assert text == "No sleep was recorded for the week starting 2026-01-05."


def test_the_fallback_summary_handles_a_single_night():
    text = build_fallback_summary(_features(nights=1))

    assert "1 night " in text
    assert "shorter" not in text and "longer" not in text and "steady" not in text


def test_the_fallback_reports_a_falling_trend():
    sessions = [_night(i, core=260 - i * 25) for i in range(7)]

    text = build_fallback_summary(build_weekly_features(sessions, _goal(), date(2026, 1, 5)))

    assert "shorter in the second half" in text


# --- caching and provider calls ---------------------------------------------------------


def _seed_week(client, user_id, external_prefix):
    create_goal(client, user_id, target_minutes=400, target_bedtime="23:00:00")
    for offset in range(3):
        days_ago = (date.today() - (WEEK_START + timedelta(days=offset))).days
        sync_session(client, user_id, f"{external_prefix}-{offset}", days_ago=days_ago, deep=90, rem=100, core=200)


def test_repeated_requests_for_the_same_week_make_one_provider_call(client, db_session, test_user):
    _seed_week(client, test_user.id, "calls")
    goal = get_goal(db_session, test_user.id)
    counting = _CountingClient()

    results = [get_weekly_insight(db_session, counting, test_user.id, goal, WEEK_START) for _ in range(100)]

    assert counting.calls == 1
    assert {r.summary_text for r in results} == {"Counted summary."}
    assert all(r.summary_source == "ai" for r in results)


def test_a_week_with_no_sleep_data_makes_no_provider_call(client, db_session, test_user):
    create_goal(client, test_user.id)
    goal = get_goal(db_session, test_user.id)
    counting = _CountingClient()

    result = get_weekly_insight(db_session, counting, test_user.id, goal, WEEK_START)

    assert counting.calls == 0
    assert result.summary_source == "fallback"
    assert result.summary_text == "No sleep was recorded for the week starting " + WEEK_START.isoformat() + "."


def test_the_fallback_is_not_cached_so_the_model_is_tried_again_next_time(client, db_session, test_user):
    _seed_week(client, test_user.id, "recover")
    goal = get_goal(db_session, test_user.id)
    failing = _CountingClient(error=anthropic.AnthropicError("down"))

    first = get_weekly_insight(db_session, failing, test_user.id, goal, WEEK_START)
    assert first.summary_source == "fallback"
    assert db_session.query(WeeklyAISummary).filter_by(user_id=test_user.id).count() == 0

    working = _CountingClient(text="Back online.")
    second = get_weekly_insight(db_session, working, test_user.id, goal, WEEK_START)

    assert (second.summary_source, second.summary_text) == ("ai", "Back online.")
    assert working.calls == 1


def test_a_blank_model_response_falls_back(client, db_session, test_user):
    _seed_week(client, test_user.id, "blank")
    goal = get_goal(db_session, test_user.id)

    result = get_weekly_insight(db_session, _CountingClient(text="   "), test_user.id, goal, WEEK_START)

    assert result.summary_source == "fallback"


def test_a_burst_of_concurrent_requests_makes_one_provider_call_and_no_errors(client, test_user):
    _seed_week(client, test_user.id, "burst")
    week_start = most_recent_completed_week_start(date.today())
    for offset in range(2):
        days_ago = (date.today() - (week_start + timedelta(days=offset))).days
        sync_session(client, test_user.id, f"burst-week-{offset}", days_ago=days_ago, deep=90, rem=100, core=200)
    counting = _CountingClient(text="One call only.", delay=0.3)
    _override_anthropic_client(counting)
    try:
        def request(_):
            return client.get("/api/v1/insights", params={"user_id": test_user.id})

        with ThreadPoolExecutor(max_workers=8) as pool:
            responses = list(pool.map(request, range(24)))
    finally:
        _clear_anthropic_override()

    assert [r.status_code for r in responses] == [200] * 24
    assert {r.json()["summary_text"] for r in responses} == {"One call only."}
    assert counting.calls == 1
    db = SessionLocal()
    try:
        assert db.query(WeeklyAISummary).filter_by(user_id=test_user.id).count() == 1
    finally:
        db.close()
