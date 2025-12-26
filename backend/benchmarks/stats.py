import math


def percentile(values: list[float], q: float) -> float:
    """The q-th percentile (0-100) using linear interpolation between closest ranks.

    Matches numpy's default method, so results can be cross-checked independently.
    """
    if not values:
        raise ValueError("percentile of an empty list")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * q / 100
    lower = math.floor(position)
    upper = math.ceil(position)
    weight = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * weight


def median(values: list[float]) -> float:
    return percentile(values, 50)


def latency_summary(values_ms: list[float]) -> dict:
    """Count, p50, p95, mean and max of a list of latencies in milliseconds."""
    if not values_ms:
        return {"count": 0, "p50": None, "p95": None, "mean": None, "max": None}
    return {
        "count": len(values_ms),
        "p50": percentile(values_ms, 50),
        "p95": percentile(values_ms, 95),
        "mean": sum(values_ms) / len(values_ms),
        "max": max(values_ms),
    }
