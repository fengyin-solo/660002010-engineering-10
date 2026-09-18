#!/usr/bin/env bash
#
# 监控大屏一键编排脚本：环境检查 → 清残留 → 依赖检查/安装 → 构建校验 → 起后端 → 起前端
#
# 用法:
#   ./scripts/dev.sh            # 全流程校验通过后，前台同时启动前后端（Ctrl-C 一起停）
#   ./scripts/dev.sh setup      # 只跑 环境检查 + 依赖 + 构建校验，不启动服务
#   ./scripts/dev.sh reset-data # 一键恢复示例数据（等价于大屏上的“恢复示例数据”按钮）
#   ./scripts/dev.sh stop       # 停止正在运行的前后端
#   ./scripts/dev.sh clean      # 清理中间产物（dist/缓存/日志/pid；不删依赖、不动示例与运行数据）
#
# 任何一步失败都会立刻停下，标明是第几步、失败原因，并打印对应日志的最后 30 行。
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT_DIR/.run"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
BACKEND_LOG="$RUN_DIR/backend.log"
FRONTEND_LOG="$RUN_DIR/frontend.log"
BACKEND_PID_FILE="$RUN_DIR/backend.pid"
FRONTEND_PID_FILE="$RUN_DIR/frontend.pid"
PIP_LOG="$RUN_DIR/pip-install.log"
NPM_LOG="$RUN_DIR/npm-install.log"

if [[ -t 1 ]]; then
  C_BLUE=$'\033[36m'; C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_DIM=""; C_OFF=""
fi

STEP=0
TOTAL_STEPS=8
step() { STEP=$((STEP + 1)); echo; echo "${C_BLUE}[$STEP/$TOTAL_STEPS] $*${C_OFF}"; }
ok()   { echo "${C_GREEN}  ✓ $*${C_OFF}"; }
info() { echo "${C_DIM}  $*${C_OFF}"; }
warn() { echo "${C_YELLOW}  ! $*${C_OFF}"; }

die() {
  echo "${C_RED}  ✗ $*${C_OFF}" >&2
  exit 1
}

# 步骤失败：打印原因，并给出可追查的日志位置
fail_step() {
  local reason="$1"; shift
  echo "${C_RED}  ✗ 第 $STEP/$TOTAL_STEPS 步失败：$reason${C_OFF}" >&2
  for logf in "$@"; do
    if [[ -f "$logf" ]]; then
      echo "${C_RED}  --- 最后 30 行日志: $logf ${C_OFF}" >&2
      tail -n 30 "$logf" >&2
    fi
  done
  echo "${C_RED}  修好问题后重新执行 ./scripts/dev.sh 即可，脚本会自动清理本次残留后从头跑一遍。${C_OFF}" >&2
  exit 1
}

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port\$"
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
  fi
}

wait_http_ok() {
  # $1=url $2=超时秒 $3=必须新存活的pid（只认真正新起的进程，绝不把上次的旧服务当成功）
  local url="$1" timeout_s="$2" pid="$3" i
  for ((i = 0; i < timeout_s; i++)); do
    if kill -0 "$pid" 2>/dev/null && curl -sf -o /dev/null "$url"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

kill_pidfile() {
  local pf="$1" name="$2"
  [[ -f "$pf" ]] || return 0
  local pid
  pid="$(cat "$pf" 2>/dev/null || true)"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 5); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    info "已停止上次的 $name (pid $pid)"
  fi
  rm -f "$pf"
}

# ---------------------------------------------------------------------------
# 配置加载
# ---------------------------------------------------------------------------
load_config() {
  if [[ ! -f "$ROOT_DIR/.env" ]]; then
    cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env" || die "无法创建 .env（请从 .env.example 手动复制）"
    info "未找到 .env，已根据 .env.example 生成，默认后端 8002 / 前端 5180"
  fi
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
  : "${BACKEND_HOST:=127.0.0.1}"
  : "${BACKEND_PORT:=8002}"
  : "${FRONTEND_PORT:=5180}"
  : "${VITE_API_BASE_URL:=/api}"
  export BACKEND_HOST BACKEND_PORT FRONTEND_PORT VITE_API_BASE_URL
  export DATA_DIR="${DATA_DIR:-$BACKEND_DIR/data}"
  export CORS_ORIGINS="${CORS_ORIGINS:-}"
}

# ---------------------------------------------------------------------------
# 步骤实现
# ---------------------------------------------------------------------------
s1_check_runtime() {
  step "检查本地运行环境"
  command -v python3 >/dev/null 2>&1 || fail_step "未找到 python3，请先安装 Python 3.10+"
  command -v node >/dev/null 2>&1 || fail_step "未找到 node，请先安装 Node.js 18+"
  command -v npm >/dev/null 2>&1 || fail_step "未找到 npm，请随 Node.js 一起安装"
  command -v curl >/dev/null 2>&1 || fail_step "未找到 curl，请先安装 curl"
  ok "python3 $(python3 --version 2>&1 | awk '{print $2}') / node $(node --version) / npm $(npm --version)"

  local node_major
  node_major="$(node --version | sed 's/v\([0-9]*\).*/\1/')"
  [[ "$node_major" -ge 18 ]] || fail_step "Node 版本过低（当前 v$node_major），Vite 5 需要 Node.js 18+"
}

s2_stop_stale() {
  step "停止上一次运行残留的前后端进程"
  mkdir -p "$RUN_DIR"
  kill_pidfile "$BACKEND_PID_FILE" "后端"
  kill_pidfile "$FRONTEND_PID_FILE" "前端"
  sleep 1
  if port_in_use "$BACKEND_PORT"; then
    fail_step "端口 $BACKEND_PORT 仍被其他进程占用（本脚本记录的旧进程已清理）。请用 'lsof -i :$BACKEND_PORT' 或 'ss -ltnp' 找到并停掉占用进程，或在 .env 中改 BACKEND_PORT"
  fi
  if port_in_use "$FRONTEND_PORT"; then
    fail_step "端口 $FRONTEND_PORT 仍被其他进程占用。请用 'lsof -i :$FRONTEND_PORT' 或 'ss -ltnp' 处理，或在 .env 中改 FRONTEND_PORT"
  fi
  ok "端口 $BACKEND_PORT(后端) / $FRONTEND_PORT(前端) 均空闲"
}

s3_clean_artifacts() {
  step "清理上一次的中间产物（dist / 缓存 / 日志）"
  rm -rf "$FRONTEND_DIR/dist" "$FRONTEND_DIR/node_modules/.vite"
  find "$BACKEND_DIR" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf "$BACKEND_DIR/.pytest_cache" "$BACKEND_DIR/.mypy_cache"
  : > "$BACKEND_LOG"; : > "$FRONTEND_LOG"
  ok "构建产物与运行日志已清空（node_modules / .venv / data 不受影响）"
}

ensure_venv() {
  local venv_py="$BACKEND_DIR/.venv/bin/python"
  if "$venv_py" -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >/dev/null 2>&1; then
    echo "$venv_py"; return 0
  fi

  info "后端虚拟环境缺失或损坏，重新创建 .venv ..." >&2
  rm -rf "$BACKEND_DIR/.venv"
  if ! python3 -m venv "$BACKEND_DIR/.venv" >>"$PIP_LOG" 2>&1; then
    warn "系统缺少 venv/ensurepip（常见于 Debian/Ubuntu 未装 python3-venv），改用 get-pip.py 引导" >&2
    python3 -m venv --without-pip "$BACKEND_DIR/.venv" >>"$PIP_LOG" 2>&1 \
      || fail_step "创建虚拟环境失败，可尝试先安装系统包 python3-venv" "$PIP_LOG"
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$RUN_DIR/get-pip.py" 2>>"$PIP_LOG" \
      || fail_step "下载 get-pip.py 失败（需要能访问 https://bootstrap.pypa.io）" "$PIP_LOG"
    "$venv_py" "$RUN_DIR/get-pip.py" >>"$PIP_LOG" 2>&1 \
      || fail_step "引导安装 pip 失败" "$PIP_LOG"
  fi
  "$venv_py" -m pip --version >/dev/null 2>&1 || fail_step "虚拟环境中的 pip 不可用" "$PIP_LOG"
  echo "$venv_py"
}

s4_backend_deps() {
  step "检查后端 Python 依赖（FastAPI / uvicorn / pymodbus）"
  mkdir -p "$RUN_DIR"
  VENV_PY="$(ensure_venv)"
  if "$VENV_PY" -c "import fastapi, uvicorn, pymodbus, websockets" >/dev/null 2>&1; then
    ok "后端依赖已就绪 ($( "$VENV_PY" -c 'import fastapi; print(fastapi.__version__)' ))"
    return 0
  fi
  info "依赖不全，执行 pip install -r requirements.txt ..."
  if ! "$VENV_PY" -m pip install -r "$BACKEND_DIR/requirements.txt" >>"$PIP_LOG" 2>&1; then
    fail_step "后端依赖安装失败（网络或包版本问题），详见 pip 日志" "$PIP_LOG"
  fi
  "$VENV_PY" -c "import fastapi, uvicorn, pymodbus, websockets" >/dev/null 2>&1 \
    || fail_step "pip install 报告成功但关键包仍无法导入" "$PIP_LOG"
  ok "后端依赖安装完成"
}

s5_frontend_deps() {
  step "检查前端 Node 依赖（Vue3 / Vite / ECharts）"
  if [[ ! -x "$FRONTEND_DIR/node_modules/.bin/vite" ]]; then
    info "node_modules 缺失或不完整，执行 npm install ..."
    if ! (cd "$FRONTEND_DIR" && npm install --no-audit --no-fund) >"$NPM_LOG" 2>&1; then
      fail_step "前端依赖安装失败（网络或包版本问题），详见 npm 日志" "$NPM_LOG"
    fi
  fi
  [[ -x "$FRONTEND_DIR/node_modules/.bin/vite" ]] || fail_step "npm install 后仍找不到 vite 可执行文件" "$NPM_LOG"
  ok "前端依赖已就绪"
}

s6_build_check() {
  step "构建校验（先验证后端可导入，再跑前端 vue-tsc 类型检查 + vite 打包）"
  if ! (cd "$BACKEND_DIR" && "$VENV_PY" -c "import app.main") >"$RUN_DIR/backend-import.log" 2>&1; then
    fail_step "后端代码导入失败（语法/导入路径问题）" "$RUN_DIR/backend-import.log"
  fi
  ok "后端模块导入通过"

  if ! (cd "$FRONTEND_DIR" && npm run build) >"$RUN_DIR/frontend-build.log" 2>&1; then
    fail_step "前端构建未通过（TypeScript 类型或编译错误），按日志提示修复源码" "$RUN_DIR/frontend-build.log"
  fi
  ok "前端类型检查与生产构建通过（产物在 frontend/dist，仅用于校验，dev 模式不使用）"
}

s7_start_backend() {
  step "启动后端并做新进程健康检查 (http://$BACKEND_HOST:$BACKEND_PORT/api/health)"
  (
    cd "$BACKEND_DIR" || exit 1
    setsid "$VENV_PY" -m uvicorn app.main:app --host "$BACKEND_HOST" --port "$BACKEND_PORT"
  ) >"$BACKEND_LOG" 2>&1 &
  BACKEND_PID=$!
  echo "$BACKEND_PID" > "$BACKEND_PID_FILE"

  if ! wait_http_ok "http://$BACKEND_HOST:$BACKEND_PORT/api/health" 30 "$BACKEND_PID"; then
    fail_step "后端在 30 秒内未通过健康检查（端口冲突/启动报错/数据文件问题）" "$BACKEND_LOG"
  fi
  ok "后端已启动 (pid $BACKEND_PID)"
}

s8_start_frontend() {
  step "启动前端 Vite 开发服务器并验证 /api 代理到后端"
  (
    cd "$FRONTEND_DIR" || exit 1
    setsid npm run dev
  ) >"$FRONTEND_LOG" 2>&1 &
  FRONTEND_PID=$!
  echo "$FRONTEND_PID" > "$FRONTEND_PID_FILE"

  if ! wait_http_ok "http://127.0.0.1:$FRONTEND_PORT/" 60 "$FRONTEND_PID"; then
    fail_step "前端在 60 秒内未能访问（依赖或配置问题）" "$FRONTEND_LOG"
  fi
  ok "前端已启动 (pid $FRONTEND_PID)"

  # 端到端验证：通过 Vite 代理打到后端，确保接口地址配置正确，而不是只验证页面能开
  if ! curl -sf -o /dev/null "http://127.0.0.1:$FRONTEND_PORT/api/health"; then
    fail_step "前端页面可访问，但 /api 代理到 $BACKEND_HOST:$BACKEND_PORT 失败（检查 .env 中 BACKEND_HOST/BACKEND_PORT）" "$FRONTEND_LOG" "$BACKEND_LOG"
  fi
  ok "前后端联通（Vite /api 代理 → 后端健康检查通过）"
}

# ---------------------------------------------------------------------------
# 命令
# ---------------------------------------------------------------------------
cmd_clean() {
  load_config
  mkdir -p "$RUN_DIR"
  echo "${C_BLUE}清理中间产物...${C_OFF}"
  kill_pidfile "$BACKEND_PID_FILE" "后端"
  kill_pidfile "$FRONTEND_PID_FILE" "前端"
  rm -rf "$FRONTEND_DIR/dist" "$FRONTEND_DIR/node_modules/.vite"
  find "$BACKEND_DIR" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf "$BACKEND_DIR/.pytest_cache"
  rm -f "$RUN_DIR"/*.log "$RUN_DIR"/*.pid
  ok "已清理。依赖目录(.venv/node_modules)与数据目录($DATA_DIR)保留。"
}

cmd_stop() {
  load_config
  kill_pidfile "$BACKEND_PID_FILE" "后端"
  kill_pidfile "$FRONTEND_PID_FILE" "前端"
  ok "完成"
}

cmd_reset_data() {
  load_config
  mkdir -p "$DATA_DIR"
  [[ -f "$DATA_DIR/seed.json" ]] || die "找不到示例数据文件 $DATA_DIR/seed.json"
  cp -f "$DATA_DIR/seed.json" "$DATA_DIR/state.json"
  ok "示例数据已恢复到初始状态: $DATA_DIR/state.json"
  info "若大屏正开着，点页面会自动拉取最新状态；浏览器中的实时曲线属会话数据，点页面上的“恢复示例数据”按钮可一并清空。"
}

cmd_setup() {
  load_config
  echo "${C_BLUE}== 监控大屏依赖安装与构建校验 ==${C_OFF}"
  s1_check_runtime
  s2_stop_stale
  s3_clean_artifacts
  s4_backend_deps
  s5_frontend_deps
  s6_build_check
  echo
  ok "全部检查通过。执行 ./scripts/dev.sh 即可一键启动。"
}

cmd_dev() {
  load_config
  echo "${C_BLUE}== 监控大屏一键启动（后端 :$BACKEND_PORT / 前端 :$FRONTEND_PORT） ==${C_OFF}"
  s1_check_runtime
  s2_stop_stale
  s3_clean_artifacts
  s4_backend_deps
  s5_frontend_deps
  s6_build_check
  s7_start_backend
  s8_start_frontend

  cleanup_on_exit() {
    echo
    info "收到退出信号，停止前后端 ..."
    kill_pidfile "$FRONTEND_PID_FILE" "前端"
    kill_pidfile "$BACKEND_PID_FILE" "后端"
    exit 0
  }
  trap cleanup_on_exit INT TERM EXIT

  echo
  echo "${C_GREEN}========================================================${C_OFF}"
  echo "${C_GREEN} 大屏已启动: http://127.0.0.1:$FRONTEND_PORT/${C_OFF}"
  echo "${C_GREEN} 后端接口:   http://$BACKEND_HOST:$BACKEND_PORT/api/health${C_OFF}"
  echo "${C_DIM} 日志: $BACKEND_LOG / $FRONTEND_LOG${C_OFF}"
  echo "${C_DIM} 恢复示例数据: ./scripts/dev.sh reset-data （或点页面上的按钮）${C_OFF}"
  echo "${C_GREEN} 按 Ctrl-C 一起停止前后端${C_OFF}"
  echo "${C_GREEN}========================================================${C_OFF}"

  # 任一进程退出即整体失败退出，避免“前端挂了后端还在跑”的半吊子状态
  while true; do
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
      fail_step "后端进程意外退出" "$BACKEND_LOG"
    fi
    if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
      fail_step "前端进程意外退出" "$FRONTEND_LOG"
    fi
    sleep 2
  done
}

case "${1:-dev}" in
  dev)        cmd_dev ;;
  setup)      cmd_setup ;;
  reset-data) cmd_reset_data ;;
  stop)       cmd_stop ;;
  clean)      cmd_clean ;;
  *) echo "用法: $0 [dev|setup|reset-data|stop|clean]"; exit 1 ;;
esac
