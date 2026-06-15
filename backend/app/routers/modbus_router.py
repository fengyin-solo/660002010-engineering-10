from fastapi import APIRouter
from app.services.modbus_service import read_registers, get_device_status

router = APIRouter()

@router.get("/modbus/devices")
def list_devices():
    return get_device_status()

@router.get("/modbus/read/{device_id}/{address}/{count}")
def read_holding(device_id: str, address: int, count: int = 1):
    """Read holding registers from a Modbus device."""
    return read_registers(device_id, address, count)

@router.post("/modbus/write/{device_id}/{address}")
def write_register(device_id: str, address: int, value: int):
    return {"device_id": device_id, "address": address, "value": value, "status": "written"}
