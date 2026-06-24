from datetime import date

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models import SleepSession
from app.schemas.sleep import SleepSessionIn


def sync_sessions(db: Session, user_id: int, sessions_in: list[SleepSessionIn]) -> list[SleepSession]:
    external_ids = [session_in.external_id for session_in in sessions_in]
    existing = (
        db.query(SleepSession)
        .filter(SleepSession.user_id == user_id, SleepSession.external_id.in_(external_ids))
        .all()
    )
    existing_by_external_id = {session.external_id: session for session in existing}

    sessions = []
    for session_in in sessions_in:
        session = existing_by_external_id.get(session_in.external_id)
        if session is None:
            session = SleepSession(user_id=user_id, external_id=session_in.external_id)
            db.add(session)

        session.start_time = session_in.start_time
        session.end_time = session_in.end_time
        session.deep_minutes = session_in.deep_minutes
        session.rem_minutes = session_in.rem_minutes
        session.core_minutes = session_in.core_minutes
        session.awake_minutes = session_in.awake_minutes
        sessions.append(session)

    db.commit()
    return sessions


def list_sessions(
    db: Session, user_id: int, start_date: date | None, end_date: date | None
) -> list[SleepSession]:
    query = db.query(SleepSession).filter(SleepSession.user_id == user_id)
    if start_date is not None:
        query = query.filter(func.date(SleepSession.start_time) >= start_date)
    if end_date is not None:
        query = query.filter(func.date(SleepSession.start_time) <= end_date)
    return query.order_by(SleepSession.start_time.desc()).all()
