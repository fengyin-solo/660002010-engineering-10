"""运行期配置：全部来自环境变量（根目录 .env 由 scripts/dev.sh 加载），换机器只改 .env。"""
import os
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent

DATA_DIR = Path(os.getenv("DATA_DIR", str(BACKEND_DIR / "data")))
SEED_FILE = DATA_DIR / "seed.json"
STATE_FILE = DATA_DIR / "state.json"

BACKEND_HOST = os.getenv("BACKEND_HOST", "127.0.0.1")
BACKEND_PORT = int(os.getenv("BACKEND_PORT", "8002"))
FRONTEND_PORT = int(os.getenv("FRONTEND_PORT", "5180"))


def cors_origins() -> list[str]:
    """默认只放行本机前端端口；可用 CORS_ORIGINS=a,b 覆盖。"""
    raw = os.getenv("CORS_ORIGINS", "").strip()
    if raw:
        return [o.strip() for o in raw.split(",") if o.strip()]
    return [
        f"http://localhost:{FRONTEND_PORT}",
        f"http://127.0.0.1:{FRONTEND_PORT}",
    ]
