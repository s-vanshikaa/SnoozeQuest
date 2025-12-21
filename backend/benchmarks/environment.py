import platform
import subprocess
from datetime import datetime, timezone
from importlib import metadata
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent


def _run(*command: str) -> str:
    try:
        return subprocess.run(
            command, capture_output=True, text=True, check=True, cwd=BACKEND_DIR
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def _sysctl(name: str) -> str:
    return _run("sysctl", "-n", name) if platform.system() == "Darwin" else "unknown"


def collect_environment(postgres_version: str | None = None) -> dict:
    """Facts about the machine and code, captured at run time (nothing hand-entered)."""
    packages = {}
    for name in ("fastapi", "uvicorn", "sqlalchemy", "psycopg2-binary", "httpx", "pydantic", "anthropic"):
        try:
            packages[name] = metadata.version(name)
        except metadata.PackageNotFoundError:
            packages[name] = "not installed"

    memory_bytes = _sysctl("hw.memsize")
    return {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "git_commit": _run("git", "rev-parse", "--short", "HEAD"),
        # Only the code under test: benchmark tooling changes don't affect what is measured.
        "git_working_tree_dirty": bool(_run("git", "status", "--porcelain", "--", "app", "alembic", "requirements.txt")),
        "os": platform.platform(),
        "cpu": _sysctl("machdep.cpu.brand_string"),
        "cpu_cores": _sysctl("hw.ncpu"),
        "memory_gb": round(int(memory_bytes) / 1024**3, 1) if memory_bytes.isdigit() else "unknown",
        "python": platform.python_version(),
        "packages": packages,
        "postgres_version": postgres_version or "unknown",
    }
