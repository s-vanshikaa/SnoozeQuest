# SnoozeQuest Benchmarks

Measured results for sync batching, reliability and idempotency. All numbers below are generated from `benchmark_results.json` by `benchmarks/report.py`; nothing is edited by hand. Re-running the commands below on other hardware will produce different absolute numbers.

## Environment

|  |  |
|---|---|
| Captured (UTC) | 2026-09-21T23:05:47+00:00 |
| Code version | git fb5ac2c |
| Machine | Apple M3, 8 cores, 8.0 GB RAM |
| OS | macOS-26.6.2-arm64-arm-64bit-Mach-O |
| Python | 3.13.5 |
| Packages | fastapi 0.115.0, uvicorn 0.30.6, sqlalchemy 2.0.35, psycopg2-binary 2.9.12, httpx 0.27.2, pydantic 2.9.2, anthropic 0.122.0 |
| PostgreSQL | PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2) on aarch64-unknown-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit |

The AI insight benchmark was run at 2026-09-21T23:19:19+00:00 UTC on git 9f3266e.

## Commands

Prerequisites: the PostgreSQL container is running (`docker compose up -d db` in `backend/`), `backend/.env` holds the database credentials, and dependencies are installed (`pip install -r requirements.txt`).

```bash
cd backend
python -m benchmarks.run_sync_benchmark   # writes benchmarks/benchmark_results.json and BENCHMARKS.md
python -m benchmarks.run_ai_insight_benchmark   # add ANTHROPIC_API_KEY=... --provider real for real model latency
python -m benchmarks.report                      # re-render BENCHMARKS.md from the JSON
python -m pytest tests/test_benchmark_tooling.py
```

The sync benchmark in this file was run with: `python -m benchmarks.run_sync_benchmark `

The AI insight benchmark in this file was run with: `python -m benchmarks.run_ai_insight_benchmark `

## Sync throughput and reliability (Tickets 2-3)

**Workload:** 10,000 synthetic sleep sessions (seed 42), batch sizes 1, 25, 100, 250, 3 timed repetitions per configuration.  
**Client retry policy modelled:** up to 4 attempts per request, exponential backoff from 0.5s capped at 8.0s, full jitter.

### Methodology

- The real FastAPI app is started from the current code with uvicorn (1 worker) against a **throwaway PostgreSQL database** created for the run and dropped afterwards. Nothing touches the development database.
- Sessions are generated deterministically from the seed. Each has a unique `external_id`, so the number of unique records is exactly the workload size.
- A Python model of the iOS `SyncEngine` (`benchmarks/sync_client.py`) uploads them: batches of at most `batch_size`, retry with backoff on transient failures, no retry of permanent failures, a batch that exhausts its retries is left unsynced while the run continues, and the run stops after 3 consecutive batches exhaust their retries.
- Each configuration is run 3 times on an emptied table; the table reports the **median** of the repetitions, with the min-max range for total runtime.
- **Runtime** is wall-clock time for all sync passes, from the first request to the last response. **Latency** is measured per HTTP request that reached the server (client-observed, including JSON encoding, on localhost); p50/p95 use linear interpolation between ranks.
- Backoff waits are **computed and totalled but not slept**, so runtime reflects request work only; `simulated backoff` shows how long a real client would additionally have waited.
- **Duplicates** are `rows - distinct external_ids` in the database after the run, and the session-minutes checksum is compared with the generated data.
- **Fault injection:** each request attempt fails independently with the scenario's probability, drawn from a seeded generator, so the fault sequence is identical on every run. A failure is one of `connection_error` (never reaches the server), `http_503` (never reaches the server) or `lost_response` (the server commits the batch but the response is dropped, so the client retries a batch the server already accepted). The three kinds are equally likely.

### Throughput by batch size (no injected faults)

| Batch size | Records | API requests | Runtime s, median (range) | Records/s | p50 ms | p95 ms | Failures | Duplicates |
|---|---|---|---|---|---|---|---|---|
| 1 | 10,000 | 10,000 | 46.74 (46.26-47.49) | 214 | 4.57 | 7.06 | 0 | 0 |
| 25 | 10,000 | 400 | 3.23 (3.10-3.35) | 3,100 | 8.06 | 9.70 | 0 | 0 |
| 100 | 10,000 | 100 | 1.84 (1.79-1.85) | 5,440 | 18.06 | 21.25 | 0 | 0 |
| 250 | 10,000 | 40 | 1.59 (1.59-1.61) | 6,276 | 38.39 | 46.71 | 0 | 0 |

Batch size 100 used 100 requests against 10,000 for batch size 1 (99.0% fewer), and synced 25.4x as many records per second (5,440 vs 214).

### Recovery under 30% transient request failures

| Batch size | Attempts | API requests reaching server | Initial failed requests | Records in those requests | Recovered | Unrecovered | Recovery % | Avg attempts / request | Avg retries / failed request | Duplicate deliveries absorbed | Duplicates in DB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 14,303 | 11,410 | 2,984 | 2,948 | 2,948 | 0 | 100.00% | 1.417 | 1.410 | 1,410 | 0 |
| 25 | 578 | 451 | 117 | 2,875 | 2,875 | 0 | 100.00% | 1.434 | 1.496 | 1,275 | 0 |
| 100 | 137 | 113 | 26 | 2,500 | 2,500 | 0 | 100.00% | 1.356 | 1.385 | 1,300 | 0 |
| 250 | 64 | 46 | 15 | 3,750 | 3,750 | 0 | 100.00% | 1.600 | 1.600 | 1,500 | 0 |

### Passes needed and cost of recovery

| Batch size | Records synced | Unsynced after first pass | Total sync passes | Unsynced at end | Runtime s (median) | Records/s | Simulated backoff s | p50 ms | p95 ms | Reliability numbers identical across repetitions |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 10,000 | 93 | 3 | 0 | 53.43 | 187 | 1,504.6 | 4.55 | 7.20 | yes |
| 25 | 10,000 | 75 | 2 | 0 | 5.80 | 1,725 | 69.7 | 13.09 | 19.02 | yes |
| 100 | 10,000 | 100 | 2 | 0 | 2.18 | 4,595 | 16.6 | 19.37 | 22.32 | yes |
| 250 | 10,000 | 0 | 1 | 0 | 1.94 | 5,151 | 8.5 | 41.76 | 48.09 | yes |

**Definitions.** *Initial failed request*: a logical upload whose first attempt failed. *Recovered*: a record in such a request that was synced by the end of the run (all passes). *Unrecovered*: one that was not. *Recovery %* = recovered / records in initially failed requests. *Unsynced after first pass*: records still pending when the first sync pass ended (a pass stops after 3 consecutive batches exhaust their retries, leaving later batches untouched). *Total sync passes* = 1 + *extra passes*: further full sync passes, as the app would run on its next refresh, until nothing is pending. *Duplicate deliveries absorbed*: records that reached the server more than once (for example a retry after a lost response) and were applied as no-ops by the upsert.

## Weekly AI insight: features, cache and fallback (Ticket 4)

> **No real model was called in this run.** The model provider was replaced by a stub (injected delay per call: 0 ms), because no `ANTHROPIC_API_KEY` was available. Provider-call counts, cache hit rates, cached-response latency and fallback behaviour are real measurements of this code. **Cold-request latency here is the app's own overhead plus the stub's delay; it says nothing about real model latency.** To measure that, run with an API key: `ANTHROPIC_API_KEY=... python -m benchmarks.run_ai_insight_benchmark --provider real`.

### Methodology

- The real FastAPI app runs in-process (uvicorn on localhost) against a **throwaway PostgreSQL database**; the benchmark process is the HTTP client. A wrapper around the provider counts and times every call the app makes to it.
- 30 users each have a goal and a full synthetic week of nights (seed 42, week starting 2026-09-14). Each user is one distinct (user, week) cache key.
- **Cold vs cached:** for every key the first request is cold (cache miss); the remaining 99 requests for that same week should be cache hits, giving 100 equivalent requests per key. A request counts as a **cache hit** when it completed without the provider being called (the per-request provider-call counter did not change).
- **Latency** is client-observed HTTP latency on localhost (the client and server share one Python process); p50/p95 use linear interpolation between ranks.
- **Concurrent burst:** 100 simultaneous requests (12 workers) for one uncached week.
- **Fallback:** with the provider failing on every call, 20 users are each requested twice.

### Structured weekly features sent to the model

| Nights per week | Signals per night | Signals per full week | Prompt characters (mean) |
|---|---|---|---|
| 7 | 7 | 49 | 1,051 |

Signals per night: total sleep, deep, REM, core, awake (minutes), bedtime deviation from the goal (minutes) and sleep score, measured from the features the app builds for the benchmark users. Source identifiers and raw timestamps are not sent.

### Cache effectiveness

| Weeks (cache keys) | Requests / week | Total requests | Provider calls | Cache hits | Hit rate | Provider calls per 100 requests | Provider-call reduction |
|---|---|---|---|---|---|---|---|
| 30 | 100 | 3,000 | 30 | 2,970 | 99.00% | 1.00 | 99.00% |

Cached requests that still called the provider: 0. Summary sources on cold requests: {'ai': 30}; on cached requests: {'ai': 2970}. Reduction = 1 - provider calls / total requests.

### Latency

| Request type | Samples | p50 ms | p95 ms | Mean ms | Max ms |
|---|---|---|---|---|---|
| Cold request (cache miss) | 30 | 7.09 | 11.39 | 7.74 | 20.09 |
| Cached request (cache hit) | 2,970 | 4.11 | 7.13 | 4.63 | 45.12 |

Median cold request was 1.7x the median cached request. This compares the app's own cold path (feature build, stub call, cache write) with a cache hit; it is not a comparison against real model latency.

### Concurrent burst on an uncached week

| Requests | Workers | Successful | Failed | Provider calls | Distinct summary texts | Cache rows written | p50 ms | p95 ms |
|---|---|---|---|---|---|---|---|---|
| 100 | 12 | 100 | 0 | 1 | 1 | 1 | 37.0 | 238.0 |

A per-(user, week) database lock makes concurrent requests wait for the first one's result instead of each calling the provider. The stub call was held for 200 ms so that requests genuinely overlap; that delay is not a latency claim.

### Deterministic fallback when the provider fails

| Requests | Fallback responses | AI responses | Same text on repeat | Provider calls | p50 ms | p95 ms |
|---|---|---|---|---|---|---|
| 40 | 40 | 0 | yes | 40 | 5.31 | 8.82 |

The fallback is not cached, so each request tries the provider again (provider calls equal requests) and the summary returns to AI-written text as soon as the provider recovers.

## Limitations

- The iOS client is Swift and cannot be driven from a load script. The benchmark uses a Python model of its upload algorithm (`benchmarks/sync_client.py`); the batching and retry constants are duplicated and must be kept in step with `SyncEngine.swift`. The numbers characterise the backend and the algorithm, not the app on a device.
- Everything runs on one machine over localhost, with PostgreSQL in a container on the same host, so there is no real network latency, packet loss or cellular behaviour. Absolute latencies will be higher for a real device.
- Faults are injected in the client transport, not by breaking the network or the server.
- One synthetic user, one uvicorn worker, and one machine; no concurrent-client load.
- Backoff delays are not slept (see Methodology).
- AI insight benchmark: the client and the server share one Python process, and the model provider may be a stub (the report says which); with a stub, cold latency excludes real model latency. Synthetic data only, one week per user, one machine.
