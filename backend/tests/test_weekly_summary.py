from datetime import date, time, timedelta

from app.services.analytics import calculate_sleep_score
from app.services.goal import get_goal
from app.services.weekly_summary import calculate_weekly_metrics
from tests.conftest import create_goal, sync_session

WEEK_START = date.today() - timedelta(days=13)


def test_weekly_metrics_handles_a_week_with_no_sessions(client, db_session, test_user):
    create_goal(client, test_user.id)
    goal = get_goal(db_session, test_user.id)

    metrics = calculate_weekly_metrics(db_session, test_user.id, goal, WEEK_START)

    assert metrics.average_sleep_minutes == 0
    assert metrics.duration_change_minutes == 0
    assert metrics.bedtime_change_minutes == 0
    assert metrics.goal_completion_rate == 0
    assert metrics.average_sleep_score == 0


def test_weekly_metrics_are_deterministic_and_only_include_sessions_in_that_week(client, db_session, test_user):
    create_goal(client, test_user.id, target_minutes=400, target_bedtime="23:00:00")
    # Inside the target week: first half vs second half drives the change metrics.
    sync_session(
        client, test_user.id, "week-a", days_ago=12, deep=100, rem=100, core=100, bedtime=time(23, 0)
    )
    sync_session(
        client, test_user.id, "week-b", days_ago=8, deep=150, rem=150, core=150, bedtime=time(23, 30)
    )
    # Outside the target week — must not affect the result.
    sync_session(client, test_user.id, "outside-week", days_ago=1, deep=200, rem=200, core=200)
    goal = get_goal(db_session, test_user.id)

    first_call = calculate_weekly_metrics(db_session, test_user.id, goal, WEEK_START)
    second_call = calculate_weekly_metrics(db_session, test_user.id, goal, WEEK_START)

    score_a = calculate_sleep_score(total_minutes=300, target_minutes=400, bedtime_deviation=0, goal_met=False)
    score_b = calculate_sleep_score(total_minutes=450, target_minutes=400, bedtime_deviation=30, goal_met=True)

    assert first_call.average_sleep_minutes == 375.0
    assert first_call.duration_change_minutes == 150.0
    assert first_call.bedtime_change_minutes == 30.0
    assert first_call.goal_completion_rate == 0.5
    assert first_call.average_sleep_score == (score_a + score_b) / 2
    assert first_call == second_call
