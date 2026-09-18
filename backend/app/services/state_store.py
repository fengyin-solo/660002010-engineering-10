"""文件态数据存储：seed.json 为出厂示例数据，state.json 为当前运行状态。

所有写操作走 tmp + os.replace 原子落盘，进程中途崩溃也不会留下半个 JSON，
重新执行/重启进程时读到的一定是上一次完整写入的结果。
"""
import json
import os
import threading
from typing import Any, Dict

from app import config

# 可重入锁：load() 缺失状态时会在持锁状态下调用 reset_to_seed()
_lock = threading.RLock()


def _read_json(path) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _write_json_atomic(path, data: Dict[str, Any]) -> None:
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def reset_to_seed() -> Dict[str, Any]:
    """用出厂示例数据覆盖当前状态，并返回新状态。"""
    with _lock:
        config.DATA_DIR.mkdir(parents=True, exist_ok=True)
        data = _read_json(config.SEED_FILE)
        _write_json_atomic(config.STATE_FILE, data)
        return data


def load() -> Dict[str, Any]:
    """加载当前状态；state 缺失或损坏（如上次只写了一半）时回退到示例数据。"""
    with _lock:
        if config.STATE_FILE.exists():
            try:
                return _read_json(config.STATE_FILE)
            except (json.JSONDecodeError, OSError):
                pass
        return reset_to_seed()


def save(data: Dict[str, Any]) -> None:
    with _lock:
        config.DATA_DIR.mkdir(parents=True, exist_ok=True)
        _write_json_atomic(config.STATE_FILE, data)
