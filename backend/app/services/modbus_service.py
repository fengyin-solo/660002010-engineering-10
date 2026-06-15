"""Modbus service with mock data (replace with pymodbus for production)."""
import random
from typing import List, Dict, Any

MOCK_DEVICES = [
    {"id": "dev1", "name": "温湿度传感器-A区", "ip": "192.168.1.101", "port": 502, "slave_id": 1, "online": True},
    {"id": "dev2", "name": "压力变送器-B区", "ip": "192.168.1.102", "port": 502, "slave_id": 2, "online": True},
    {"id": "dev3", "name": "电机控制器-C区", "ip": "192.168.1.103", "port": 502, "slave_id": 3, "online": False},
]

def get_device_status() -> List[Dict[str, Any]]:
    return MOCK_DEVICES

def read_registers(device_id: str, address: int, count: int) -> Dict[str, Any]:
    """Read registers via pymodbus (mock implementation)."""
    # In production: from pymodbus.client import ModbusTcpClient
    # client = ModbusTcpClient(host, port=port)
    # result = client.read_holding_registers(address, count, slave=slave_id)
    values = [round(random.uniform(0, 100), 2) for _ in range(count)]
    return {"device_id": device_id, "address": address, "values": values}
