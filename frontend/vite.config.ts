import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// dev.sh 会把仓库根 .env 中的变量导出到进程环境；直接执行 npm run dev 时使用下面的缺省值。
// 端口、后端地址均不写死，换机器只需改环境变量，无需改代码。
declare const process: { env: Record<string, string | undefined> }

export default defineConfig({
  plugins: [vue()],
  server: {
    host: '0.0.0.0', // 与容器/局域网端口映射兼容
    port: Number(process.env.FRONTEND_PORT ?? 5180),
    strictPort: true, // 端口被占用直接报错，由编排脚本统一预检，避免悄悄换端口
    open: process.env.BROWSER_OPEN === 'true',
    proxy: {
      '/api': process.env.VITE_API_PROXY_TARGET ?? `http://localhost:${process.env.BACKEND_PORT ?? 8002}`,
    },
  },
})
