from fastapi import APIRouter, HTTPException

from app.services import modbus_service

router = APIRouter()


@router.get("/snapshot")
def get_snapshot():
    """大屏初始化/刷新时一次性拉取全部设备、寄存器与告警。"""
    return modbus_service.snapshot()


@router.post("/poll")
def poll_once():
    """触发一轮采集（前端按轮询间隔调用），返回最新完整状态。"""
    return modbus_service.poll_tick()


@router.post("/devices/{device_id}/toggle")
def toggle_device(device_id: str):
    data = modbus_service.toggle_device(device_id)
    if data is None:
        raise HTTPException(status_code=404, detail=f"设备不存在: {device_id}")
    return data


@router.post("/alarms/{alarm_id}/ack")
def acknowledge_alarm(alarm_id: str):
    data = modbus_service.acknowledge_alarm(alarm_id)
    if data is None:
        raise HTTPException(status_code=404, detail=f"告警不存在: {alarm_id}")
    return data


@router.post("/demo/reset")
def reset_demo():
    """一键恢复示例数据到初始状态。"""
    return modbus_service.reset_demo()


# ---------------------------------------------------------------------------
# 以下为原有 Modbus 读写接口，保留兼容
# ---------------------------------------------------------------------------
@router.get("/modbus/devices")
def list_devices():
    return modbus_service.snapshot()["devices"]


@router.get("/modbus/read/{device_id}/{address}/{count}")
def read_holding(device_id: str, address: int, count: int = 1):
    return modbus_service.read_registers(device_id, address, count)


@router.post("/modbus/write/{device_id}/{address}")
def write_register(device_id: str, address: int, value: int):
    return {"device_id": device_id, "address": address, "value": value, "status": "written"}
