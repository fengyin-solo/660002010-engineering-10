import axios from 'axios'

// 接口地址集中配置：默认 /api（经 Vite 代理到后端），换机器/部署只需改根目录 .env 里的 VITE_API_BASE_URL
const client = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? '/api',
  timeout: 5000,
})

export interface ApiRegister {
  address: number
  name: string
  type: 'coil' | 'discrete' | 'holding' | 'input'
  value: number | boolean
  unit: string
  updated_at?: number
}

export interface ApiDevice {
  id: string
  name: string
  ip: string
  port: number
  slave_id: number
  online: boolean
  registers: ApiRegister[]
}

export interface ApiAlarm {
  id: string
  device_id: string
  register: string
  message: string
  level: 'info' | 'warning' | 'critical'
  timestamp: number
  acknowledged: boolean
}

export interface ApiSnapshot {
  devices: ApiDevice[]
  alarms: ApiAlarm[]
}

export const api = {
  snapshot: () => client.get<ApiSnapshot>('/snapshot').then(r => r.data),
  poll: () => client.post<ApiSnapshot>('/poll').then(r => r.data),
  toggleDevice: (id: string) => client.post<ApiSnapshot>(`/devices/${id}/toggle`).then(r => r.data),
  ackAlarm: (id: string) => client.post<ApiSnapshot>(`/alarms/${id}/ack`).then(r => r.data),
  resetDemo: () => client.post<ApiSnapshot>('/demo/reset').then(r => r.data),
}
