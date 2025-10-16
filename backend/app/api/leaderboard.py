from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.schemas.leaderboard import LeaderboardEntryOut
from app.services.leaderboard import get_leaderboard

router = APIRouter(prefix="/api/v1/leaderboard", tags=["leaderboard"])


@router.get("", response_model=list[LeaderboardEntryOut])
def leaderboard(db: Session = Depends(get_db)) -> list[LeaderboardEntryOut]:
    return get_leaderboard(db)
