from __future__ import annotations

from typing import Any

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.plant import Plant


class PlantService:
    def __init__(self, db: Session):
        self.db = db

    def get_all(self, skip: int = 0, limit: int = 100) -> tuple[list[Plant], int]:
        from sqlalchemy import func
        total = self.db.execute(select(func.count()).select_from(Plant)).scalar_one()
        rows = self.db.execute(select(Plant).offset(skip).limit(limit)).scalars().all()
        return rows, total

    def get_by_id(self, plant_id: int) -> Plant | None:
        return self.db.execute(select(Plant).where(Plant.id == plant_id)).scalar_one_or_none()

    def search(self, q: str) -> list[Plant]:
        q_clean = q.strip()
        if not q_clean:
            return []
        pattern = f"%{q_clean}%"
        stmt = select(Plant).where(
            or_(
                Plant.common_name.ilike(pattern),
                Plant.scientific_name.ilike(pattern),
                Plant.hindi_name.ilike(pattern),
                Plant.family.ilike(pattern),
            )
        )
        return self.db.execute(stmt).scalars().all()

    def create_many(self, plants: list[dict[str, Any]]) -> None:
        for item in plants:
            plant = Plant(**item)
            self.db.add(plant)
        self.db.commit()
