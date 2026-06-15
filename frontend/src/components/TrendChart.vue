<template>
  <v-chart v-if="chartOption" :option="chartOption" class="h-56" autoresize />
  <div v-else class="h-56 flex items-center justify-center text-gray-600 text-sm">开始采集后显示趋势</div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { LineChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components'
import VChart from 'vue-echarts'
import { useModbusStore } from '../store/modbus'
import type { EChartsOption } from 'echarts'

use([CanvasRenderer, LineChart, GridComponent, TooltipComponent, LegendComponent])

const store = useModbusStore()

const chartOption = computed<EChartsOption | null>(() => {
  const dev = store.selectedDevice
  if (!dev) return null
  const colors = ['#f97316', '#22d3ee', '#a78bfa', '#34d399']
  const series: any[] = []
  dev.registers.forEach((reg, i) => {
    const key = `${dev.id}_${reg.address}`
    const hd = store.historyData[key]
    if (!hd || !hd.values.length) return
    series.push({
      name: reg.name,
      type: 'line',
      showSymbol: false,
      smooth: true,
      lineStyle: { color: colors[i % colors.length], width: 2 },
      data: hd.time.map((t, j) => [t, hd.values[j]])
    })
  })
  if (!series.length) return null
  return {
    tooltip: { trigger: 'axis' },
    legend: { textStyle: { color: '#999' }, top: 0 },
    grid: { left: 50, right: 20, top: 30, bottom: 25 },
    xAxis: { type: 'value', axisLabel: { color: '#666', formatter: (v: number) => new Date(v).toLocaleTimeString() }, splitLine: { lineStyle: { color: '#1f2937' } } },
    yAxis: { type: 'value', axisLabel: { color: '#666' }, splitLine: { lineStyle: { color: '#1f2937' } } },
    series
  }
})
</script>
