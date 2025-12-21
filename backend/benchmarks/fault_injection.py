import random
from collections.abc import Callable
from enum import Enum
from time import perf_counter

import httpx

from benchmarks.sync_client import PermanentError, TransientError


class Fault(str, Enum):
    CONNECTION_ERROR = "connection_error"  # request never reaches the server
    HTTP_503 = "http_503"  # request never reaches the server; client sees a 503
    LOST_RESPONSE = "lost_response"  # server commits the batch, the response is lost (timeout)


class FaultInjector:
    """Decides, per request attempt, whether it fails and how. Fully determined by the seed.

    Each attempt fails independently with `probability`; a failure is one of the three kinds
    above, chosen uniformly.
    """

    def __init__(self, probability: float, seed: str):
        if not 0 <= probability <= 1:
            raise ValueError("probability must be between 0 and 1")
        self.probability = probability
        self._rng = random.Random(seed)

    def next_fault(self) -> Fault | None:
        if self.probability == 0:
            return None
        if self._rng.random() >= self.probability:
            return None
        return self._rng.choice(list(Fault))


class InstrumentedTransport:
    """Sends batches through `send` (which returns an HTTP status), injecting faults and
    counting what actually reached the server.
    """

    def __init__(self, send: Callable[[list[dict]], int], injector: FaultInjector):
        self._send = send
        self._injector = injector
        self.attempts = 0
        self.failed_attempts = 0
        self.requests_reaching_server = 0
        self.latencies_ms: list[float] = []
        self.faults_injected: dict[str, int] = {fault.value: 0 for fault in Fault}
        self.deliveries = 0  # records carried by requests that reached the server
        self.delivered_ids: set[str] = set()

    @property
    def duplicate_deliveries(self) -> int:
        """Records that reached the server more than once (retries after a lost response)."""
        return self.deliveries - len(self.delivered_ids)

    def post(self, batch: list[dict]) -> None:
        self.attempts += 1
        fault = self._injector.next_fault()
        if fault is not None:
            self.faults_injected[fault.value] += 1

        if fault in (Fault.CONNECTION_ERROR, Fault.HTTP_503):
            self.failed_attempts += 1
            raise TransientError(fault.value)

        started = perf_counter()
        try:
            status = self._send(batch)
        except (httpx.ConnectError, httpx.TimeoutException) as error:
            self.failed_attempts += 1
            raise TransientError(str(error)) from error
        self.latencies_ms.append((perf_counter() - started) * 1000)
        self.requests_reaching_server += 1
        self.deliveries += len(batch)
        self.delivered_ids.update(record["external_id"] for record in batch)

        if fault is Fault.LOST_RESPONSE:
            self.failed_attempts += 1
            raise TransientError(fault.value)
        if status == 429 or status >= 500:
            self.failed_attempts += 1
            raise TransientError(f"HTTP {status}")
        if status >= 400:
            self.failed_attempts += 1
            raise PermanentError(f"HTTP {status}")
