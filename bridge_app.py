"""Sobe o app Vitrine dentro do runner (Linux), carregando runtime/app.env."""

import os
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent
env_file = Path(os.environ.get("APP_ENV_FILE", BASE / "runtime" / "app.env"))
for raw in env_file.read_text(encoding="utf-8", errors="ignore").splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    os.environ[key.strip().lstrip("\ufeff")] = value.strip().strip('"').strip("'")

repo = Path(os.environ.get("APP_REPO", BASE / "app"))
os.chdir(repo)
sys.path.insert(0, str(repo))

import uvicorn  # noqa: E402

uvicorn.run(
    "app.main:app",
    host="127.0.0.1",
    port=int(os.environ.get("APP_PORT", "8010")),
    log_level="info",
    access_log=False,
)
