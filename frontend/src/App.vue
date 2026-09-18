<template>
  <div class="flex h-screen">
    <!-- Sidebar -->
    <div class="w-64 bg-gray-900 p-4 flex flex-col gap-3 border-r border-gray-800 overflow-y-auto">
      <h1 class="text-lg font-bold text-orange-400">Modbus 工业监控</h1>
      <div class="flex gap-2">
        <button @click="startPoll" :disabled="store.isPolling" class="flex-1 bg-green-700 py-1.5 rounded text-xs hover:bg-green-600 disabled:opacity-50">
          {{ store.isPolling ? '采集中...' : '开始采集' }}
        </button>
        <button @click="stopPoll" :disabled="!store.isPolling" class="flex-1 bg-red-700 py-1.5 rounded text-xs hover:bg-red-600 disabled:opacity-50">
          停止
        </button>
      </div>
      <div>
        <label class="text-gray-400 text-xs">轮询间隔: {{ store.pollInterval }}ms</label>
        <input type="range" v-model.number="store.pollInterval" min="200" max="5000" step="100" class="w-full" />
      </div>

      <h3 class="text-gray-400 text-xs mt-2">设备列表</h3>
      <div v-for="d in store.devices" :key="d.id" @click="store.selectDevice(d.id)"
        class="bg-gray-800 rounded p-2 cursor-pointer text-sm"
        :class="store.selectedDevice?.id === d.id ? 'ring-1 ring-orange-500' : ''">
        <div class="flex justify-between">
          <span>{{ d.name }}</span>
          <span class="w-2 h-2 rounded-full mt-1.5" :class="d.online ? 'bg-green-500' : 'bg-red-500'"></span>
        </div>
        <div class="flex justify-between items-center">
          <span class="text-xs text-gray-500">{{ d.ip }}:{{ d.port }} [{{ d.slaveId }}]</span>
          <button @click.stop="store.toggleDevice(d.id)"
            class="text-[10px] px-1.5 py-0.5 rounded bg-gray-700 hover:bg-gray-600 text-gray-300">
            {{ d.online ? '停用' : '启用' }}
          </button>
        </div>
      </div>

      <div v-if="store.criticalAlarms.length" class="bg-red-900/50 rounded p-2 mt-2">
        <h4 class="text-red-400 text-xs font-bold">⚠ 严重告警 {{ store.criticalAlarms.length }}</h4>
        <div v-for="a in store.criticalAlarms.slice(0, 3)" :key="a.id" class="text-xs text-red-300 mt-1 truncate">
          {{ a.message }}
        </div>
      </div>

      <div class="text-xs text-gray-600 mt-auto">
        在线: {{ store.onlineDevices.length }}/{{ store.devices.length }}
      </div>
    </div>

    <!-- Main Dashboard -->
    <div class="flex-1 flex flex-col gap-3 p-4 overflow-y-auto">
      <!-- 工具栏 -->
      <div class="flex items-center gap-3">
        <button @click="resetDemo" :disabled="store.resetting"
          class="bg-orange-700 hover:bg-orange-600 disabled:opacity-50 text-xs px-3 py-1.5 rounded">
          {{ store.resetting ? '恢复中...' : '↺ 恢复示例数据' }}
        </button>
        <span class="text-[11px] text-gray-500">将全部设备、寄存器和告警重置为初始示例状态</span>
        <div v-if="store.error" class="ml-auto flex items-center gap-2">
          <span class="text-xs text-red-400">{{ store.error }}</span>
          <button @click="store.loadSnapshot()" class="text-xs text-blue-400 hover:underline">重试</button>
        </div>
        <span v-else-if="store.loading" class="ml-auto text-xs text-gray-500">加载中...</span>
      </div>

      <!-- Register Gauges -->
      <div class="grid grid-cols-4 gap-3">
        <template v-for="d in store.devices" :key="d.id">
          <div v-for="r in d.registers" :key="`${d.id}_${r.address}`"
            class="bg-gray-900 rounded-xl p-3">
            <div class="text-xs text-gray-400">{{ d.name }}</div>
            <div class="text-2xl font-bold" :class="d.online ? 'text-orange-400' : 'text-gray-600'">
              {{ typeof r.value === 'number' ? r.value.toFixed(r.value > 100 ? 0 : 1) : r.value ? 'ON' : 'OFF' }}
            </div>
            <div class="text-xs text-gray-500">{{ r.name }} {{ r.unit }}</div>
          </div>
        </template>
      </div>

      <!-- Chart -->
      <div class="bg-gray-900 rounded-xl p-3 flex-1">
        <h3 class="text-sm text-gray-400 mb-2">
          实时趋势 — {{ store.selectedDevice?.name || '选择设备' }}
        </h3>
        <TrendChart />
      </div>

      <!-- Alarm List -->
      <div class="bg-gray-900 rounded-xl p-3 max-h-48 overflow-y-auto">
        <h3 class="text-sm text-gray-400 mb-2">告警记录</h3>
        <div v-if="!store.alarms.length" class="text-xs text-gray-600">暂无告警</div>
        <div v-for="a in store.alarms.slice(0, 10)" :key="a.id"
          class="flex justify-between text-xs bg-gray-800 rounded p-2 mb-1"
          :class="{ 'border-l-4 border-red-500': a.level === 'critical', 'border-l-4 border-yellow-500': a.level === 'warning' }">
          <span>{{ a.message }}</span>
          <div class="flex gap-2">
            <span class="text-gray-500">{{ new Date(a.timestamp).toLocaleTimeString() }}</span>
            <button v-if="!a.acknowledged" @click="store.acknowledgeAlarm(a.id)" class="text-blue-400 hover:underline">确认</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted, onUnmounted, watch } from 'vue'
import { useModbusStore } from './store/modbus'
import TrendChart from './components/TrendChart.vue'

const store = useModbusStore()
let timer: number | null = null

function startPoll() {
  stopPoll()
  store.isPolling = true
  timer = window.setInterval(() => store.pollOnce(), store.pollInterval)
}

function stopPoll() {
  store.isPolling = false
  if (timer) { clearInterval(timer); timer = null }
}

// 恢复示例数据时先停止采集（否则下一拍轮询又会改动刚恢复的值），
// 再由 store 重置后端 state.json、重拉快照、清空本会话曲线
async function resetDemo() {
  stopPoll()
  await store.resetDemoData()
}

// 拖动轮询间隔滑块且正在采集时，按新间隔重启定时器
watch(() => store.pollInterval, () => {
  if (store.isPolling) startPoll()
})

onMounted(() => store.loadSnapshot())
onUnmounted(() => stopPoll())
</script>
