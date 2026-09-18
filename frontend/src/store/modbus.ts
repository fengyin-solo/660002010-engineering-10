import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import type { Device, Alarm } from '../types'
import { api, type ApiSnapshot } from '../api/client'

export const useModbusStore = defineStore('modbus', () => {
  const devices = ref<Device[]>([])
  const alarms = ref<Alarm[]>([])
  // 趋势曲线只属于当前浏览器会话：刷新后从空开始累积，恢复示例数据时同步清空，
  // 保证大屏展示的数值始终与后端当前状态一致，不会混入上一次的曲线。
  const historyData = ref<Record<string, { time: number[]; values: number[] }>>({})
  const isPolling = ref(false)
  const pollInterval = ref(1000)
  const selectedDeviceId = ref<string | null>(null)
  const loading = ref(false)
  const resetting = ref(false)
  const error = ref('')

  const selectedDevice = computed<Device | null>(
    () => devices.value.find(d => d.id === selectedDeviceId.value) ?? devices.value[0] ?? null
  )
  const criticalAlarms = computed(() => alarms.value.filter(a => a.level === 'critical' && !a.acknowledged))
  const onlineDevices = computed(() => devices.value.filter(d => d.online))

  function applySnapshot(snap: ApiSnapshot) {
    devices.value = snap.devices.map(d => ({
      id: d.id,
      name: d.name,
      ip: d.ip,
      port: d.port,
      slaveId: d.slave_id,
      online: d.online,
      registers: d.registers.map(r => ({
        address: r.address,
        name: r.name,
        type: r.type,
        value: r.value,
        unit: r.unit,
        updatedAt: r.updated_at ?? Date.now(),
      })),
    }))
    alarms.value = snap.alarms.map(a => ({
      id: a.id,
      deviceId: a.device_id,
      register: a.register,
      message: a.message,
      level: a.level,
      timestamp: a.timestamp,
      acknowledged: a.acknowledged,
    }))
    if (!selectedDeviceId.value && devices.value.length) selectedDeviceId.value = devices.value[0].id
  }

  function clearHistory() {
    historyData.value = {}
  }

  async function loadSnapshot() {
    loading.value = true
    error.value = ''
    try {
      applySnapshot(await api.snapshot())
    } catch (e: any) {
      error.value = `无法连接后端接口: ${e?.message ?? e}`
    } finally {
      loading.value = false
    }
  }

  async function pollOnce() {
    error.value = ''
    try {
      const snap = await api.poll()
      applySnapshot(snap)
      const now = Date.now()
      for (const dev of devices.value) {
        if (!dev.online) continue
        for (const reg of dev.registers) {
          if (typeof reg.value !== 'number') continue
          const key = `${dev.id}_${reg.address}`
          if (!historyData.value[key]) historyData.value[key] = { time: [], values: [] }
          historyData.value[key].time.push(now)
          historyData.value[key].values.push(reg.value)
          if (historyData.value[key].time.length > 100) {
            historyData.value[key].time.shift()
            historyData.value[key].values.shift()
          }
        }
      }
    } catch (e: any) {
      error.value = `采集失败: ${e?.message ?? e}`
    }
  }

  async function toggleDevice(id: string) {
    try {
      applySnapshot(await api.toggleDevice(id))
    } catch (e: any) {
      error.value = `设备启停失败: ${e?.message ?? e}`
    }
  }

  async function acknowledgeAlarm(id: string) {
    try {
      applySnapshot(await api.ackAlarm(id))
    } catch (e: any) {
      error.value = `告警确认失败: ${e?.message ?? e}`
    }
  }

  /** 一键恢复示例数据：后端重置 state.json，前端重拉并清空本会话曲线。 */
  async function resetDemoData() {
    resetting.value = true
    error.value = ''
    try {
      applySnapshot(await api.resetDemo())
      clearHistory()
    } catch (e: any) {
      error.value = `恢复示例数据失败: ${e?.message ?? e}`
    } finally {
      resetting.value = false
    }
  }

  function selectDevice(id: string) {
    selectedDeviceId.value = id
  }

  return {
    devices, alarms, historyData, isPolling, pollInterval, selectedDevice,
    loading, resetting, error,
    criticalAlarms, onlineDevices,
    loadSnapshot, pollOnce, toggleDevice, acknowledgeAlarm, resetDemoData, selectDevice, clearHistory,
  }
})
