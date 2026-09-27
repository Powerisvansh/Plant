from __future__ import annotations

import hashlib
import io
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile, status
from PIL import Image, UnidentifiedImageError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import CurrentUser
from app.core.config import get_settings
from app.core.errors import AppError, ErrorCode, success_payload
from app.database.session import get_db
from app.models.diagnosis import Diagnosis, DiagnosisImage
from app.models.enums import DiagnosisStatus, FileKind
from app.models.files import StoredFile

router = APIRouter(prefix="/diagnosis", tags=["diagnosis"])
DbSession = Annotated[Session, Depends(get_db)]


def _safe_filename(filename: str | None, suffix: str) -> str:
    stem = (filename or "upload").split("/")[-1].split("\\")[-1]
    stem = stem.strip() or "upload"
    safe = "".join(ch if ch.isalnum() or ch in {"-", "_", "."} else "_" for ch in stem)
    safe = safe or f"upload{suffix}"
    if not safe.lower().endswith(suffix.lower()):
        safe = f"{Path(safe).stem}{suffix}"
    return safe


def _validate_image_bytes(data: bytes, declared_mime: str | None) -> tuple[str, int, int]:
    settings = get_settings()
    allowed = {m.lower() for m in settings.ALLOWED_IMAGE_MIME_TYPES}
    mime = (declared_mime or "image/png").lower()
    if mime not in allowed:
        raise AppError(
            "Only PNG, JPEG and WebP images are allowed.",
            code=ErrorCode.UNSUPPORTED_MEDIA_TYPE,
            status_code=415,
        )

    try:
        with Image.open(io.BytesIO(data)) as img:
            img.verify()
    except (OSError, UnidentifiedImageError, ValueError) as exc:
        raise AppError(
            "The uploaded file is not a valid image.",
            code=ErrorCode.IMAGE_INVALID,
            status_code=400,
        ) from exc

    try:
        with Image.open(io.BytesIO(data)) as img:
            width, height = img.size
            if width < settings.MIN_IMAGE_DIMENSION or height < settings.MIN_IMAGE_DIMENSION:
                raise AppError(
                    "Image dimensions are too small.",
                    code=ErrorCode.IMAGE_DIMENSIONS_INVALID,
                    status_code=400,
                )
            if width > settings.MAX_IMAGE_DIMENSION or height > settings.MAX_IMAGE_DIMENSION:
                raise AppError(
                    "Image dimensions are too large.",
                    code=ErrorCode.IMAGE_DIMENSIONS_INVALID,
                    status_code=400,
                )
            if width * height > settings.MAX_IMAGE_PIXELS:
                raise AppError(
                    "Image is too large to process.",
                    code=ErrorCode.IMAGE_DIMENSIONS_INVALID,
                    status_code=400,
                )
            if img.format:
                mime = img.get_format_mimetype() or mime
    except (OSError, UnidentifiedImageError, ValueError) as exc:
        raise AppError(
            "The uploaded file is not a valid image.",
            code=ErrorCode.IMAGE_INVALID,
            status_code=400,
        ) from exc

    return mime, width, height


@router.get("", summary="List the current user's diagnosis records")
async def list_diagnoses(
    auth: CurrentUser,
    db: DbSession,
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    total = db.scalar(
        select(func.count(Diagnosis.id)).where(
            Diagnosis.user_id == auth.id,
            Diagnosis.deleted_at.is_(None),
        )
    ) or 0
    rows = db.execute(
        select(Diagnosis)
        .where(Diagnosis.user_id == auth.id, Diagnosis.deleted_at.is_(None))
        .order_by(Diagnosis.created_at.desc())
        .limit(limit)
        .offset(offset)
    ).scalars().all()

    items: list[dict[str, Any]] = []
    for diagnosis in rows:
        image_row = db.execute(
            select(DiagnosisImage)
            .where(DiagnosisImage.diagnosis_id == diagnosis.id)
            .order_by(DiagnosisImage.position.asc())
            .limit(1)
        ).scalar_one_or_none()
        stored = image_row.stored_file if image_row is not None else None
        items.append(
            {
                "id": str(diagnosis.id),
                "status": diagnosis.status.value if hasattr(diagnosis.status, "value") else str(diagnosis.status),
                "notes": diagnosis.user_notes,
                "model_name": diagnosis.model_name,
                "analysis_location": diagnosis.analysis_location,
                "created_at": diagnosis.created_at.isoformat() if diagnosis.created_at else None,
                "image": {
                    "id": str(stored.id),
                    "storage_key": stored.storage_key,
                    "mime_type": stored.mime_type,
                    "size_bytes": stored.size_bytes,
                    "width": stored.width,
                    "height": stored.height,
                } if stored is not None else None,
            }
        )

    return success_payload(
        items,
        meta={"total": total, "limit": limit, "offset": offset},
    )


@router.post("", status_code=status.HTTP_201_CREATED, summary="Upload an image for diagnosis")
async def create_diagnosis(
    auth: CurrentUser,
    db: DbSession,
    file: UploadFile = File(...),
    notes: str | None = Form(default=None),
) -> dict[str, Any]:
    if file.filename is None:
        raise AppError("An image file is required.", code=ErrorCode.VALIDATION_ERROR, status_code=422)

    raw = await file.read()
    if not raw:
        raise AppError("The uploaded file is empty.", code=ErrorCode.VALIDATION_ERROR, status_code=422)

    mime, width, height = _validate_image_bytes(raw, file.content_type)
    if len(raw) > get_settings().MAX_UPLOAD_BYTES:
        raise AppError(
            "The uploaded image is too large.",
            code=ErrorCode.FILE_TOO_LARGE,
            status_code=413,
        )

    ext = ".png"
    if mime == "image/jpeg":
        ext = ".jpg"
    elif mime == "image/webp":
        ext = ".webp"

    filename = _safe_filename(file.filename, ext)
    date_dir = datetime.now(UTC).strftime("%Y/%m/%d")
    storage_root = get_settings().uploads_root / "diagnosis-images" / date_dir
    storage_root.mkdir(parents=True, exist_ok=True)
    storage_key = f"diagnosis-images/{date_dir}/{uuid.uuid4()}{ext}"
    destination = get_settings().uploads_root / storage_key
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(raw)

    digest = hashlib.sha256(raw).hexdigest()
    stored = StoredFile(
        owner_user_id=auth.id,
        kind=FileKind.DIAGNOSIS_IMAGE,
        storage_backend="filesystem",
        storage_key=storage_key,
        original_filename=file.filename,
        safe_filename=filename,
        mime_type=mime,
        size_bytes=len(raw),
        width=width,
        height=height,
        sha256=digest,
        is_public=False,
        content_type_verified=True,
        is_processed=False,
    )
    db.add(stored)
    db.flush()

    diagnosis = Diagnosis(
        user_id=auth.id,
        status=DiagnosisStatus.PENDING,
        user_notes=notes,
        analysis_location="client",
    )
    db.add(diagnosis)
    db.flush()

    image_link = DiagnosisImage(
        diagnosis_id=diagnosis.id,
        stored_file_id=stored.id,
        position=1,
        is_primary=True,
        subject_type="other",
    )
    db.add(image_link)
    db.commit()
    db.refresh(stored)
    db.refresh(diagnosis)

    return success_payload(
        {
            "id": str(diagnosis.id),
            "status": diagnosis.status.value if hasattr(diagnosis.status, "value") else str(diagnosis.status),
            "notes": diagnosis.user_notes,
            "created_at": diagnosis.created_at.isoformat() if diagnosis.created_at else None,
            "image": {
                "id": str(stored.id),
                "storage_key": stored.storage_key,
                "mime_type": stored.mime_type,
                "size_bytes": stored.size_bytes,
                "width": stored.width,
                "height": stored.height,
            },
        }
    )
