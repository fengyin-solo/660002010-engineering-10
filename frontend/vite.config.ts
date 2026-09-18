import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'

// 端口与后端地址全部来自根目录 .env（dev.sh 会注入环境变量），换机只改 .env
export default defineConfig(({ mode }) => {
  const env = { ...loadEnv(mode, process.cwd(), ''), ...process.env }
  const frontendPort = Number(env.FRONTEND_PORT ?? 5180)
  const backendPort = Number(env.BACKEND_PORT ?? 8002)
  const backendHost = String(env.BACKEND_HOST ?? '127.0.0.1')

  return {
    plugins: [vue()],
    server: {
      host: '127.0.0.1',
      port: frontendPort,
      open: false,
      proxy: {
        '/api': `http://${backendHost}:${backendPort}`,
      },
    },
  }
})
