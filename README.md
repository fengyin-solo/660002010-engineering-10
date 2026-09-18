# solo-6600020: Modbus 工业协议数据采集监控大屏

## 技术栈
- Frontend: Vue 3 + TypeScript + Vite + Pinia + Tailwind CSS + ECharts
- Backend: Python FastAPI + pymodbus

## 核心特性
1. **Modbus RTU/TCP 寄存器实时读取**：pymodbus 连接工业设备
2. **时序曲线 ECharts 绘制**：实时趋势图，多寄存器对比
3. **阈值告警 WebSocket 推送**：温度/压力超限自动告警
4. **设备拓扑 SVG 图**：可视化设备布局与在线状态
5. **采集任务调度**：可调轮询间隔，设备启停控制

## 本地开发：一条命令启动大屏

前置要求：Node.js 18+、Python 3.9+（含 venv）、curl。

```bash
cp .env.example .env   # 可选：换机器/端口时只改这个文件，默认配置可直接用
./scripts/dev.sh       # 或 make dev
```

脚本会按顺序执行，每一步都有编号和 ✓/✗ 输出，任一步失败立即中止并打印原因：

1. 停止上次运行残留的前后端进程（基于 `.run/*.pid`，整进程组清理）
2. 加载 `.env`（不存在则用 `.env.example` 默认值）
3. **依赖检查**：版本检查；后端依赖装进 `backend/.venv`（隔离不污染系统 Python），前端装进 `node_modules`；缺失自动安装，装完做真实 import / 模块解析校验
4. **构建校验**：先删掉旧的 `dist`、`__pycache__`；后端 `compileall` + `import app.main`，前端 `vue-tsc && vite build`；校验完立即删除构建产物，避免旧产物被当成新结果
5. **端口预检**：端口被占用直接报错并给出占用信息，而不是悄悄换端口
6. 启动后端 (uvicorn) 与前端 (vite)，日志写入 `.run/logs/`
7. **健康检查**：后端 `/api/health` → 前端首页 → 经 vite 代理访问后端接口，任一失败打印对应日志并回滚本次启动的进程

启动成功后：

- 大屏：http://localhost:5180/
- 后端：http://localhost:8002/api/modbus/devices
- `Ctrl-C` 停止全部服务（或另开终端执行 `./scripts/dev.sh down`）

### 子命令

| 命令 | 作用 |
| --- | --- |
| `./scripts/dev.sh` / `up` | 检查 + 构建校验 + 启动（前台） |
| `./scripts/dev.sh check` | 只做依赖检查与构建校验（排错/CI 用） |
| `./scripts/dev.sh reset-data` | **一键恢复示例数据**到初始状态 |
| `./scripts/dev.sh down` | 停止服务 |
| `./scripts/dev.sh clean` | 清理构建产物与缓存（保留依赖和数据） |
| `./scripts/dev.sh nuke` | 连依赖、工作数据一起删除（保留 seed 模板） |

## 端口与接口地址配置

不再写死在代码里，统一由根目录 `.env` 控制（见 `.env.example`）：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `BACKEND_PORT` | `8002` | 后端监听端口 |
| `FRONTEND_PORT` | `5180` | 前端 dev server 端口（strictPort，占用即报错） |
| `VITE_API_PROXY_TARGET` | `http://localhost:8002` | 前端 `/api` 代理目标，需与后端端口一致 |
| `BROWSER_OPEN` | `false` | 启动时是否自动打开浏览器 |

## 示例数据与恢复

- 初始模板：`backend/seed/devices.seed.json`（只读，纳入版本管理）
- 当前工作数据：`backend/data/devices.json`（运行时自动从 seed 生成，已在 `.gitignore`）
- 大屏设备数据以后端文件为**唯一事实来源**，页面加载/刷新都会重新请求 `/api/modbus/devices`

恢复方式二选一：

```bash
./scripts/dev.sh reset-data     # 命令行一键恢复
```

或点击大屏侧栏「↺ 恢复示例数据」按钮（会停止采集、清空告警与趋势、重新拉取数据）。

恢复后刷新页面，大屏展示与 `seed/devices.seed.json` 完全一致——后端每次实时读文件，不缓存旧数据。

## 手工启动（等价于脚本内的步骤，一般不需要）

```bash
# 后端
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m uvicorn app.main:app --reload --port 8002

# 前端
cd frontend
npm install
npm run dev
```
