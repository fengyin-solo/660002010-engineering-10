"""Modbus 设备数据服务。

数据以本地 JSON 文件为事实来源：
- seed/devices.seed.json 初始示例数据（只读模板）
- data/devices.json    当前工作数据，可被 reset_sample_data() 一键还原

前端大屏直接消费这里的数据，因此 reset 之后再刷新页面，
看到的一定与 seed 完全一致。
"""
import json
import shutil
import threading
from pathlib import Path
from typing import Any, Dict, List

from app.config import DATA_FILE, SEED_FILE

_lock = threading.Lock()


def _load_json(path: Path) -> List[Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"{path} 内容格式错误：期望设备列表")
    return data


def _ensure_data_file() -> None:
    """首次运行或工作数据丢失时，从 seed 初始化。"""
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not DATA_FILE.exists():
        shutil.copyfile(SEED_FILE, DATA_FILE)


def get_device_status() -> List[Dict[str, Any]]:
    with _lock:
        _ensure_data_file()
        return _load_json(DATA_FILE)


def reset_sample_data() -> List[Dict[str, Any]]:
    """用 seed 覆盖当前工作数据，返回还原后的设备列表。"""
    with _lock:
        if not SEED_FILE.exists():
            raise FileNotFoundError(f"初始数据模板不存在：{SEED_FILE}")
        DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SEED_FILE, DATA_FILE)
        return _load_json(DATA_FILE)


def read_registers(device_id: str, address: int, count: int) -> Dict[str, Any]:
    """读取指定设备从 address 起的 count 个保持寄存器值。

    本地开发用文件中的示例数据；生产环境替换为 pymodbus 调用即可：
        from pymodbus.client import ModbusTcpClient
        client = ModbusTcpClient(host, port=port)
        result = client.read_holding_registers(address, count, slave=slave_id)
    """
    for dev in get_device_status():
        if dev["id"] != device_id:
            continue
        regs = sorted(
            (r for r in dev.get("registers", []) if r["address"] >= address),
            key=lambda r: r["address"],
        )
        values = [r["value"] for r in regs[:count]]
        return {"device_id": device_id, "address": address, "values": values}
    return {"device_id": device_id, "address": address, "values": [], "error": "device not found"}


def write_register(device_id: str, address: int, value: float) -> Dict[str, Any]:
    """把单个寄存器值写入工作数据文件（示例数据持久化，便于演示写入/恢复）。"""
    with _lock:
        _ensure_data_file()
        devices = _load_json(DATA_FILE)
        for dev in devices:
            if dev["id"] != device_id:
                continue
            for reg in dev.get("registers", []):
                if reg["address"] == address:
                    reg["value"] = value
                    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
                    with open(DATA_FILE, "w", encoding="utf-8") as f:
                        json.dump(devices, f, ensure_ascii=False, indent=2)
                    return {"device_id": device_id, "address": address, "value": value, "status": "written"}
        return {"device_id": device_id, "address": address, "value": value, "status": "device or register not found"}
