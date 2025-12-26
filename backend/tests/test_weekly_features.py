from datetime import date, datetime, time, timedelta, timezone

from app.models import Goal, SleepSession
from app.schemas.weekly_summary import NightFeatures
from app.services.analytics import score_sessions
from app.services.weekly_features import build_weekly_features
from app.services.weekly_summary import metrics_from_sessions

WEEK_START = date(2026, 1, 5)


def _goal() -> Goal:
    return Goal(user_id=0, target_minutes=420, target_bedtime=time(23, 0), target_wake_time=time(7, 0))


def _sessions(count: int) -> list[SleepSession]:
    sessions = []
    for offset in range(count):
        start = datetime.combine(WEEK_START + timedelta(days=offset), time(23, 0), tzinfo=timezone.utc)
        start += timedelta(minutes=offset * 7)
        sessions.append(
            SleepSession(
                user_id=0, external_id=f"hk-{offset}", start_time=start,
                end_time=start + timedelta(minutes=480),
                deep_minutes=80 + offset, rem_minutes=95 + offset, core_minutes=240 + offset, awake_minutes=20 + offset,
            )
        )
    return sessions


def test_a_full_week_yields_seven_nights_of_seven_signals_each():
    features = build_weekly_features(_sessions(7), _goal(), WEEK_START)

    assert len(features.nights) == 7
    assert len(NightFeatures.signal_names()) == 7
    assert features.signal_count == 49
    assert features.signal_count >= 40


def test_a_partial_week_counts_only_the_nights_it_has():
    features = build_weekly_features(_sessions(4), _goal(), WEEK_START)

    assert features.signal_count == 4 * 7


def test_an_empty_week_has_no_signals():
    features = build_weekly_features([], _goal(), WEEK_START)

    assert features.nights == []
    assert features.signal_count == 0
    assert features.metrics.average_sleep_minutes == 0


def test_each_night_carries_the_expected_derived_values():
    sessions = _sessions(3)
    features = build_weekly_features(sessions, _goal(), WEEK_START)
    scores = score_sessions(sessions, _goal())

    night = features.nights[2]
    assert night.date == WEEK_START + timedelta(days=2)
    assert (night.deep_minutes, night.rem_minutes, night.core_minutes, night.awake_minutes) == (82, 97, 242, 22)
    assert night.total_sleep_minutes == 82 + 97 + 242  # awake time is not sleep
    assert night.bedtime_deviation_minutes == 14
    assert night.sleep_score == scores[2]


def test_the_weekly_metrics_match_the_existing_calculation():
    sessions = _sessions(7)

    features = build_weekly_features(sessions, _goal(), WEEK_START)

    assert features.metrics == metrics_from_sessions(sessions, _goal())


def test_features_do_not_carry_source_identifiers_or_raw_timestamps():
    dumped = build_weekly_features(_sessions(7), _goal(), WEEK_START).model_dump_json()

    assert "hk-" not in dumped
    assert "external_id" not in dumped
    assert "start_time" not in dumped and "end_time" not in dumped
    assert "23:00:00" not in dumped


def test_goal_context_is_included_for_the_model():
    features = build_weekly_features(_sessions(1), _goal(), WEEK_START)

    assert features.goal_target_minutes == 420
    assert features.goal_bedtime == "23:00"
