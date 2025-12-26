"""Throwaway PostgreSQL database shared by the benchmarks, so they never touch dev data."""

import os
import subprocess
import sys

import psycopg2

from app.core.config import settings
from benchmarks.environment import BACKEND_DIR

BENCH_DB = "snoozequest_bench"


def connect(dbname: str):
    return psycopg2.connect(
        host=settings.postgres_host, port=settings.postgres_port,
        user=settings.postgres_user, password=settings.postgres_password, dbname=dbname,
    )


def create_database() -> None:
    connection = connect("postgres")
    connection.autocommit = True
    with connection.cursor() as cursor:
        cursor.execute(f"DROP DATABASE IF EXISTS {BENCH_DB} WITH (FORCE)")
        cursor.execute(f"CREATE DATABASE {BENCH_DB}")
    connection.close()


def drop_database() -> None:
    connection = connect("postgres")
    connection.autocommit = True
    with connection.cursor() as cursor:
        cursor.execute(f"DROP DATABASE IF EXISTS {BENCH_DB} WITH (FORCE)")
    connection.close()


def bench_env() -> dict[str, str]:
    return {**os.environ, "POSTGRES_DB": BENCH_DB}


def migrate() -> None:
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND_DIR, env=bench_env(), check=True, capture_output=True,
    )
