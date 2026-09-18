import axios from 'axios'
import type { Device, ModbusRegister } from './types'

// 走相对路径，由 vite dev server 代理到后端（代理目标来自环境变量），不写死主机/端口
const http = axios.create({ baseURL: '/api', timeout: 8000 })

interface ApiRegister {
  address: number
  name: string
  type: ModbusRegister['type']
  value: number | boolean
  unit: string
}

interface ApiDevice {
  id: string
  name: string
  ip: string
  port: number
  slave_id: number
  online: boolean
  registers: ApiRegister[]
}

function normalizeDevice(d: ApiDevice): Device {
  return {
    id: d.id,
    name: d.name,
    ip: d.ip,
    port: d.port,
    slaveId: d.slave_id,
    online: d.online,
    registers: (d.registers ?? []).map((r) => ({
      address: r.address,
      name: r.name,
      type: r.type,
      value: r.value,
      unit: r.unit,
      updatedAt: 0,
    })),
  }
}

export async function fetchDevices(): Promise<Device[]> {
  const res = await http.get<ApiDevice[]>('/modbus/devices')
  return res.data.map(normalizeDevice)
}

export async function resetSampleData(): Promise<Device[]> {
  const res = await http.post<{ status: string; devices: ApiDevice[] }>('/modbus/reset')
  return res.data.devices.map(normalizeDevice)
}
