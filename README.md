# solo-6600020: Modbus 工业协议数据采集监控大屏

## 技术栈
- Frontend: Vue 3 + TypeScript + Vite + Pinia + Tailwind CSS + ECharts
- Backend: Python FastAPI + pymodbus

## 核心特性
1. **Modbus RTU/TCP 寄存器实时读取**：pymodbus 连接工业设备（当前为本地演示数据）
2. **时序曲线 ECharts 绘制**：实时趋势图，多寄存器对比
3. **阈值告警**：温度超限自动产生 warning/critical 告警
4. **设备列表/在线状态**：可视化设备状态，可启停设备
5. **采集任务调度**：可调轮询间隔，开始/停止控制
6. **一键恢复示例数据**：后端持久化状态可随时回到出厂快照，刷新页面保持一致

## 本地一条命令跑起来

前置要求：`python3` (3.10+)、`node` (18+)、`npm`、`curl`。

```bash
./scripts/dev.sh
```

脚本会按顺序执行，每一步都有编号日志，任何一步失败立即停止并指出原因和日志位置：

1. 检查 python/node/npm/curl 与版本
2. 停止上一次残留的前后端进程，确认端口空闲
3. 清理上一次的中间产物（`dist`、缓存、日志；**不删**依赖和数据）
4. 检查/安装后端依赖（自动创建 `.venv`；系统缺 `python3-venv` 时自动用 get-pip.py 引导）
5. 检查/安装前端依赖（缺 `node_modules` 时自动 `npm install`）
6. 构建校验：后端 `import app.main` + 前端 `vue-tsc && vite build`
7. 启动后端并对**新进程**做 `/api/health` 健康检查
8. 启动前端，并验证 `/api` 代理端到端联通

启动成功后访问 http://127.0.0.1:5180/ ，`Ctrl-C` 一起停止前后端。

### 换机器 / 改端口
只改根目录 `.env`（首次运行会自动从 `.env.example` 生成）：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `BACKEND_HOST` / `BACKEND_PORT` | `127.0.0.1` / `8002` | 后端监听地址端口，也是 Vite 代理目标 |
| `FRONTEND_PORT` | `5180` | 前端 Vite 端口 |
| `VITE_API_BASE_URL` | `/api` | 前端接口前缀 |
| `CORS_ORIGINS` | 空 | 额外放行的跨域来源，逗号分隔 |
| `DATA_DIR` | `backend/data` | 示例与运行态数据目录 |

### 其他命令

```bash
./scripts/dev.sh setup       # 只做依赖检查 + 构建校验（CI/想先验证环境时用）
./scripts/dev.sh stop        # 停止后台运行的前后端
./scripts/dev.sh clean       # 清理中间产物（保留依赖和数据）
./scripts/dev.sh reset-data  # CLI 恢复示例数据
```

运行日志与 pid 位于 `.run/`：`backend.log`、`frontend.log`、`pip-install.log`、`npm-install.log`、`frontend-build.log`。

## 示例数据与刷新一致性

- `backend/data/seed.json`：出厂示例数据（纳入 git）
- `backend/data/state.json`：当前运行状态（原子写入，git 忽略；损坏/缺失时自动回退 seed）
- 页面点 **↺ 恢复示例数据**（或 `./scripts/dev.sh reset-data`）即可回到初始状态
- 页面刷新时前端从后端 `/api/snapshot` 重新拉取，大屏展示与 `state.json` 严格一致；
  浏览器内的实时趋势曲线只属于当前会话，恢复数据时会一并清空

## 手工方式（不推荐，仅备查）
```bash
# 后端
cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8002
# 前端
cd frontend && npm install && npm run dev
```
