"""Weekly AI insight benchmark: cache effectiveness, provider calls and latency.

Starts the real FastAPI app in-process (over real HTTP on localhost) against a throwaway
PostgreSQL database, with a metered stand-in for the model provider so every provider call is
counted. See BENCHMARKS.md for methodology.

    cd backend
    .venv/bin/python -m benchmarks.run_ai_insight_benchmark                 # stub provider
    ANTHROPIC_API_KEY=... .venv/bin/python -m benchmarks.run_ai_insight_benchmark --provider real

Run it as its own process: it points the app at the benchmark database before the app loads.
"""

import os
import sys

# The app builds its database engine when it is first imported, so the benchmark database must
# be selected first. That is only possible in a fresh process.
if "app.core.config" in sys.modules:
    raise RuntimeError("run_ai_insight_benchmark must be started as its own process")
os.environ["POSTGRES_DB"] = "snoozequest_bench"

import argparse  # noqa: E402
import json  # noqa: E402
import logging  # noqa: E402
import random  # noqa: E402
import threading  # noqa: E402
import time  # noqa: E402
from concurrent.futures import ThreadPoolExecutor  # noqa: E402
from datetime import date, datetime, time as clock_time, timedelta, timezone  # noqa: E402
from pathlib import Path  # noqa: E402
from time import perf_counter  # noqa: E402

import httpx  # noqa: E402
import uvicorn  # noqa: E402
from dotenv import dotenv_values  # noqa: E402

from app.api.insights import get_anthropic_client  # noqa: E402
from app.database.session import SessionLocal  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Goal, SleepSession, User, WeeklyAISummary  # noqa: E402
from app.services.ai_insight import MODEL, build_prompt  # noqa: E402
from app.services.weekly_features import build_weekly_features  # noqa: E402
from app.services.weekly_summary import load_week_sessions, most_recent_completed_week_start  # noqa: E402
from benchmarks.ai_providers import FailingProvider, MeteredClient, StubProvider  # noqa: E402
from benchmarks.bench_database import BENCH_DB, create_database, drop_database, migrate  # noqa: E402
from benchmarks.environment import BACKEND_DIR, collect_environment  # noqa: E402
from benchmarks.report import render_markdown  # noqa: E402
from benchmarks.stats import latency_summary  # noqa: E402

assert BENCH_DB == os.environ["POSTGRES_DB"]


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--provider", choices=["auto", "real", "stub"], default="auto",
                        help="auto uses the real provider only if ANTHROPIC_API_KEY is available")
    parser.add_argument("--stub-latency-ms", type=float, default=0.0,
                        help="delay injected into every stub provider call (stub mode only)")
    parser.add_argument("--stampede-delay-ms", type=float, default=200.0,
                        help="stub-mode delay for the concurrent-burst scenario only, so calls overlap")
    parser.add_argument("--users", type=int, default=30, help="distinct (user, week) pairs = cold samples")
    parser.add_argument("--requests-per-week", type=int, default=100)
    parser.add_argument("--stampede-requests", type=int, default=100)
    parser.add_argument("--stampede-workers", type=int, default=12)
    parser.add_argument("--fallback-users", type=int, default=20)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--output-dir", type=Path, default=BACKEND_DIR / "benchmarks")
    parser.add_argument("--keep-db", action="store_true")
    return parser.parse_args(argv)


# --- provider selection ------------------------------------------------------------------


def resolve_provider(args: argparse.Namespace):
    """Returns (inner_client, description). Never falls back silently from an explicit choice."""
    key = os.environ.get("ANTHROPIC_API_KEY") or dotenv_values(BACKEND_DIR / ".env").get("ANTHROPIC_API_KEY")
    if args.provider == "real" and not key:
        raise SystemExit("--provider real needs ANTHROPIC_API_KEY (environment or backend/.env)")
    if args.provider in ("real", "auto") and key:
        import anthropic

        return anthropic.Anthropic(api_key=key), {"mode": "real", "model": MODEL, "stub_latency_ms": None}
    return StubProvider(args.stub_latency_ms), {"mode": "stub", "model": None, "stub_latency_ms": args.stub_latency_ms}


# --- data --------------------------------------------------------------------------------


def seed_users(count: int, prefix: str, week_start: date, seed: int) -> list[int]:
    """Creates users with a goal and a full week of deterministic synthetic nights."""
    rng = random.Random(f"ai:{seed}:{prefix}")
    ids = []
    db = SessionLocal()
    try:
        for index in range(count):
            user = User(name=f"Benchmark {prefix} {index}", email=f"{prefix}-{index}@example.com")
            db.add(user)
            db.flush()
            db.add(Goal(user_id=user.id, target_minutes=rng.choice([420, 450, 480]),
                        target_bedtime=clock_time(22, 30), target_wake_time=clock_time(6, 30)))
            for night in range(7):
                start = datetime.combine(week_start + timedelta(days=night), clock_time(22, 0), tzinfo=timezone.utc)
                start += timedelta(minutes=rng.randint(0, 120))
                deep, rem = rng.randint(45, 120), rng.randint(60, 140)
                core, awake = rng.randint(180, 300), rng.randint(5, 45)
                db.add(SleepSession(
                    user_id=user.id, external_id=f"{prefix}-{index}-night-{night}", start_time=start,
                    end_time=start + timedelta(minutes=deep + rem + core + awake),
                    deep_minutes=deep, rem_minutes=rem, core_minutes=core, awake_minutes=awake,
                ))
            ids.append(user.id)
        db.commit()
    finally:
        db.close()
    return ids


def feature_stats(user_ids: list[int], week_start: date) -> dict:
    """Signal counts and prompt size, measured from the features the app actually builds."""
    db = SessionLocal()
    try:
        signal_counts, prompt_chars = [], []
        for user_id in user_ids:
            goal = db.query(Goal).filter(Goal.user_id == user_id).one()
            features = build_weekly_features(load_week_sessions(db, user_id, week_start), goal, week_start)
            signal_counts.append(features.signal_count)
            prompt_chars.append(len(build_prompt(features)))
        nights = len(features.nights)
    finally:
        db.close()
    return {
        "users_measured": len(user_ids),
        "nights_per_week": nights,
        "signals_per_night": features.signal_count // nights if nights else 0,
        "signals_per_week_min": min(signal_counts),
        "signals_per_week_max": max(signal_counts),
        "prompt_characters_mean": sum(prompt_chars) / len(prompt_chars),
    }


# --- server ------------------------------------------------------------------------------


def start_server(port: int) -> tuple[uvicorn.Server, threading.Thread]:
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, log_level="warning"))
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            if httpx.get(f"http://127.0.0.1:{port}/health", timeout=1).status_code == 200:
                return server, thread
        except httpx.HTTPError:
            time.sleep(0.1)
    raise RuntimeError("benchmark API server did not become healthy within 30s")


# --- scenarios ---------------------------------------------------------------------------


def get_insight(http: httpx.Client, user_id: int) -> tuple[float, dict]:
    started = perf_counter()
    response = http.get("/api/v1/insights", params={"user_id": user_id})
    latency_ms = (perf_counter() - started) * 1000
    response.raise_for_status()
    return latency_ms, response.json()


def run_cold_and_cached(http, metered, user_ids, requests_per_week) -> dict:
    """First request per (user, week) is cold; the rest of that week's requests should hit the cache."""
    metered.reset()
    cold_latencies, cached_latencies = [], []
    cold_sources, cached_sources = [], []
    cold_calls, cached_calls = 0, 0

    for user_id in user_ids:
        before = metered.call_count
        latency, body = get_insight(http, user_id)
        cold_calls += metered.call_count - before
        cold_latencies.append(latency)
        cold_sources.append(body["summary_source"])

        for _ in range(requests_per_week - 1):
            before = metered.call_count
            latency, body = get_insight(http, user_id)
            cached_calls += metered.call_count - before
            cached_latencies.append(latency)
            cached_sources.append(body["summary_source"])

    total_requests = len(user_ids) * requests_per_week
    provider_calls = metered.call_count
    cache_hits = len(cached_latencies) - cached_calls
    tokens = [(c.input_tokens, c.output_tokens) for c in metered.calls if c.input_tokens is not None]
    return {
        "weeks": len(user_ids),
        "requests_per_week": requests_per_week,
        "total_requests": total_requests,
        "provider_calls": provider_calls,
        "provider_call_latency_ms": latency_summary([c.latency_ms for c in metered.calls]),
        "cache_hits": cache_hits,
        "cache_hit_rate_pct": 100 * cache_hits / total_requests,
        "provider_calls_per_100_requests": 100 * provider_calls / total_requests,
        "provider_call_reduction_pct": 100 * (1 - provider_calls / total_requests),
        "cold_request_latency_ms": latency_summary(cold_latencies),
        "cached_request_latency_ms": latency_summary(cached_latencies),
        "cold_summary_sources": {s: cold_sources.count(s) for s in set(cold_sources)},
        "cached_summary_sources": {s: cached_sources.count(s) for s in set(cached_sources)},
        "cached_requests_that_called_the_provider": cached_calls,
        "tokens": {
            "calls_with_usage": len(tokens),
            "input_tokens_mean": sum(t[0] for t in tokens) / len(tokens) if tokens else None,
            "output_tokens_mean": sum(t[1] for t in tokens) / len(tokens) if tokens else None,
        },
    }


def run_stampede(http, metered, user_id, requests: int, workers: int) -> dict:
    """Many simultaneous requests for one uncached week."""
    metered.reset()
    started = perf_counter()

    def one(_):
        try:
            return get_insight(http, user_id)
        except httpx.HTTPError:
            return None, None

    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(one, range(requests)))
    elapsed = perf_counter() - started

    ok = [r for r in results if r[1] is not None]
    db = SessionLocal()
    try:
        cache_rows = db.query(WeeklyAISummary).filter(WeeklyAISummary.user_id == user_id).count()
    finally:
        db.close()
    return {
        "requests": requests,
        "concurrent_workers": workers,
        "successful_responses": len(ok),
        "failed_responses": requests - len(ok),
        "provider_calls": metered.call_count,
        "distinct_summary_texts": len({r[1]["summary_text"] for r in ok}),
        "cache_rows_written": cache_rows,
        "wall_time_seconds": elapsed,
        "request_latency_ms": latency_summary([r[0] for r in ok]),
    }


def run_fallback(http, metered, user_ids) -> dict:
    """Provider down: every response should be the deterministic fallback, and none cached."""
    metered.reset()
    latencies, sources, deterministic = [], [], True
    requests = 0
    for user_id in user_ids:
        first_latency, first = get_insight(http, user_id)
        second_latency, second = get_insight(http, user_id)
        latencies += [first_latency, second_latency]
        sources += [first["summary_source"], second["summary_source"]]
        deterministic &= first["summary_text"] == second["summary_text"]
        requests += 2
    return {
        "requests": requests,
        "fallback_responses": sources.count("fallback"),
        "ai_responses": sources.count("ai"),
        "identical_text_on_repeat": deterministic,
        "provider_calls": metered.call_count,  # one per request: the fallback is never cached
        "request_latency_ms": latency_summary(latencies),
    }


# --- entry point -------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    inner, provider = resolve_provider(args)
    week_start = most_recent_completed_week_start(date.today())
    metered = MeteredClient(inner)

    create_database()
    server = None
    try:
        migrate()
        cache_users = seed_users(args.users, "cache", week_start, args.seed)
        stampede_user = seed_users(1, "stampede", week_start, args.seed)[0]
        fallback_users = seed_users(args.fallback_users, "fallback", week_start, args.seed)
        app.dependency_overrides[get_anthropic_client] = lambda: metered
        server, thread = start_server(args.port)

        with httpx.Client(base_url=f"http://127.0.0.1:{args.port}", timeout=120) as http:
            http.get("/health")  # warm the connection

            print(f"provider={provider['mode']}  users={args.users}  requests/week={args.requests_per_week}", flush=True)
            cache = run_cold_and_cached(http, metered, cache_users, args.requests_per_week)
            print(f"cold+cached done: {cache['provider_calls']} provider calls for {cache['total_requests']} requests", flush=True)

            if provider["mode"] == "stub":
                metered.inner = StubProvider(max(args.stub_latency_ms, args.stampede_delay_ms))
                stampede_delay = max(args.stub_latency_ms, args.stampede_delay_ms)
            else:
                stampede_delay = None
            stampede = run_stampede(http, metered, stampede_user, args.stampede_requests, args.stampede_workers)
            stampede["injected_provider_delay_ms"] = stampede_delay
            print(f"stampede done: {stampede['provider_calls']} provider calls for {stampede['requests']} concurrent requests", flush=True)

            metered.inner = FailingProvider()
            # The app logs a warning with a traceback for every failed call; that is expected here.
            logging.getLogger("app.services.ai_insight").setLevel(logging.CRITICAL)
            fallback = run_fallback(http, metered, fallback_users)
            print(f"fallback done: {fallback['fallback_responses']}/{fallback['requests']} fallback responses", flush=True)

        features = feature_stats(cache_users, week_start)
        environment = collect_environment()
    finally:
        app.dependency_overrides.pop(get_anthropic_client, None)
        if server is not None:
            server.should_exit = True
            thread.join(timeout=10)
        if not args.keep_db:
            drop_database()

    output_json = args.output_dir / "benchmark_results.json"
    results = json.loads(output_json.read_text()) if output_json.exists() else {}
    results.setdefault("metadata", {})["ai_insight_benchmark_environment"] = environment
    results["ai_insight_benchmark"] = {
        "config": {
            "users": args.users, "requests_per_week": args.requests_per_week,
            "stampede_requests": args.stampede_requests, "stampede_workers": args.stampede_workers,
            "fallback_users": args.fallback_users, "seed": args.seed, "week_start": week_start.isoformat(),
            "command": "python -m benchmarks.run_ai_insight_benchmark " + " ".join(argv if argv is not None else sys.argv[1:]),
        },
        "provider": provider,
        "features": features,
        "cache": cache,
        "stampede": stampede,
        "fallback": fallback,
    }
    output_json.write_text(json.dumps(results, indent=2) + "\n")
    (args.output_dir / "BENCHMARKS.md").write_text(render_markdown(results))
    print(f"wrote {output_json} and BENCHMARKS.md")


if __name__ == "__main__":
    main()
