"""Modbus 采集与大屏状态服务（本地演示模式）。

数据全部由 state_store 持久化：seed.json 为示例初始值，state.json 为当前值。
生产环境把 _simulate_one_tick 中的模拟读数替换为 pymodbus 真实读取即可。
"""
import random
import time
from typing import Any, Dict, Optional

from app.services import state_store

_TEMP_WARN = 28.0
_TEMP_CRITICAL = 30.0
_ALARM_LIMIT = 50


def snapshot() -> Dict[str, Any]:
    """大屏一次性拉取的完整状态：设备/寄存器 + 告警。"""
    return state_store.load()


def reset_demo() -> Dict[str, Any]:
    """一键恢复示例数据，返回恢复后的完整状态。"""
    return state_store.reset_to_seed()


def toggle_device(device_id: str) -> Optional[Dict[str, Any]]:
    data = state_store.load()
    for dev in data["devices"]:
        if dev["id"] == device_id:
            dev["online"] = not dev["online"]
            state_store.save(data)
            return data
    return None


def acknowledge_alarm(alarm_id: str) -> Optional[Dict[str, Any]]:
    data = state_store.load()
    for alarm in data["alarms"]:
        if alarm["id"] == alarm_id:
            alarm["acknowledged"] = True
            state_store.save(data)
            return data
    return None


def poll_tick() -> Dict[str, Any]:
    """模拟一轮 Modbus 轮询：在线设备的数值寄存器叠加 ±1% 噪声并落盘。

    生产环境此处替换为：
        from pymodbus.client import ModbusTcpClient
        client = ModbusTcpClient(dev["ip"], port=dev["port"])
        result = client.read_holding_registers(address, count, slave=dev["slave_id"])
    """
    data = state_store.load()
    now_ms = int(time.time() * 1000)
    for dev in data["devices"]:
        if not dev["online"]:
            continue
        for reg in dev["registers"]:
            value = reg.get("value")
            if not isinstance(value, (int, float)):
                continue
            noise = (random.random() - 0.5) * value * 0.02
            reg["value"] = round(value + noise, 2)
            reg["updated_at"] = now_ms
            if reg["name"] == "温度" and reg["value"] > _TEMP_WARN:
                level = "critical" if reg["value"] > _TEMP_CRITICAL else "warning"
                data["alarms"].insert(0, {
                    "id": f"a_{now_ms}_{random.randint(0, 999999):06d}",
                    "device_id": dev["id"],
                    "register": reg["name"],
                    "message": f'{dev["name"]} {reg["name"]}超限: {reg["value"]}{reg["unit"]}',
                    "level": level,
                    "timestamp": now_ms,
                    "acknowledged": False,
                })
    data["alarms"] = data["alarms"][:_ALARM_LIMIT]
    state_store.save(data)
    return data


def read_registers(device_id: str, address: int, count: int) -> Dict[str, Any]:
    """单寄存器读取接口（兼容保留）；无真实设备时返回演示随机值。"""
    values = [round(random.uniform(0, 100), 2) for _ in range(count)]
    return {"device_id": device_id, "address": address, "values": values}
