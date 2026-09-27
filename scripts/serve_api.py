#!/usr/bin/env python3
"""Local development server entry point."""

import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

import uvicorn

from plantdoctor_api.config import get_settings

BACKEND_DIR = REPO_ROOT / "backend"


def main() -> None:
    settings = get_settings()
    os.chdir(BACKEND_DIR)
    if str(BACKEND_DIR) not in sys.path:
        sys.path.insert(0, str(BACKEND_DIR))
    uvicorn.run(
        "plantdoctor_api.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=True,
        log_level=settings.log_level.lower(),
    )


if __name__ == "__main__":
    main()
