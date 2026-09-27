"""Shared pagination and sorting primitives.

Every list endpoint in the API uses the same contract so the mobile client can
implement one paginator instead of one per resource.
"""

from __future__ import annotations

from typing import Generic, TypeVar

from fastapi import Query
from pydantic import BaseModel, Field

T = TypeVar("T")

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 200


class PageParams(BaseModel):
    limit: int = Field(default=DEFAULT_PAGE_SIZE, ge=1, le=MAX_PAGE_SIZE)
    offset: int = Field(default=0, ge=0)

    @property
    def page(self) -> int:
        return self.offset // self.limit + 1


def page_params(
    limit: int = Query(
        default=DEFAULT_PAGE_SIZE,
        ge=1,
        le=MAX_PAGE_SIZE,
        description="Maximum number of records to return.",
    ),
    offset: int = Query(
        default=0,
        ge=0,
        description="Number of records to skip.",
    ),
) -> PageParams:
    return PageParams(limit=limit, offset=offset)


class Page(BaseModel, Generic[T]):
    """Envelope for a list response."""

    items: list[T]
    total: int = Field(description="Total number of records matching the filter.")
    limit: int
    offset: int
    has_more: bool

    @classmethod
    def build(cls, items: list[T], total: int, limit: int, offset: int) -> "Page[T]":
        return cls(
            items=items,
            total=total,
            limit=limit,
            offset=offset,
            has_more=offset + len(items) < total,
        )


class SortOrder(str):
    ASC = "asc"
    DESC = "desc"


class PageMeta(BaseModel):
    total: int
    limit: int
    offset: int
    page: int
    has_more: bool
