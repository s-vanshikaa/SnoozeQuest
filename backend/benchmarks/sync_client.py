"""A Python model of the iOS SyncEngine's upload algorithm.

The app itself (Swift) can't be run against a load generator, so this reproduces its
decisions one-for-one so the backend contract can be measured under the same batching and
retry behaviour:

* pending records are sent in batches of at most `batch_size` (the app uses 100);
* transient failures (connection, timeout, 429, 5xx) are retried up to `max_attempts` total
  tries with exponential backoff and full jitter, capped at `max_delay`;
* a permanent failure is never retried as-is; a multi-record batch is split in half to
  isolate the bad record;
* a batch that is still failing after all its retries stays unsynced and the run moves on to
  the next batch; the run stops once `max_consecutive_exhausted_batches` batches in a row have
  done that, leaving the records not reached pending until the next pass. A batch the server
  accepts, or rejects with a permanent error (the server answered, so the network is up),
  resets that count.

Keep the constants in step with `RetryPolicy`, `SyncEngine.batchSize` and
`SyncEngine.maxConsecutiveExhaustedBatches` in
ios/SnoozeQuest/SnoozeQuest/Services/SyncEngine.swift. Task cancellation, which the Swift
engine also stops on, has no equivalent here because the benchmark never cancels.
"""

import random
from collections.abc import Callable
from dataclasses import dataclass, field


class TransientError(Exception):
    """A failure that repeating the same request could fix."""


class PermanentError(Exception):
    """A failure the same request will hit every time (e.g. a validation error)."""


@dataclass(frozen=True)
class RetryPolicy:
    max_attempts: int = 4
    base_delay: float = 0.5
    max_delay: float = 8.0

    def delay(self, retry_index: int, random_unit: float) -> float:
        ceiling = min(self.max_delay, self.base_delay * 2 ** min(retry_index, 30))
        return ceiling * min(max(random_unit, 0.0), 1.0)


@dataclass
class RequestLog:
    """One logical upload request: the first try plus any retries."""

    record_ids: list[str]
    attempts: int = 0
    first_attempt_failed: bool = False
    outcome: str = "pending"  # synced | exhausted | rejected


@dataclass
class PassResult:
    synced: int
    unsynced: int
    stopped_early: bool


@dataclass
class SyncClient:
    post: Callable[[list[dict]], None]
    batch_size: int
    retry_policy: RetryPolicy = field(default_factory=RetryPolicy)
    max_consecutive_exhausted_batches: int = 3
    jitter: random.Random = field(default_factory=lambda: random.Random(0))
    sleep: Callable[[float], None] = lambda seconds: None
    synced_ids: set[str] = field(default_factory=set)
    request_logs: list[RequestLog] = field(default_factory=list)
    simulated_backoff_seconds: float = 0.0
    _consecutive_exhausted: int = 0

    def sync_pass(self, records: list[dict]) -> PassResult:
        """Uploads every record not yet synced. Mirrors one `SyncEngine.sync()` call."""
        pending = [r for r in records if r["external_id"] not in self.synced_ids]
        synced_before = len(self.synced_ids)
        self._consecutive_exhausted = 0

        stopped_early = False
        for start in range(0, len(pending), self.batch_size):
            self._upload(pending[start : start + self.batch_size])
            if self._should_stop():
                stopped_early = start + self.batch_size < len(pending)
                break

        return PassResult(
            synced=len(self.synced_ids) - synced_before,
            unsynced=len(pending) - (len(self.synced_ids) - synced_before),
            stopped_early=stopped_early,
        )

    def _should_stop(self) -> bool:
        return self._consecutive_exhausted >= self.max_consecutive_exhausted_batches

    def _upload(self, batch: list[dict]) -> None:
        log = RequestLog(record_ids=[r["external_id"] for r in batch])
        self.request_logs.append(log)

        outcome = self._send_with_retries(batch, log)
        log.outcome = outcome
        if outcome == "synced":
            self.synced_ids.update(log.record_ids)
            self._consecutive_exhausted = 0
        elif outcome == "exhausted":
            self._consecutive_exhausted += 1
        else:  # rejected: the server answered, so the network is up
            self._consecutive_exhausted = 0
            if len(batch) > 1:
                middle = len(batch) // 2
                self._upload(batch[:middle])
                if self._should_stop():
                    return
                self._upload(batch[middle:])

    def _send_with_retries(self, batch: list[dict], log: RequestLog) -> str:
        for attempt in range(self.retry_policy.max_attempts):
            log.attempts += 1
            try:
                self.post(batch)
                return "synced"
            except TransientError:
                if attempt == 0:
                    log.first_attempt_failed = True
                if attempt == self.retry_policy.max_attempts - 1:
                    return "exhausted"
                delay = self.retry_policy.delay(attempt, self.jitter.random())
                self.simulated_backoff_seconds += delay
                self.sleep(delay)
            except PermanentError:
                return "rejected"
        return "exhausted"
