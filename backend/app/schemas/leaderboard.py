from pydantic import BaseModel


class LeaderboardEntryOut(BaseModel):
    id: int
    name: str
    rank: int
    average_score: float
    goals_met: int
