import random
from datetime import datetime, timedelta, timezone

_FIRST_NIGHT = datetime(2000, 1, 1, 23, 0, tzinfo=timezone.utc)


def generate_sessions(count: int, seed: int) -> list[dict]:
    """Deterministic synthetic sleep sessions, already shaped like the sync request payload.

    The same (count, seed) always yields byte-identical output. Each session is a distinct
    night with a unique external_id, so the number of unique records is exactly `count`.
    """
    rng = random.Random(f"sessions:{seed}")
    sessions = []
    for index in range(count):
        start = _FIRST_NIGHT + timedelta(days=index, minutes=rng.randint(-60, 90))
        deep = rng.randint(45, 120)
        rem = rng.randint(60, 140)
        core = rng.randint(180, 300)
        awake = rng.randint(5, 45)
        end = start + timedelta(minutes=deep + rem + core + awake)
        sessions.append(
            {
                "external_id": f"bench-{index:05d}",
                "start_time": start.isoformat(),
                "end_time": end.isoformat(),
                "deep_minutes": deep,
                "rem_minutes": rem,
                "core_minutes": core,
                "awake_minutes": awake,
            }
        )
    return sessions


def total_minutes(sessions: list[dict]) -> int:
    """Checksum used to confirm the database holds the values that were generated."""
    return sum(
        s["deep_minutes"] + s["rem_minutes"] + s["core_minutes"] + s["awake_minutes"] for s in sessions
    )
