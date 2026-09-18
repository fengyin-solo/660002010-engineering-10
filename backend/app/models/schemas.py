from pydantic import BaseModel
from typing import List, Union


class ModbusRegister(BaseModel):
    address: int
    name: str
    type: str
    value: Union[float, bool]
    unit: str


class Device(BaseModel):
    id: str
    name: str
    ip: str
    port: int
    slave_id: int
    online: bool
    registers: List[ModbusRegister] = []
