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
        "most `batch_size`, retry with backoff on transient failures, no retry of permanent failures, a "
        "batch that exhausts its retries is left unsynced while the run continues, and the run stops after "
        f"{config['max_consecutive_exhausted_batches']} consecutive batches exhaust their retries.\n"
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
                _fmt(rel["records_unsynced_after_first_pass"]), _fmt(rel["additional_sync_passes"] + 1),
                _fmt(rel["final_unsynced_records"]),
                f"{_fmt(row['total_runtime_seconds']['median'], 2)}",
                _fmt(row["records_per_second_median"], 0),
                _fmt(rel["simulated_backoff_seconds"], 1),
                _fmt(row["latency_p50_ms_median"], 2), _fmt(row["latency_p95_ms_median"], 2),
                "yes" if row["reliability_identical_across_repetitions"] else "NO",
            ])
        parts.append(_table(
            ["Batch size", "Records synced", "Unsynced after first pass", "Total sync passes",
             "Unsynced at end", "Runtime s (median)", "Records/s", "Simulated backoff s",
             "p50 ms", "p95 ms", "Reliability numbers identical across repetitions"], rows))
        parts.append("")
        parts.append(
            "**Definitions.** *Initial failed request*: a logical upload whose first attempt failed. "
            "*Recovered*: a record in such a request that was synced by the end of the run (all passes). "
            "*Unrecovered*: one that was not. *Recovery %* = recovered / records in initially failed requests. "
            "*Unsynced after first pass*: records still pending when the first sync pass ended (a pass stops after "
            f"{config['max_consecutive_exhausted_batches']} consecutive batches exhaust their retries, leaving later "
            "batches untouched). *Total sync passes* = 1 + *extra passes*: further "
            "full sync passes, as the app would run on its next refresh, until nothing is pending. "
            "*Duplicate deliveries absorbed*: records that reached the server more than once (for example a retry "
            "after a lost response) and were applied as no-ops by the upsert."
        )
        parts.append("")

    return "\n".join(parts)


def _latency_row(label: str, summary: dict) -> list[str]:
    if not summary["count"]:
        return [label, "0", "n/a", "n/a", "n/a", "n/a"]
    return [label, _fmt(summary["count"]), _fmt(summary["p50"], 2), _fmt(summary["p95"], 2),
            _fmt(summary["mean"], 2), _fmt(summary["max"], 2)]


def _ai_section(ai: dict) -> str:
    config, provider, features = ai["config"], ai["provider"], ai["features"]
    cache, stampede, fallback = ai["cache"], ai["stampede"], ai["fallback"]
    is_stub = provider["mode"] == "stub"

    parts = ["## Weekly AI insight: features, cache and fallback (Ticket 4)", ""]
    if is_stub:
        delay = provider["stub_latency_ms"]
        parts.append(
            "> **No real model was called in this run.** The model provider was replaced by a stub "
            f"(injected delay per call: {_fmt(delay, 0)} ms), because no `ANTHROPIC_API_KEY` was available. "
            "Provider-call counts, cache hit rates, cached-response latency and fallback behaviour are real "
            "measurements of this code. **Cold-request latency here is the app's own overhead plus the stub's "
            "delay; it says nothing about real model latency.** To measure that, run with an API key: "
            "`ANTHROPIC_API_KEY=... python -m benchmarks.run_ai_insight_benchmark --provider real`."
        )
    else:
        parts.append(f"**Provider:** real Anthropic API, model `{provider['model']}`.")
    parts.append("")

    parts += ["### Methodology", ""]
    parts.append(
        "- The real FastAPI app runs in-process (uvicorn on localhost) against a **throwaway PostgreSQL "
        "database**; the benchmark process is the HTTP client. A wrapper around the provider counts and times "
        "every call the app makes to it.\n"
        f"- {config['users']} users each have a goal and a full synthetic week of nights (seed {config['seed']}, "
        f"week starting {config['week_start']}). Each user is one distinct (user, week) cache key.\n"
        f"- **Cold vs cached:** for every key the first request is cold (cache miss); the remaining "
        f"{config['requests_per_week'] - 1} requests for that same week should be cache hits, giving "
        f"{config['requests_per_week']} equivalent requests per key. A request counts as a **cache hit** when "
        "it completed without the provider being called (the per-request provider-call counter did not change).\n"
        "- **Latency** is client-observed HTTP latency on localhost (the client and server share one Python "
        "process); p50/p95 use linear interpolation between ranks.\n"
        f"- **Concurrent burst:** {config['stampede_requests']} simultaneous requests "
        f"({config['stampede_workers']} workers) for one uncached week.\n"
        f"- **Fallback:** with the provider failing on every call, {config['fallback_users']} users are each "
        "requested twice."
    )
    parts.append("")

    parts += ["### Structured weekly features sent to the model", ""]
    parts.append(_table(
        ["Nights per week", "Signals per night", "Signals per full week", "Prompt characters (mean)"],
        [[_fmt(features["nights_per_week"]), _fmt(features["signals_per_night"]),
          f"{_fmt(features['signals_per_week_min'])}"
          + (f"-{_fmt(features['signals_per_week_max'])}" if features["signals_per_week_max"] != features["signals_per_week_min"] else ""),
          _fmt(features["prompt_characters_mean"], 0)]]))
    parts.append("")
    parts.append(
        "Signals per night: total sleep, deep, REM, core, awake (minutes), bedtime deviation from the goal "
        "(minutes) and sleep score, measured from the features the app builds for the benchmark users. Source "
        "identifiers and raw timestamps are not sent."
    )
    parts.append("")

    parts += ["### Cache effectiveness", ""]
    parts.append(_table(
        ["Weeks (cache keys)", "Requests / week", "Total requests", "Provider calls", "Cache hits",
         "Hit rate", "Provider calls per 100 requests", "Provider-call reduction"],
        [[_fmt(cache["weeks"]), _fmt(cache["requests_per_week"]), _fmt(cache["total_requests"]),
          _fmt(cache["provider_calls"]), _fmt(cache["cache_hits"]), _fmt(cache["cache_hit_rate_pct"], 2) + "%",
          _fmt(cache["provider_calls_per_100_requests"], 2), _fmt(cache["provider_call_reduction_pct"], 2) + "%"]]))
    parts.append("")
    parts.append(
        f"Cached requests that still called the provider: {_fmt(cache['cached_requests_that_called_the_provider'])}. "
        f"Summary sources on cold requests: {cache['cold_summary_sources']}; on cached requests: "
        f"{cache['cached_summary_sources']}. Reduction = 1 - provider calls / total requests."
    )
    parts.append("")

    parts += ["### Latency", ""]
    latency_rows = [
        _latency_row("Cold request (cache miss)", cache["cold_request_latency_ms"]),
        _latency_row("Cached request (cache hit)", cache["cached_request_latency_ms"]),
    ]
    if not is_stub:
        latency_rows.append(_latency_row("Provider call alone", cache["provider_call_latency_ms"]))
    parts.append(_table(["Request type", "Samples", "p50 ms", "p95 ms", "Mean ms", "Max ms"], latency_rows))
    parts.append("")
    cold_p50, cached_p50 = cache["cold_request_latency_ms"]["p50"], cache["cached_request_latency_ms"]["p50"]
    if cold_p50 and cached_p50:
        note = (" This compares the app's own cold path (feature build, stub call, cache write) with a cache "
                "hit; it is not a comparison against real model latency." if is_stub else "")
        parts.append(f"Median cold request was {_fmt(cold_p50 / cached_p50, 1)}x the median cached request.{note}")
        parts.append("")
    if not is_stub and cache["tokens"]["calls_with_usage"]:
        tokens = cache["tokens"]
        parts.append(
            f"Tokens per provider call (mean over {tokens['calls_with_usage']} calls): "
            f"{_fmt(tokens['input_tokens_mean'], 0)} in, {_fmt(tokens['output_tokens_mean'], 0)} out."
        )
        parts.append("")

    parts += ["### Concurrent burst on an uncached week", ""]
    delay_note = ""
    if stampede.get("injected_provider_delay_ms"):
        delay_note = (f" The stub call was held for {_fmt(stampede['injected_provider_delay_ms'], 0)} ms so that "
                      "requests genuinely overlap; that delay is not a latency claim.")
    parts.append(_table(
        ["Requests", "Workers", "Successful", "Failed", "Provider calls", "Distinct summary texts",
         "Cache rows written", "p50 ms", "p95 ms"],
        [[_fmt(stampede["requests"]), _fmt(stampede["concurrent_workers"]), _fmt(stampede["successful_responses"]),
          _fmt(stampede["failed_responses"]), _fmt(stampede["provider_calls"]),
          _fmt(stampede["distinct_summary_texts"]), _fmt(stampede["cache_rows_written"]),
          _fmt(stampede["request_latency_ms"]["p50"], 1), _fmt(stampede["request_latency_ms"]["p95"], 1)]]))
    parts.append("")
    parts.append("A per-(user, week) database lock makes concurrent requests wait for the first one's result "
                 "instead of each calling the provider." + delay_note)
    parts.append("")

    parts += ["### Deterministic fallback when the provider fails", ""]
    parts.append(_table(
        ["Requests", "Fallback responses", "AI responses", "Same text on repeat", "Provider calls",
         "p50 ms", "p95 ms"],
        [[_fmt(fallback["requests"]), _fmt(fallback["fallback_responses"]), _fmt(fallback["ai_responses"]),
          "yes" if fallback["identical_text_on_repeat"] else "NO", _fmt(fallback["provider_calls"]),
          _fmt(fallback["request_latency_ms"]["p50"], 2), _fmt(fallback["request_latency_ms"]["p95"], 2)]]))
    parts.append("")
    parts.append("The fallback is not cached, so each request tries the provider again (provider calls equal "
                 "requests) and the summary returns to AI-written text as soon as the provider recovers.")
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
    environment = metadata.get("sync_benchmark_environment") or metadata.get("ai_insight_benchmark_environment")
    if environment:
        parts += ["## Environment", "", _environment_section(environment), ""]
        ai_environment = metadata.get("ai_insight_benchmark_environment")
        if ai_environment and ai_environment != environment:
            parts += [f"The AI insight benchmark was run at {ai_environment['captured_at_utc']} UTC on git "
                      f"{ai_environment['git_commit']}.", ""]

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
        "python -m benchmarks.run_ai_insight_benchmark   # add ANTHROPIC_API_KEY=... --provider real for real model latency",
        "python -m benchmarks.report                      # re-render BENCHMARKS.md from the JSON",
        "python -m pytest tests/test_benchmark_tooling.py",
        "```",
        "",
    ]
    if "sync_benchmark" in results:
        parts += [f"The sync benchmark in this file was run with: `{results['sync_benchmark']['config']['command']}`", ""]
    if "ai_insight_benchmark" in results:
        parts += [f"The AI insight benchmark in this file was run with: `{results['ai_insight_benchmark']['config']['command']}`", ""]
    if "sync_benchmark" in results:
        parts.append(_sync_section(results["sync_benchmark"]))
    if "ai_insight_benchmark" in results:
        parts.append(_ai_section(results["ai_insight_benchmark"]))

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
        "- Backoff delays are not slept (see Methodology).\n"
        "- AI insight benchmark: the client and the server share one Python process, and the model provider "
        "may be a stub (the report says which); with a stub, cold latency excludes real model latency. "
        "Synthetic data only, one week per user, one machine.",
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
