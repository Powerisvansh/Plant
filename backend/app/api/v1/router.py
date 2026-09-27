"""API v1 router aggregation.

Each module owns one resource and exposes a ``router``. Adding a resource here
is the only change needed to publish it under ``/api/v1``.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import (
    auth,
    diagnosis,
    diseases,
    doctors,
    health,
    medicines,
    my_plants,
    plants,
    sources,
    symptoms,
    treatments,
)

api_router = APIRouter()

# Mounted without an extra prefix so the probes read as /api/v1/health and
# /api/v1/health/database, matching the root-level aliases.
api_router.include_router(health.router)

# Auth owns the /auth prefix itself. The path strings here are duplicated in
# app.core.rate_limit.default_rules; the two must be changed together or a
# renamed endpoint silently loses its throttle.
api_router.include_router(auth.router)
api_router.include_router(diagnosis.router)
api_router.include_router(sources.router)
api_router.include_router(plants.router)
api_router.include_router(diseases.router)
api_router.include_router(symptoms.router)
api_router.include_router(treatments.router)
api_router.include_router(medicines.router)
api_router.include_router(doctors.router)
api_router.include_router(my_plants.router)

__all__ = ["api_router"]
