"""Tests for the benchmark tooling itself: determinism, statistics and the sync-client model.

These need no running server or database.
"""

import random
from datetime import datetime

import pytest

from benchmarks.fault_injection import Fault, FaultInjector, InstrumentedTransport
from benchmarks.report import render_markdown
from benchmarks.stats import median, percentile
from benchmarks.sync_client import PermanentError, RetryPolicy, SyncClient, TransientError
from benchmarks.synthetic_data import generate_sessions, total_minutes

# --- statistics --------------------------------------------------------------------------


def test_percentile_of_a_single_value_is_that_value():
    assert percentile([7.0], 95) == 7.0


def test_percentile_interpolates_between_ranks_like_numpy():
    values = [float(v) for v in range(1, 101)]

    assert percentile(values, 50) == pytest.approx(50.5)
    assert percentile(values, 95) == pytest.approx(95.05)
    assert percentile(values, 0) == 1
    assert percentile(values, 100) == 100


def test_percentile_does_not_depend_on_input_order():
    assert percentile([5.0, 1.0, 3.0], 50) == 3.0
    assert median([4.0, 1.0, 2.0, 3.0]) == 2.5


def test_percentile_rejects_empty_input():
    with pytest.raises(ValueError):
        percentile([], 50)


# --- synthetic data ----------------------------------------------------------------------


def test_the_same_seed_produces_identical_sessions():
    assert generate_sessions(500, seed=42) == generate_sessions(500, seed=42)


def test_a_different_seed_produces_different_sessions():
    assert generate_sessions(50, seed=1) != generate_sessions(50, seed=2)


def test_sessions_have_unique_ids_and_valid_time_ranges():
    sessions = generate_sessions(10_000, seed=42)

    assert len({s["external_id"] for s in sessions}) == 10_000
    for session in sessions:
        start = datetime.fromisoformat(session["start_time"])
        end = datetime.fromisoformat(session["end_time"])
        assert end > start
        assert min(session[k] for k in ("deep_minutes", "rem_minutes", "core_minutes", "awake_minutes")) >= 0


def test_total_minutes_sums_every_stage():
    sessions = generate_sessions(3, seed=1)

    assert total_minutes(sessions) == sum(
        s["deep_minutes"] + s["rem_minutes"] + s["core_minutes"] + s["awake_minutes"] for s in sessions
    )


# --- fault injection ---------------------------------------------------------------------


def _sequence(probability: float, seed: str, count: int) -> list[Fault | None]:
    injector = FaultInjector(probability, seed)
    return [injector.next_fault() for _ in range(count)]


def test_the_same_seed_gives_the_same_fault_sequence():
    assert _sequence(0.3, "s", 1000) == _sequence(0.3, "s", 1000)


def test_a_different_seed_gives_a_different_fault_sequence():
    assert _sequence(0.3, "a", 1000) != _sequence(0.3, "b", 1000)


def test_zero_probability_never_faults_and_one_always_does():
    assert _sequence(0, "s", 200) == [None] * 200
    assert all(fault is not None for fault in _sequence(1, "s", 200))


def test_the_observed_failure_rate_is_close_to_the_requested_probability():
    faults = _sequence(0.30, "rate-check", 20_000)

    rate = sum(fault is not None for fault in faults) / len(faults)
    assert rate == pytest.approx(0.30, abs=0.01)
    assert {fault for fault in faults if fault} == set(Fault)


def test_invalid_probability_is_rejected():
    with pytest.raises(ValueError):
        FaultInjector(1.5, "s")


# --- retry policy ------------------------------------------------------------------------


def test_retry_delays_double_up_to_the_cap_and_scale_with_jitter():
    policy = RetryPolicy(max_attempts=10, base_delay=0.5, max_delay=8)

    assert [policy.delay(i, 1.0) for i in range(6)] == [0.5, 1, 2, 4, 8, 8]
    assert policy.delay(3, 0.5) == 2
    assert policy.delay(3, 0.0) == 0


# --- sync client model -------------------------------------------------------------------


def _records(count: int) -> list[dict]:
    return generate_sessions(count, seed=7)


class ScriptedServer:
    """Records what it is sent; `script` supplies one outcome per call (default: accept)."""

    def __init__(self, script=None, reject_ids=frozenset()):
        self.calls: list[list[str]] = []
        self.stored: set[str] = set()
        self.script = list(script or [])
        self.reject_ids = reject_ids

    def post(self, batch: list[dict]) -> None:
        ids = [r["external_id"] for r in batch]
        self.calls.append(ids)
        if self.reject_ids.intersection(ids):
            raise PermanentError("invalid")
        outcome = self.script.pop(0) if self.script else "ok"
        if outcome == "fail":
            raise TransientError("boom")
        self.stored.update(ids)
        if outcome == "lose_response":
            raise TransientError("lost")


def _client(server: ScriptedServer, batch_size: int = 100) -> SyncClient:
    return SyncClient(post=server.post, batch_size=batch_size, jitter=random.Random(0))


@pytest.mark.parametrize(
    ("count", "expected_batches"),
    [(0, []), (1, [1]), (100, [100]), (101, [100, 1]), (250, [100, 100, 50])],
)
def test_records_are_sent_in_batches_of_at_most_the_batch_size(count, expected_batches):
    server = ScriptedServer()

    result = _client(server).sync_pass(_records(count))

    assert [len(call) for call in server.calls] == expected_batches
    assert result.synced == count
    assert result.unsynced == 0


def test_a_transient_failure_is_retried_and_recovers():
    server = ScriptedServer(script=["fail", "ok"])
    client = _client(server)

    result = client.sync_pass(_records(10))

    assert result.unsynced == 0
    assert len(server.calls) == 2
    assert client.request_logs[0].first_attempt_failed
    assert client.request_logs[0].attempts == 2
    assert client.simulated_backoff_seconds > 0


EXHAUSTED = ["fail"] * RetryPolicy().max_attempts  # one batch that uses every attempt


def test_retries_are_bounded_per_batch():
    server = ScriptedServer(script=["fail"] * 50)
    client = _client(server)

    client.sync_pass(_records(100))

    assert len(server.calls) == RetryPolicy().max_attempts
    assert client.request_logs[0].outcome == "exhausted"
    assert client.request_logs[0].attempts == RetryPolicy().max_attempts


def test_one_exhausted_batch_does_not_stop_the_rest_of_the_pass():
    server = ScriptedServer(script=EXHAUSTED)
    client = _client(server)

    result = client.sync_pass(_records(300))

    assert result.synced == 200
    assert result.unsynced == 100
    assert not result.stopped_early
    assert len(server.calls) == 4 + 1 + 1


def test_two_consecutive_exhausted_batches_still_allow_continuation():
    server = ScriptedServer(script=EXHAUSTED + EXHAUSTED)
    client = _client(server)

    result = client.sync_pass(_records(300))

    assert result.synced == 100
    assert not result.stopped_early
    assert len(server.calls) == 4 + 4 + 1


def test_three_consecutive_exhausted_batches_stop_the_pass_leaving_later_batches_untried():
    server = ScriptedServer(script=EXHAUSTED * 3)
    client = _client(server)

    result = client.sync_pass(_records(500))

    assert result.stopped_early
    assert result.synced == 0
    assert result.unsynced == 500
    assert len(server.calls) == 3 * 4
    assert len(client.request_logs) == 3  # batches 4 and 5 were never attempted


def test_three_exhausted_batches_that_are_also_the_last_do_not_count_as_stopping_early():
    server = ScriptedServer(script=EXHAUSTED * 3)

    result = _client(server).sync_pass(_records(300))

    assert not result.stopped_early
    assert result.unsynced == 300


def test_a_successful_batch_resets_the_consecutive_exhausted_count():
    # exhausted, exhausted, ok, exhausted, exhausted: never three in a row.
    server = ScriptedServer(script=EXHAUSTED + EXHAUSTED + ["ok"] + EXHAUSTED + EXHAUSTED)
    client = _client(server)

    result = client.sync_pass(_records(500))

    assert not result.stopped_early
    assert len(client.request_logs) == 5
    assert len(server.calls) == 4 + 4 + 1 + 4 + 4
    assert result.synced == 100


def test_the_consecutive_limit_is_configurable_and_defaults_to_three():
    assert SyncClient.max_consecutive_exhausted_batches == 3
    server = ScriptedServer(script=EXHAUSTED)
    client = SyncClient(post=server.post, batch_size=100, max_consecutive_exhausted_batches=1)

    result = client.sync_pass(_records(300))

    assert result.stopped_early
    assert len(client.request_logs) == 1


def test_exhausted_records_stay_unsynced_and_upload_on_a_later_pass():
    server = ScriptedServer(script=EXHAUSTED)
    client = _client(server)
    records = _records(300)

    first = client.sync_pass(records)
    second = client.sync_pass(records)

    assert first.unsynced == 100
    assert second.unsynced == 0
    assert server.stored == {r["external_id"] for r in records}


def test_resending_batches_the_server_already_accepted_keeps_a_single_copy():
    server = ScriptedServer(script=["lose_response"] * 4)
    client = _client(server)
    records = _records(300)

    client.sync_pass(records)
    assert len(server.stored) == 300

    client.sync_pass(records)

    assert client.synced_ids == {r["external_id"] for r in records}
    assert len(server.stored) == 300


def test_a_later_pass_finishes_what_an_earlier_pass_left_pending():
    server = ScriptedServer(script=EXHAUSTED * 3)
    client = _client(server)
    records = _records(500)

    first = client.sync_pass(records)
    second = client.sync_pass(records)

    assert first.unsynced == 500
    assert second.unsynced == 0
    assert server.stored == {r["external_id"] for r in records}


def test_a_permanent_failure_is_not_retried_and_does_not_block_good_records():
    records = _records(8)
    bad = records[5]["external_id"]
    server = ScriptedServer(reject_ids=frozenset({bad}))
    client = _client(server)

    result = client.sync_pass(records)

    assert result.synced == 7
    assert result.unsynced == 1
    assert bad not in client.synced_ids
    assert client.simulated_backoff_seconds == 0
    assert not result.stopped_early
    assert all(call.count(bad) <= 1 for call in server.calls)


def test_a_retry_after_a_lost_response_keeps_a_single_copy():
    server = ScriptedServer(script=["lose_response", "ok"])
    records = _records(100)

    _client(server).sync_pass(records)

    assert len(server.calls) == 2
    assert len(server.stored) == 100


def test_the_instrumented_transport_counts_duplicate_deliveries_from_lost_responses():
    injector = FaultInjector(1.0, "always")
    # Force every attempt to be a lost response by replacing the fault choice.
    injector.next_fault = lambda: Fault.LOST_RESPONSE
    sent: list[list[dict]] = []
    transport = InstrumentedTransport(lambda batch: sent.append(batch) or 200, injector)
    batch = _records(5)

    for _ in range(3):
        with pytest.raises(TransientError):
            transport.post(batch)

    assert transport.requests_reaching_server == 3
    assert transport.deliveries == 15
    assert transport.duplicate_deliveries == 10
    assert len(transport.latencies_ms) == 3


def test_faults_that_never_reach_the_server_are_not_counted_as_requests():
    injector = FaultInjector(1.0, "x")
    injector.next_fault = lambda: Fault.CONNECTION_ERROR
    transport = InstrumentedTransport(lambda batch: 200, injector)

    with pytest.raises(TransientError):
        transport.post(_records(3))

    assert transport.attempts == 1
    assert transport.requests_reaching_server == 0
    assert transport.latencies_ms == []


@pytest.mark.parametrize(("status", "error"), [(429, TransientError), (503, TransientError), (422, PermanentError)])
def test_http_status_classification_matches_the_app(status, error):
    transport = InstrumentedTransport(lambda batch: status, FaultInjector(0, "s"))

    with pytest.raises(error):
        transport.post(_records(1))


# --- report ------------------------------------------------------------------------------


def test_the_report_renders_numbers_from_the_results_it_is_given():
    results = {
        "sync_benchmark": {
            "config": {
                "records": 4321, "batch_sizes": [1, 100], "repetitions": 2, "seed": 9, "fault_probability": 0.3,
                "retry_policy": {"max_attempts": 4, "base_delay": 0.5, "max_delay": 8.0},
                "max_consecutive_exhausted_batches": 3,
                "command": "python -m benchmarks.run_sync_benchmark",
            },
            "runs": [],
            "summary": [],
        }
    }

    markdown = render_markdown(results)

    assert "4,321 synthetic sleep sessions" in markdown
    assert "seed 9" in markdown
