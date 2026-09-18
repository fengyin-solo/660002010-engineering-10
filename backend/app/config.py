"""运行期配置：所有机器相关参数均来自环境变量，不写死。"""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# 服务端口（uvicorn --port 由启动脚本传入，这里仅用于健康检查等场景）
BACKEND_PORT = int(os.getenv("BACKEND_PORT", "8002"))

# 示例数据：seed 是初始模板，data 是当前工作数据
SEED_FILE = BASE_DIR / "seed" / "devices.seed.json"
DATA_FILE = BASE_DIR / "data" / "devices.json"
