"""Auth routes.

Kept as a package rather than a single ``auth.py`` module because the sibling
resource packages (plants, diagnosis, users, ...) already use that layout, and a
module and a package cannot share a name: ``app/api/v1/auth.py`` was silently
shadowed by this directory.
"""

from app.api.v1.auth.routes import router

__all__ = ["router"]
