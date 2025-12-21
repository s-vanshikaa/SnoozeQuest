"""Renders BENCHMARKS.md from benchmark_results.json.

Every number in the document is read from the results file; nothing is typed in by hand.
Sections appear only for benchmarks that have been run.
"""


def _fmt(value, digits: int = 1) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:,.{digits}f}"
    if isinstance(value, int):
        return f"{value:,}"
    return str(value)


def _table(headers: list[str], rows: list[list[str]]) -> str:
    lines = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    lines += ["| " + " | ".join(row) + " |" for row in rows]
    return "\n".join(lines)


def _environment_section(environment: dict) -> str:
    packages = ", ".join(f"{name} {version}" for name, version in environment["packages"].items())
    dirty = " (uncommitted changes in backend/app or alembic)" if environment["git_working_tree_dirty"] else ""
    rows = [
        ["Captured (UTC)", environment["captured_at_utc"]],
        ["Code version", f"git {environment['git_commit']}{dirty}"],
        ["Machine", f"{environment['cpu']}, {environment['cpu_cores']} cores, {environment['memory_gb']} GB RAM"],
        ["OS", environment["os"]],
        ["Python", environment["python"]],
        ["Packages", packages],
        ["PostgreSQL", environment["postgres_version"]],
    ]
    return _table(["", ""], rows)


def _sync_section(sync: dict) -> str:
    config = sync["config"]
    summary = sync["summary"]
    baseline = [row for row in summary if row["fault_probability"] == 0]
    faulty = [row for row in summary if row["fault_probability"] > 0]
    retry = config["retry_policy"]

    parts = ["## Sync throughput and reliability (Tickets 2-3)", ""]
    parts.append(
        f"**Workload:** {_fmt(config['records'])} synthetic sleep sessions (seed {config['seed']}), "
        f"batch sizes {', '.join(str(b) for b in config['batch_sizes'])}, "
        f"{config['repetitions']} timed repetitions per configuration.  \n"
        f"**Client retry policy modelled:** up to {retry['max_attempts']} attempts per request, "
        f"exponential backoff from {retry['base_delay']}s capped at {retry['max_delay']}s, full jitter."
    )
    parts.append("")

    parts += ["### Methodology", ""]
    parts.append(
        "- The real FastAPI app is started from the current code with uvicorn (1 worker) against a "
        "**throwaway PostgreSQL database** created for the run and dropped afterwards. Nothing touches "
        "the development database.\n"
        "- Sessions are generated deterministically from the seed. Each has a unique `external_id`, so the "
        "number of unique records is exactly the workload size.\n"
        "- A Python model of the iOS `SyncEngine` (`benchmarks/sync_client.py`) uploads them: batches of at "
        "most `batch_size`, retry with backoff on transient failures, no retry of permanent failures, and "
        "the run stops after a request exhausts its retries.\n"
        "- Each configuration is run "
        f"{config['repetitions']} times on an emptied table; the table reports the **median** of the "
        "repetitions, with the min-max range for total runtime.\n"
        "- **Runtime** is wall-clock time for all sync passes, from the first request to the last response. "
        "**Latency** is measured per HTTP request that reached the server (client-observed, including JSON "
        "encoding, on localhost); p50/p95 use linear interpolation between ranks.\n"
        "- Backoff waits are **computed and totalled but not slept**, so runtime reflects request work only; "
        "`simulated backoff` shows how long a real client would additionally have waited.\n"
        "- **Duplicates** are `rows - distinct external_ids` in the database after the run, and the "
        "session-minutes checksum is compared with the generated data.\n"
        "- **Fault injection:** each request attempt fails independently with the scenario's probability, "
        "drawn from a seeded generator, so the fault sequence is identical on every run. A failure is one of "
        "`connection_error` (never reaches the server), `http_503` (never reaches the server) or "
        "`lost_response` (the server commits the batch but the response is dropped, so the client retries a "
        "batch the server already accepted). The three kinds are equally likely."
    )
    parts.append("")

    if baseline:
        parts += ["### Throughput by batch size (no injected faults)", ""]
        rows = []
        for row in baseline:
            runtime = row["total_runtime_seconds"]
            rows.append([
                str(row["batch_size"]), _fmt(row["records"]), _fmt(row["api_requests"]),
                f"{_fmt(runtime['median'], 2)} ({_fmt(runtime['min'], 2)}-{_fmt(runtime['max'], 2)})",
                _fmt(row["records_per_second_median"], 0),
                _fmt(row["latency_p50_ms_median"], 2), _fmt(row["latency_p95_ms_median"], 2),
                _fmt(row["failed_attempts"]), _fmt(row["duplicates_in_database_max"]),
            ])
        parts.append(_table(
            ["Batch size", "Records", "API requests", "Runtime s, median (range)", "Records/s",
             "p50 ms", "p95 ms", "Failures", "Duplicates"], rows))
        parts.append("")

        by_size = {row["batch_size"]: row for row in baseline}
        if 1 in by_size and 100 in by_size:
            one, hundred = by_size[1], by_size[100]
            reduction = 100 * (1 - hundred["api_requests"] / one["api_requests"])
            speedup = hundred["records_per_second_median"] / one["records_per_second_median"]
            parts.append(
                f"Batch size 100 used {_fmt(hundred['api_requests'])} requests against "
                f"{_fmt(one['api_requests'])} for batch size 1 ({_fmt(reduction, 1)}% fewer), and synced "
                f"{_fmt(speedup, 1)}x as many records per second "
                f"({_fmt(hundred['records_per_second_median'], 0)} vs {_fmt(one['records_per_second_median'], 0)})."
            )
            parts.append("")

    if faulty:
        probability = round(faulty[0]["fault_probability"] * 100)
        parts += [f"### Recovery under {probability}% transient request failures", ""]
        rows = []
        for row in faulty:
            rel = row["reliability"]
            rows.append([
                str(row["batch_size"]), _fmt(row["request_attempts"]), _fmt(row["api_requests"]),
                _fmt(rel["initial_failed_requests"]), _fmt(rel["records_in_initially_failed_requests"]),
                _fmt(rel["records_recovered"]), _fmt(rel["records_unrecovered"]),
                _fmt(rel["recovery_percentage"], 2) + ("%" if rel["recovery_percentage"] is not None else ""),
                _fmt(rel["avg_attempts_per_request"], 3), _fmt(rel["avg_retries_per_initially_failed_request"], 3),
                _fmt(rel["duplicate_deliveries_absorbed"]), _fmt(row["duplicates_in_database_max"]),
            ])
        parts.append(_table(
            ["Batch size", "Attempts", "API requests reaching server", "Initial failed requests",
             "Records in those requests", "Recovered", "Unrecovered", "Recovery %",
             "Avg attempts / request", "Avg retries / failed request", "Duplicate deliveries absorbed",
             "Duplicates in DB"], rows))
        parts.append("")

        parts += ["### Passes needed and cost of recovery", ""]
        rows = []
        for row in faulty:
            rel = row["reliability"]
            rows.append([
                str(row["batch_size"]), _fmt(row["records_synced"]),
                _fmt(rel["records_unsynced_after_first_pass"]), _fmt(rel["additional_sync_passes"]),
                _fmt(rel["final_unsynced_records"]),
                f"{_fmt(row['total_runtime_seconds']['median'], 2)}",
                _fmt(row["records_per_second_median"], 0),
                _fmt(rel["simulated_backoff_seconds"], 1),
                _fmt(row["latency_p50_ms_median"], 2), _fmt(row["latency_p95_ms_median"], 2),
                "yes" if row["reliability_identical_across_repetitions"] else "NO",
            ])
        parts.append(_table(
            ["Batch size", "Records synced", "Unsynced after first pass", "Extra passes to finish",
             "Unsynced at end", "Runtime s (median)", "Records/s", "Simulated backoff s",
             "p50 ms", "p95 ms", "Reliability numbers identical across repetitions"], rows))
        parts.append("")
        parts.append(
            "**Definitions.** *Initial failed request*: a logical upload whose first attempt failed. "
            "*Recovered*: a record in such a request that was synced by the end of the run (all passes). "
            "*Unrecovered*: one that was not. *Recovery %* = recovered / records in initially failed requests. "
            "*Unsynced after first pass*: records still pending when the first sync pass ended (a pass stops at "
            "the first request that exhausts its retries, leaving later batches untouched). *Extra passes*: further "
            "full sync passes, as the app would run on its next refresh, until nothing is pending. "
            "*Duplicate deliveries absorbed*: records that reached the server more than once (for example a retry "
            "after a lost response) and were applied as no-ops by the upsert."
        )
        parts.append("")

    return "\n".join(parts)


def render_markdown(results: dict) -> str:
    parts = [
        "# SnoozeQuest Benchmarks",
        "",
        "Measured results for sync batching, reliability and idempotency. All numbers below are generated "
        "from `benchmark_results.json` by `benchmarks/report.py`; nothing is edited by hand. Re-running the "
        "commands below on other hardware will produce different absolute numbers.",
        "",
    ]

    metadata = results.get("metadata", {})
    if "sync_benchmark_environment" in metadata:
        parts += ["## Environment", "", _environment_section(metadata["sync_benchmark_environment"]), ""]

    parts += [
        "## Commands",
        "",
        "Prerequisites: the PostgreSQL container is running (`docker compose up -d db` in `backend/`), "
        "`backend/.env` holds the database credentials, and dependencies are installed "
        "(`pip install -r requirements.txt`).",
        "",
        "```bash",
        "cd backend",
        "python -m benchmarks.run_sync_benchmark   # writes benchmarks/benchmark_results.json and BENCHMARKS.md",
        "python -m pytest tests/test_benchmark_tooling.py",
        "```",
        "",
    ]
    if "sync_benchmark" in results:
        parts += [f"The sync benchmark in this file was run with: `{results['sync_benchmark']['config']['command']}`", ""]
        parts.append(_sync_section(results["sync_benchmark"]))

    parts += [
        "## Limitations",
        "",
        "- The iOS client is Swift and cannot be driven from a load script. The benchmark uses a Python model of "
        "its upload algorithm (`benchmarks/sync_client.py`); the batching and retry constants are duplicated "
        "and must be kept in step with `SyncEngine.swift`. The numbers characterise the backend and the "
        "algorithm, not the app on a device.\n"
        "- Everything runs on one machine over localhost, with PostgreSQL in a container on the same host, so "
        "there is no real network latency, packet loss or cellular behaviour. Absolute latencies will be higher "
        "for a real device.\n"
        "- Faults are injected in the client transport, not by breaking the network or the server.\n"
        "- One synthetic user, one uvicorn worker, and one machine; no concurrent-client load.\n"
        "- Backoff delays are not slept (see Methodology).",
        "",
    ]
    return "\n".join(parts)


if __name__ == "__main__":
    # Re-render BENCHMARKS.md from an existing results file without re-running any benchmark.
    import json
    from pathlib import Path

    directory = Path(__file__).resolve().parent
    results = json.loads((directory / "benchmark_results.json").read_text())
    (directory / "BENCHMARKS.md").write_text(render_markdown(results))
