"""Add ``refresh_tokens.family_id`` for rotation reuse detection.

Every token descended from one login shares a ``family_id``. Presenting a token
that has already been rotated means one of the holders is an attacker, and the
whole family must be revoked. Without this column only a single session could be
revoked, and two legitimate rotations could not be told apart from a replay.

Adding a NOT NULL column to a table that may already hold rows needs three
steps, not one. A bare ``ADD COLUMN ... NOT NULL`` fails as soon as the table is
non-empty, which is exactly the situation on a server that has been running for
a while:

1. add the column nullable,
2. backfill existing rows with their own ``session_id`` - self-consistent, so a
   pre-existing token can still be revoked individually - and attach a
   permanent default,
3. drop the default and set NOT NULL, so every future insert is forced to
   supply a real family.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002_refresh_family"
down_revision: str | None = "0001_initial"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "refresh_tokens",
        sa.Column("family_id", sa.UUID(), nullable=True),
    )
    op.execute(
        "UPDATE refresh_tokens SET family_id = session_id WHERE family_id IS NULL"
    )
    op.alter_column(
        "refresh_tokens",
        "family_id",
        existing_type=sa.UUID(),
        nullable=False,
    )
    op.create_index(
        op.f("ix_refresh_tokens_family_id"), "refresh_tokens", ["family_id"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_refresh_tokens_family_id"), table_name="refresh_tokens")
    op.drop_column("refresh_tokens", "family_id")
