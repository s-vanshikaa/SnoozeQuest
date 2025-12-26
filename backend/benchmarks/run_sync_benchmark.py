"""Sync reliability and throughput benchmark.

Runs the real FastAPI app (a uvicorn subprocess started from the current code) against a
throwaway PostgreSQL database, and pushes synthetic sleep sessions through a Python model of
the iOS sync client. See BENCHMARKS.md for methodology.

    cd backend
    .venv/bin/python -m benchmarks.run_sync_benchmark
"""

import argparse
import json
import os
import random
import subprocess
import sys
import time
from dataclasses import asdict
from pathlib import Path
from time import perf_counter

import httpx

from benchmarks.bench_database import BENCH_DB, bench_env, connect as _connect, create_database, drop_database, migrate
from benchmarks.environment import BACKEND_DIR, collect_environment
from benchmarks.fault_injection import FaultInjector, InstrumentedTransport
from benchmarks.report import render_markdown
from benchmarks.stats import median, percentile
from benchmarks.sync_client import RetryPolicy, SyncClient
from benchmarks.synthetic_data import generate_sessions, total_minutes

DEFAULT_BATCH_SIZES = (1, 25, 100, 250)
MAX_EXTRA_PASSES = 1000


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--records", type=int, default=10_000)
    parser.add_argument("--batch-sizes", type=int, nargs="+", default=list(DEFAULT_BATCH_SIZES))
    parser.add_argument("--repetitions", type=int, default=3, help="timed repetitions per configuration")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--fault-probability", type=float, default=0.30)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--output-dir", type=Path, default=BACKEND_DIR / "benchmarks")
    parser.add_argument("--keep-db", action="store_true", help=f"don't drop the {BENCH_DB} database afterwards")
    return parser.parse_args(argv)


# --- database and server lifecycle -------------------------------------------------------


def create_user() -> int:
    connection = _connect(BENCH_DB)
    with connection, connection.cursor() as cursor:
        cursor.execute(
            "INSERT INTO users (name, email) VALUES ('Benchmark User', 'benchmark@example.com') RETURNING id"
        )
        user_id = cursor.fetchone()[0]
    connection.close()
    return user_id


def start_server(port: int) -> subprocess.Popen:
    server = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1",
         "--port", str(port), "--log-level", "warning"],
        cwd=BACKEND_DIR, env=bench_env(),
    )
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            if httpx.get(f"http://127.0.0.1:{port}/health", timeout=1).status_code == 200:
                return server
        except httpx.HTTPError:
            time.sleep(0.2)
    server.terminate()
    raise RuntimeError("benchmark API server did not become healthy within 30s")


# --- one measured run --------------------------------------------------------------------


def run_once(
    *, base_url: str, user_id: int, records: list[dict], batch_size: int,
    fault_probability: float, seed: int, scenario: str, repetition: int,
) -> dict:
    connection = _connect(BENCH_DB)
    with connection, connection.cursor() as cursor:
        cursor.execute("DELETE FROM sleep_sessions WHERE user_id = %s", (user_id,))

    with httpx.Client(base_url=base_url, timeout=30) as http:
        def send(batch: list[dict]) -> int:
            return http.post("/api/v1/sleep/sync", json={"user_id": user_id, "sessions": batch}).status_code

        # Warm the connection so the first timed request isn't paying for TCP/pool setup.
        http.get("/health")

        transport = InstrumentedTransport(send, FaultInjector(fault_probability, f"faults:{seed}:{batch_size}"))
        client = SyncClient(
            post=transport.post, batch_size=batch_size, retry_policy=RetryPolicy(),
            jitter=random.Random(f"jitter:{seed}:{batch_size}"),
        )

        started = perf_counter()
        first_pass = client.sync_pass(records)
        first_pass_seconds = perf_counter() - started

        extra_passes = 0
        while len(client.synced_ids) < len(records) and extra_passes < MAX_EXTRA_PASSES:
            client.sync_pass(records)
            extra_passes += 1
        total_seconds = perf_counter() - started

    with connection, connection.cursor() as cursor:
        cursor.execute(
            "SELECT count(*), count(DISTINCT external_id), "
            "coalesce(sum(deep_minutes + rem_minutes + core_minutes + awake_minutes), 0) "
            "FROM sleep_sessions WHERE user_id = %s",
            (user_id,),
        )
        rows_in_db, distinct_in_db, minutes_in_db = cursor.fetchone()
    connection.close()

    logs = client.request_logs
    initially_failed = [log for log in logs if log.first_attempt_failed]
    affected_ids = {record_id for log in initially_failed for record_id in log.record_ids}
    recovered_ids = affected_ids & client.synced_ids
    latencies = transport.latencies_ms

    return {
        "scenario": scenario,
        "repetition": repetition,
        "batch_size": batch_size,
        "fault_probability": fault_probability,
        "records": len(records),
        "records_synced": len(client.synced_ids),
        "api_requests": transport.requests_reaching_server,
        "request_attempts": transport.attempts,
        "failed_attempts": transport.failed_attempts,
        "total_runtime_seconds": total_seconds,
        "first_pass_runtime_seconds": first_pass_seconds,
        "records_per_second": len(client.synced_ids) / total_seconds,
        "latency_ms": {
            "count": len(latencies),
            "p50": percentile(latencies, 50),
            "p95": percentile(latencies, 95),
            "mean": sum(latencies) / len(latencies),
            "max": max(latencies),
        },
        "duplicates_in_database": rows_in_db - distinct_in_db,
        "rows_in_database": rows_in_db,
        "database_minutes_match_generated": minutes_in_db == total_minutes(records),
        "reliability": {
            "faults_injected": transport.faults_injected,
            "logical_requests": len(logs),
            "initial_failed_requests": len(initially_failed),
            "records_in_initially_failed_requests": len(affected_ids),
            "records_recovered": len(recovered_ids),
            "records_unrecovered": len(affected_ids - client.synced_ids),
            "recovery_percentage": (100 * len(recovered_ids) / len(affected_ids)) if affected_ids else None,
            "records_unsynced_after_first_pass": first_pass.unsynced,
            "first_pass_stopped_early": first_pass.stopped_early,
            "additional_sync_passes": extra_passes,
            "final_unsynced_records": len(records) - len(client.synced_ids),
            "avg_attempts_per_request": sum(log.attempts for log in logs) / len(logs) if logs else 0,
            "avg_retries_per_initially_failed_request": (
                sum(log.attempts - 1 for log in initially_failed) / len(initially_failed)
                if initially_failed else 0
            ),
            "duplicate_deliveries_absorbed": transport.duplicate_deliveries,
            "simulated_backoff_seconds": client.simulated_backoff_seconds,
        },
    }


# --- aggregation -------------------------------------------------------------------------

_DETERMINISTIC_KEYS = (
    "records_synced", "api_requests", "request_attempts", "failed_attempts",
)


def summarize(runs: list[dict]) -> list[dict]:
    """One row per (scenario, batch size): medians of the timed metrics over repetitions.

    Timings vary run to run; the fault sequence does not, so the reliability numbers must be
    identical across repetitions. `reliability_identical_across_repetitions` checks that.
    """
    groups: dict[tuple[str, int], list[dict]] = {}
    for run in runs:
        groups.setdefault((run["scenario"], run["batch_size"]), []).append(run)

    summary = []
    for (scenario, batch_size), group in groups.items():
        first = group[0]
        reliability_signature = [
            ({key: run[key] for key in _DETERMINISTIC_KEYS}, run["reliability"]["records_unrecovered"],
             run["reliability"]["initial_failed_requests"], run["reliability"]["additional_sync_passes"])
            for run in group
        ]
        summary.append({
            "scenario": scenario,
            "batch_size": batch_size,
            "fault_probability": first["fault_probability"],
            "repetitions": len(group),
            "records": first["records"],
            "records_synced": first["records_synced"],
            "api_requests": first["api_requests"],
            "request_attempts": first["request_attempts"],
            "failed_attempts": first["failed_attempts"],
            "total_runtime_seconds": {
                "median": median([r["total_runtime_seconds"] for r in group]),
                "min": min(r["total_runtime_seconds"] for r in group),
                "max": max(r["total_runtime_seconds"] for r in group),
            },
            "records_per_second_median": median([r["records_per_second"] for r in group]),
            "latency_p50_ms_median": median([r["latency_ms"]["p50"] for r in group]),
            "latency_p95_ms_median": median([r["latency_ms"]["p95"] for r in group]),
            "duplicates_in_database_max": max(r["duplicates_in_database"] for r in group),
            "database_minutes_match_generated": all(r["database_minutes_match_generated"] for r in group),
            "reliability": first["reliability"],
            "reliability_identical_across_repetitions": all(
                signature == reliability_signature[0] for signature in reliability_signature
            ),
        })
    return summary


# --- entry point -------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    scenarios = [("baseline", 0.0), (f"transient_{round(args.fault_probability * 100)}pct", args.fault_probability)]
    records = generate_sessions(args.records, args.seed)

    create_database()
    server = None
    try:
        migrate()
        user_id = create_user()
        server = start_server(args.port)
        connection = _connect(BENCH_DB)
        with connection.cursor() as cursor:
            cursor.execute("SELECT version()")
            postgres_version = cursor.fetchone()[0]
        connection.close()

        runs = []
        for scenario, probability in scenarios:
            for batch_size in args.batch_sizes:
                for repetition in range(1, args.repetitions + 1):
                    run = run_once(
                        base_url=f"http://127.0.0.1:{args.port}", user_id=user_id, records=records,
                        batch_size=batch_size, fault_probability=probability, seed=args.seed,
                        scenario=scenario, repetition=repetition,
                    )
                    runs.append(run)
                    print(
                        f"{scenario:>16} batch={batch_size:<4} rep={repetition} "
                        f"requests={run['api_requests']:<6} runtime={run['total_runtime_seconds']:.2f}s "
                        f"rec/s={run['records_per_second']:.0f}",
                        flush=True,
                    )
        environment = collect_environment(postgres_version)
    finally:
        if server is not None:
            server.terminate()
            server.wait(timeout=10)
        if not args.keep_db:
            drop_database()

    output_json = args.output_dir / "benchmark_results.json"
    results = json.loads(output_json.read_text()) if output_json.exists() else {}
    results["metadata"] = {**results.get("metadata", {}), "sync_benchmark_environment": environment}
    results["sync_benchmark"] = {
        "config": {
            "records": args.records, "batch_sizes": args.batch_sizes, "repetitions": args.repetitions,
            "seed": args.seed, "fault_probability": args.fault_probability,
            "retry_policy": asdict(RetryPolicy()),
            "max_consecutive_exhausted_batches": SyncClient.max_consecutive_exhausted_batches,
            "command": "python -m benchmarks.run_sync_benchmark " + " ".join(argv if argv is not None else sys.argv[1:]),
        },
        "runs": runs,
        "summary": summarize(runs),
    }
    output_json.write_text(json.dumps(results, indent=2) + "\n")
    (args.output_dir / "BENCHMARKS.md").write_text(render_markdown(results))
    print(f"wrote {output_json} and BENCHMARKS.md")


if __name__ == "__main__":
    main()
