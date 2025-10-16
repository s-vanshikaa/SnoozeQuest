from datetime import datetime, time, timezone

from app.services.analytics import bedtime_deviation_minutes, calculate_sleep_score


def test_bedtime_deviation_is_zero_for_exact_match():
    start = datetime(2026, 1, 1, 23, 0, tzinfo=timezone.utc)
    assert bedtime_deviation_minutes(start, time(23, 0)) == 0


def test_bedtime_deviation_handles_midnight_wraparound():
    start = datetime(2026, 1, 2, 23, 50, tzinfo=timezone.utc)
    assert bedtime_deviation_minutes(start, time(0, 10)) == 20


def test_bedtime_deviation_without_wraparound():
    start = datetime(2026, 1, 1, 22, 30, tzinfo=timezone.utc)
    assert bedtime_deviation_minutes(start, time(23, 0)) == 30


def test_sleep_score_is_maximal_for_full_duration_on_time_goal_met():
    score = calculate_sleep_score(total_minutes=480, target_minutes=480, bedtime_deviation=0, goal_met=True)
    assert score == 100


def test_sleep_score_is_lower_for_short_duration_and_missed_goal():
    short_score = calculate_sleep_score(total_minutes=200, target_minutes=480, bedtime_deviation=0, goal_met=False)
    full_score = calculate_sleep_score(total_minutes=480, target_minutes=480, bedtime_deviation=0, goal_met=True)
    assert short_score < full_score


def test_sleep_score_is_bounded_between_zero_and_hundred():
    score = calculate_sleep_score(total_minutes=0, target_minutes=480, bedtime_deviation=1000, goal_met=False)
    assert 0 <= score <= 100
