import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import type { Device, Alarm } from '../types'
import { fetchDevices, resetSampleData } from '../api'

export const useModbusStore = defineStore('modbus', () => {
  const devices = ref<Device[]>([])
  const alarms = ref<Alarm[]>([])
  const historyData = ref<Record<string, { time: number[]; values: number[] }>>({})
  const isPolling = ref(false)
  const pollInterval = ref(1000)
  const selectedDevice = ref<Device | null>(null)
  const loading = ref(false)
  const resetting = ref(false)
  const loadError = ref('')

  const criticalAlarms = computed(() => alarms.value.filter(a => a.level === 'critical' && !a.acknowledged))
  const onlineDevices = computed(() => devices.value.filter(d => d.online))

  /** 设备数据以后端文件为事实来源，页面加载和刷新都重新拉取。 */
  async function loadDevices(selectFirst = true) {
    loading.value = true
    loadError.value = ''
    try {
      const list = await fetchDevices()
      devices.value = list
      const stillExists = list.some(d => d.id === selectedDevice.value?.id)
      if (selectFirst || !stillExists) selectedDevice.value = list[0] ?? null
    } catch (e: any) {
      loadError.value = e?.response
        ? `后端接口异常 (${e.response.status})，请确认后端已启动`
        : '无法连接后端，请检查后端进程和代理配置'
      throw e
    } finally {
      loading.value = false
    }
  }

  /** 一键恢复示例数据：后端用 seed 覆盖工作数据，前端清空告警/趋势后重新拉取。 */
  async function resetData() {
    resetting.value = true
    loadError.value = ''
    try {
      const list = await resetSampleData()
      devices.value = list
      selectedDevice.value = list[0] ?? null
      alarms.value = []
      historyData.value = {}
      return list
    } catch (e: any) {
      loadError.value = '恢复示例数据失败：' + (e?.message ?? '未知错误')
      throw e
    } finally {
      resetting.value = false
    }
  }

  function simulatePoll() {
    for (const dev of devices.value) {
      if (!dev.online) continue
      for (const reg of dev.registers) {
        if (typeof reg.value === 'number') {
          const noise = (Math.random() - 0.5) * reg.value * 0.02
          reg.value = Math.round((reg.value + noise) * 100) / 100
          reg.updatedAt = Date.now()
          const key = `${dev.id}_${reg.address}`
          if (!historyData.value[key]) historyData.value[key] = { time: [], values: [] }
          historyData.value[key].time.push(Date.now())
          historyData.value[key].values.push(reg.value)
          if (historyData.value[key].time.length > 100) {
            historyData.value[key].time.shift()
            historyData.value[key].values.shift()
          }
          // Check thresholds
          if (reg.name === '温度' && reg.value > 28) {
            alarms.value.unshift({
              id: `a_${Date.now()}`, deviceId: dev.id, register: reg.name,
              message: `${dev.name} ${reg.name}超限: ${reg.value}${reg.unit}`,
              level: reg.value > 30 ? 'critical' : 'warning',
              timestamp: Date.now(), acknowledged: false
            })
          }
        }
      }
    }
    if (alarms.value.length > 50) alarms.value = alarms.value.slice(0, 50)
  }

  function acknowledgeAlarm(id: string) {
    const a = alarms.value.find(a => a.id === id)
    if (a) a.acknowledged = true
  }

  function toggleDevice(id: string) {
    const d = devices.value.find(d => d.id === id)
    if (d) d.online = !d.online
  }

  return {
    devices, alarms, historyData, isPolling, pollInterval, selectedDevice,
    loading, resetting, loadError,
    criticalAlarms, onlineDevices,
    loadDevices, resetData, simulatePoll, acknowledgeAlarm, toggleDevice
  }
})
