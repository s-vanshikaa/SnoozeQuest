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
