from datetime import date

from sqlalchemy import Row, func
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.models import SleepSession
from app.schemas.sleep import SleepSessionIn


_UPSERT_COLUMNS = (
    "start_time",
    "end_time",
    "deep_minutes",
    "rem_minutes",
    "core_minutes",
    "awake_minutes",
)


def sync_sessions(db: Session, user_id: int, sessions_in: list[SleepSessionIn]) -> list[Row]:
    """Upsert a batch of sessions in one statement, keyed on (user_id, external_id).

    A single INSERT ... ON CONFLICT DO UPDATE is atomic per row, so concurrent or retried
    requests for the same session can never create duplicates or fail on the unique index.
    Rows come back in the order the caller first sent them.
    """
    # Postgres rejects an upsert that touches the same row twice, so collapse repeats (last wins).
    latest_by_external_id = {session_in.external_id: session_in for session_in in sessions_in}

    # Inserting in a fixed order makes concurrent batches take row locks in the same order,
    # which rules out deadlocks between overlapping requests.
    rows = [
        {"user_id": user_id, **latest_by_external_id[external_id].model_dump()}
        for external_id in sorted(latest_by_external_id)
    ]

    stmt = insert(SleepSession).values(rows)
    stmt = stmt.on_conflict_do_update(
        constraint="uq_sleep_sessions_user_external_id",
        set_={column: stmt.excluded[column] for column in _UPSERT_COLUMNS},
    ).returning(*SleepSession.__table__.c)

    returned = {row.external_id: row for row in db.execute(stmt)}
    db.commit()
    return [returned[external_id] for external_id in latest_by_external_id]


def list_sessions(
    db: Session, user_id: int, start_date: date | None, end_date: date | None
) -> list[SleepSession]:
    query = db.query(SleepSession).filter(SleepSession.user_id == user_id)
    if start_date is not None:
        query = query.filter(func.date(SleepSession.start_time) >= start_date)
    if end_date is not None:
        query = query.filter(func.date(SleepSession.start_time) <= end_date)
    return query.order_by(SleepSession.start_time.desc()).all()
