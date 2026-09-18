/// <reference types="vite/client" />
declare module '*.vue' { import type { DefineComponent } from 'vue'; const component: DefineComponent<{}, {}, any>; export default component }

interface ImportMetaEnv {
  /** 后端接口前缀，默认 /api（由 dev 代理转发） */
  readonly VITE_API_BASE_URL: string
  /** Vite 开发服务器端口（由 dev.sh 注入） */
  readonly VITE_PORT?: string
}
interface ImportMeta { readonly env: ImportMetaEnv }
