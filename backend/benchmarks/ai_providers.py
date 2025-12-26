"""Stand-ins for the Anthropic client used by the AI insight benchmark.

Anything with a `.messages.create(**kwargs)` method can sit behind `MeteredClient`, which
counts and times every call the app makes to the provider.
"""

import hashlib
import threading
import time
from dataclasses import dataclass, field
from types import SimpleNamespace


@dataclass
class CallRecord:
    latency_ms: float
    ok: bool
    input_tokens: int | None = None
    output_tokens: int | None = None


class StubProvider:
    """Returns a fixed-shape response, optionally after an injected delay.

    It makes no model call, so any latency measured through it is the injected delay plus
    the app's own overhead, never real model latency.
    """

    def __init__(self, latency_ms: float = 0.0):
        self.latency_ms = latency_ms
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        if self.latency_ms > 0:
            time.sleep(self.latency_ms / 1000)
        prompt = kwargs["messages"][0]["content"]
        digest = hashlib.sha256(prompt.encode()).hexdigest()[:8]
        block = SimpleNamespace(type="text", text=f"Stub weekly summary {digest}.")
        return SimpleNamespace(content=[block], usage=None)


class FailingProvider:
    """Always raises, like a provider outage."""

    def __init__(self):
        self.messages = SimpleNamespace(create=self._create)

    @staticmethod
    def _create(**kwargs):
        raise ConnectionError("simulated provider outage")


@dataclass
class MeteredClient:
    """Wraps a provider client and records every call. `inner` can be swapped between phases."""

    inner: object
    calls: list[CallRecord] = field(default_factory=list)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def __post_init__(self):
        self.messages = SimpleNamespace(create=self._create)

    @property
    def call_count(self) -> int:
        return len(self.calls)

    def reset(self) -> None:
        with self._lock:
            self.calls.clear()

    def _create(self, **kwargs):
        started = time.perf_counter()
        try:
            response = self.inner.messages.create(**kwargs)
        except Exception:
            self._record(CallRecord((time.perf_counter() - started) * 1000, ok=False))
            raise
        usage = getattr(response, "usage", None)
        self._record(
            CallRecord(
                (time.perf_counter() - started) * 1000,
                ok=True,
                input_tokens=getattr(usage, "input_tokens", None),
                output_tokens=getattr(usage, "output_tokens", None),
            )
        )
        return response

    def _record(self, record: CallRecord) -> None:
        with self._lock:
            self.calls.append(record)
