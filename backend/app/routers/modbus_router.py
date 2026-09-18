from fastapi import APIRouter
from pydantic import BaseModel
from app.services import modbus_service

router = APIRouter()


class WriteValue(BaseModel):
    value: float


@router.get("/modbus/devices")
def list_devices():
    """大屏设备数据的事实来源，页面加载/刷新时调用。"""
    return modbus_service.get_device_status()


@router.get("/modbus/read/{device_id}/{address}/{count}")
def read_holding(device_id: str, address: int, count: int = 1):
    """Read holding registers from a Modbus device."""
    return modbus_service.read_registers(device_id, address, count)


@router.post("/modbus/write/{device_id}/{address}")
def write_register(device_id: str, address: int, body: WriteValue):
    return modbus_service.write_register(device_id, address, body.value)


@router.post("/modbus/reset")
def reset_sample_data():
    """一键恢复示例数据到初始状态。"""
    return {"status": "reset", "devices": modbus_service.reset_sample_data()}
