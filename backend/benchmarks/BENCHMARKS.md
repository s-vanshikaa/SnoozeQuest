# SnoozeQuest Benchmarks

Measured results for sync batching, reliability and idempotency. All numbers below are generated from `benchmark_results.json` by `benchmarks/report.py`; nothing is edited by hand. Re-running the commands below on other hardware will produce different absolute numbers.

## Environment

|  |  |
|---|---|
| Captured (UTC) | 2026-09-21T22:46:59+00:00 |
| Code version | git 29f9d3e |
| Machine | Apple M3, 8 cores, 8.0 GB RAM |
| OS | macOS-26.6.2-arm64-arm-64bit-Mach-O |
| Python | 3.13.5 |
| Packages | fastapi 0.115.0, uvicorn 0.30.6, sqlalchemy 2.0.35, psycopg2-binary 2.9.12, httpx 0.27.2, pydantic 2.9.2, anthropic 0.122.0 |
| PostgreSQL | PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2) on aarch64-unknown-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit |

## Commands

Prerequisites: the PostgreSQL container is running (`docker compose up -d db` in `backend/`), `backend/.env` holds the database credentials, and dependencies are installed (`pip install -r requirements.txt`).

```bash
cd backend
python -m benchmarks.run_sync_benchmark   # writes benchmarks/benchmark_results.json and BENCHMARKS.md
python -m pytest tests/test_benchmark_tooling.py
```

The sync benchmark in this file was run with: `python -m benchmarks.run_sync_benchmark `

## Sync throughput and reliability (Tickets 2-3)

**Workload:** 10,000 synthetic sleep sessions (seed 42), batch sizes 1, 25, 100, 250, 3 timed repetitions per configuration.  
**Client retry policy modelled:** up to 4 attempts per request, exponential backoff from 0.5s capped at 8.0s, full jitter.

### Methodology

- The real FastAPI app is started from the current code with uvicorn (1 worker) against a **throwaway PostgreSQL database** created for the run and dropped afterwards. Nothing touches the development database.
- Sessions are generated deterministically from the seed. Each has a unique `external_id`, so the number of unique records is exactly the workload size.
- A Python model of the iOS `SyncEngine` (`benchmarks/sync_client.py`) uploads them: batches of at most `batch_size`, retry with backoff on transient failures, no retry of permanent failures, and the run stops after a request exhausts its retries.
- Each configuration is run 3 times on an emptied table; the table reports the **median** of the repetitions, with the min-max range for total runtime.
- **Runtime** is wall-clock time for all sync passes, from the first request to the last response. **Latency** is measured per HTTP request that reached the server (client-observed, including JSON encoding, on localhost); p50/p95 use linear interpolation between ranks.
- Backoff waits are **computed and totalled but not slept**, so runtime reflects request work only; `simulated backoff` shows how long a real client would additionally have waited.
- **Duplicates** are `rows - distinct external_ids` in the database after the run, and the session-minutes checksum is compared with the generated data.
- **Fault injection:** each request attempt fails independently with the scenario's probability, drawn from a seeded generator, so the fault sequence is identical on every run. A failure is one of `connection_error` (never reaches the server), `http_503` (never reaches the server) or `lost_response` (the server commits the batch but the response is dropped, so the client retries a batch the server already accepted). The three kinds are equally likely.

### Throughput by batch size (no injected faults)

| Batch size | Records | API requests | Runtime s, median (range) | Records/s | p50 ms | p95 ms | Failures | Duplicates |
|---|---|---|---|---|---|---|---|---|
| 1 | 10,000 | 10,000 | 45.91 (45.69-46.94) | 218 | 4.44 | 7.20 | 0 | 0 |
| 25 | 10,000 | 400 | 3.23 (3.20-3.82) | 3,100 | 8.08 | 12.12 | 0 | 0 |
| 100 | 10,000 | 100 | 1.79 (1.74-1.79) | 5,602 | 17.19 | 21.42 | 0 | 0 |
| 250 | 10,000 | 40 | 1.70 (1.52-2.24) | 5,881 | 38.04 | 52.41 | 0 | 0 |

Batch size 100 used 100 requests against 10,000 for batch size 1 (99.0% fewer), and synced 25.7x as many records per second (5,602 vs 218).

### Recovery under 30% transient request failures

| Batch size | Attempts | API requests reaching server | Initial failed requests | Records in those requests | Recovered | Unrecovered | Recovery % | Avg attempts / request | Avg retries / failed request | Duplicate deliveries absorbed | Duplicates in DB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 14,303 | 11,410 | 2,984 | 2,952 | 2,952 | 0 | 100.00% | 1.417 | 1.410 | 1,410 | 0 |
| 25 | 578 | 451 | 117 | 2,925 | 2,925 | 0 | 100.00% | 1.434 | 1.496 | 1,275 | 0 |
| 100 | 137 | 113 | 26 | 2,600 | 2,600 | 0 | 100.00% | 1.356 | 1.385 | 1,300 | 0 |
| 250 | 64 | 46 | 15 | 3,750 | 3,750 | 0 | 100.00% | 1.600 | 1.600 | 1,500 | 0 |

### Passes needed and cost of recovery

| Batch size | Records synced | Unsynced after first pass | Extra passes to finish | Unsynced at end | Runtime s (median) | Records/s | Simulated backoff s | p50 ms | p95 ms | Reliability numbers identical across repetitions |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 10,000 | 9,940 | 95 | 0 | 52.39 | 191 | 1,504.6 | 4.40 | 7.05 | yes |
| 25 | 10,000 | 8,075 | 3 | 0 | 3.60 | 2,782 | 69.7 | 7.97 | 10.81 | yes |
| 100 | 10,000 | 200 | 1 | 0 | 2.07 | 4,827 | 16.6 | 18.02 | 22.07 | yes |
| 250 | 10,000 | 0 | 0 | 0 | 1.86 | 5,382 | 8.5 | 37.21 | 46.44 | yes |

**Definitions.** *Initial failed request*: a logical upload whose first attempt failed. *Recovered*: a record in such a request that was synced by the end of the run (all passes). *Unrecovered*: one that was not. *Recovery %* = recovered / records in initially failed requests. *Unsynced after first pass*: records still pending when the first sync pass ended (a pass stops at the first request that exhausts its retries, leaving later batches untouched). *Extra passes*: further full sync passes, as the app would run on its next refresh, until nothing is pending. *Duplicate deliveries absorbed*: records that reached the server more than once (for example a retry after a lost response) and were applied as no-ops by the upsert.

## Limitations

- The iOS client is Swift and cannot be driven from a load script. The benchmark uses a Python model of its upload algorithm (`benchmarks/sync_client.py`); the batching and retry constants are duplicated and must be kept in step with `SyncEngine.swift`. The numbers characterise the backend and the algorithm, not the app on a device.
- Everything runs on one machine over localhost, with PostgreSQL in a container on the same host, so there is no real network latency, packet loss or cellular behaviour. Absolute latencies will be higher for a real device.
- Faults are injected in the client transport, not by breaking the network or the server.
- One synthetic user, one uvicorn worker, and one machine; no concurrent-client load.
- Backoff delays are not slept (see Methodology).
