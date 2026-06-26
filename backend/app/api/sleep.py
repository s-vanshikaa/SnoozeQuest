from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_user_or_404
from app.database.session import get_db
from app.schemas.sleep import SleepSessionOut, SleepSyncRequest, SleepSyncResponse
from app.services.sleep import list_sessions, sync_sessions

router = APIRouter(prefix="/api/v1/sleep", tags=["sleep"])


@router.post("/sync", response_model=SleepSyncResponse)
def sync(payload: SleepSyncRequest, db: Session = Depends(get_db)) -> SleepSyncResponse:
    get_user_or_404(db, payload.user_id)

    sessions = sync_sessions(db, payload.user_id, payload.sessions)
    return SleepSyncResponse(synced=len(sessions), sessions=sessions)


@router.get("", response_model=list[SleepSessionOut])
def list_sleep_sessions(
    user_id: int,
    start_date: date | None = None,
    end_date: date | None = None,
    db: Session = Depends(get_db),
) -> list[SleepSessionOut]:
    get_user_or_404(db, user_id)

    return list_sessions(db, user_id, start_date, end_date)
