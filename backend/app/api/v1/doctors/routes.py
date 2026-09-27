from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.errors import success_payload
from app.database.session import get_db
from app.models.experts import Doctor

router = APIRouter(prefix="/doctors", tags=["doctors"])
DbSession = Annotated[Session, Depends(get_db)]


@router.get("", summary="List verified public doctor profiles")
async def list_doctors(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: DbSession = None,
) -> dict[str, Any]:
    rows = db.execute(
        select(Doctor)
        .where(Doctor.deleted_at.is_(None), Doctor.verification_status == "VERIFIED")
        .order_by(Doctor.full_name)
        .limit(limit)
        .offset(offset)
    ).scalars().all()
    items = [
        {
            "id": str(d.id),
            "full_name": d.full_name,
            "qualifications": d.qualifications,
            "designation": d.designation,
            "organization": d.organization,
            "organization_type": d.organization_type,
            "country_code": d.country_code,
            "region": d.region,
            "city": d.city,
            "verification_status": d.verification_status,
            "consultation_available": d.consultation_available,
            "consultation_mode": d.consultation_mode,
            "website_url": d.website_url,
            "public_email": d.public_email,
            "public_phone_e164": d.public_phone_e164,
        }
        for d in rows
    ]
    total = db.scalar(
        select(func.count()).select_from(Doctor).where(
            Doctor.deleted_at.is_(None), Doctor.verification_status == "VERIFIED"
        )
    )
    return success_payload({"items": items, "total": total or 0, "limit": limit, "offset": offset})


@router.get("/{doctor_id}", summary="Fetch one doctor profile")
async def get_doctor(doctor_id: str, db: DbSession = None) -> dict[str, Any]:
    row = db.get(Doctor, doctor_id)
    if row is None or row.deleted_at is not None or row.verification_status != "VERIFIED":
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="doctor not found")
    return success_payload(
        {
            "id": str(row.id),
            "full_name": row.full_name,
            "qualifications": row.qualifications,
            "designation": row.designation,
            "organization": row.organization,
            "organization_type": row.organization_type,
            "bio": row.bio,
            "country_code": row.country_code,
            "region": row.region,
            "city": row.city,
            "service_areas": row.service_areas,
            "years_of_experience": row.years_of_experience,
            "languages_spoken": row.languages_spoken,
            "public_email": row.public_email,
            "public_phone_e164": row.public_phone_e164,
            "website_url": row.website_url,
            "verification_status": row.verification_status,
            "consultation_available": row.consultation_available,
            "consultation_mode": row.consultation_mode,
            "consultation_notes": row.consultation_notes,
        }
    )
