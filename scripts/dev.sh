#!/usr/bin/env bash
# =============================================================================
# 监控大屏本地开发一键编排脚本
#
# 用法:
#   ./scripts/dev.sh             # 同 up：检查依赖 -> 构建校验 -> 启动前后端（前台运行，Ctrl-C 退出）
#   ./scripts/dev.sh up
#   ./scripts/dev.sh check       # 只做依赖检查 + 构建校验（CI / 排错用）
#   ./scripts/dev.sh reset-data  # 一键恢复示例数据到初始状态
#   ./scripts/dev.sh down        # 停止本脚本启动的前后端进程
#   ./scripts/dev.sh clean       # 清理构建产物和缓存（不动依赖）
#
# 设计约定:
#   - 每一步都有编号和明确的成功/失败输出，失败立即中止并给出原因
#   - 不使用任何“上次结果”标记文件：依赖每次做真实 import/二进制校验，
#     构建前先删产物，构建产物仅用于校验、校验完立即删除
#   - 每次启动前停止上次的进程并预检端口，保证重跑是干净的全新启动
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT/frontend"
BACKEND_DIR="$ROOT/backend"
RUN_DIR="$ROOT/.run"
LOG_DIR="$RUN_DIR/logs"

# ---------- 颜色 / 日志 ----------
if [[ -t 1 ]]; then
  C_GREEN='\033[0;32m'; C_RED='\033[0;31m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_OFF='\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_BLUE=''; C_OFF=''
fi

STEP=0
step()  { STEP=$((STEP + 1)); echo -e "${C_BLUE}[$STEP] $*${C_OFF}"; }
ok()    { echo -e "  ${C_GREEN}✓ $*${C_OFF}"; }
info()  { echo -e "  ${C_YELLOW}→ $*${C_OFF}"; }
die()   { echo -e "  ${C_RED}✗ $*${C_OFF}" >&2; exit 1; }

trap 'die "第 $STEP 步执行失败（命令: $BASH_COMMAND）。请根据上面的输出定位原因，修复后重新运行即可，脚本会先清理上次的进程和产物。"' ERR

# ---------- 环境变量 ----------
load_env() {
  if [[ -f "$ROOT/.env" ]]; then
    info "加载配置 $ROOT/.env"
    set -a; source "$ROOT/.env"; set +a
  else
    info "未找到 .env，使用 .env.example 中的默认配置（如需自定义: cp .env.example .env）"
    set -a; source "$ROOT/.env.example"; set +a
  fi
  : "${BACKEND_PORT:?BACKEND_PORT 未设置}"
  : "${FRONTEND_PORT:?FRONTEND_PORT 未设置}"
  : "${VITE_API_PROXY_TARGET:?VITE_API_PROXY_TARGET 未设置}"
  BROWSER_OPEN="${BROWSER_OPEN:-false}"
  export BACKEND_PORT FRONTEND_PORT VITE_API_PROXY_TARGET BROWSER_OPEN
}

# ---------- 清理 ----------
clean_artifacts() {
  info "清理构建产物与缓存（dist / __pycache__ / tsbuildinfo）"
  rm -rf "$FRONTEND_DIR/dist"
  find "$FRONTEND_DIR" -maxdepth 3 -name '*.tsbuildinfo' -not -path '*/node_modules/*' -delete 2>/dev/null || true
  find "$BACKEND_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf "$BACKEND_DIR/.pytest_cache"
}

# ---------- 依赖检查 / 安装 ----------
require_versions() {
  command -v node >/dev/null || die "未找到 node，请安装 Node.js 18+"
  command -v npm  >/dev/null || die "未找到 npm，请随 Node.js 一并安装"
  command -v python3 >/dev/null || die "未找到 python3，请安装 Python 3.9+"
  python3 -c 'import venv' 2>/dev/null || die "python3 缺少 venv 模块（Debian/Ubuntu: sudo apt install python3-venv）"

  local node_major py_version py_major py_minor
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  [[ "$node_major" -ge 18 ]] || die "Node 版本过低（当前 $(node -v)），需要 18+"
  py_version="$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
  py_major="${py_version%%.*}"; py_minor="${py_version#*.}"
  { [[ "$py_major" -gt 3 ]] || { [[ "$py_major" -eq 3 ]] && [[ "$py_minor" -ge 9 ]]; }; } \
    || die "Python 版本过低（当前 $py_version），需要 3.9+"
  ok "node $(node -v) / npm $(npm -v) / python $py_version"
}

ensure_backend_deps() {
  local venv="$BACKEND_DIR/.venv"
  local py="$venv/bin/python"
  if [[ ! -x "$py" ]]; then
    info "后端虚拟环境不存在，创建 $venv"
    if ! python3 -m venv "$venv" 2>"$RUN_DIR/venv.err"; then
      # 精简镜像常缺 ensurepip（Debian 需 python3-venv），但 venv 本体可用：
      # 先建无 pip 的 venv，再用官方 get-pip.py 引导
      info "标准 venv 创建失败（通常是缺 ensurepip/python3-venv），尝试 get-pip.py 兜底引导"
      rm -rf "$venv"
      python3 -m venv --without-pip "$venv" \
        || { cat "$RUN_DIR/venv.err"; die "无法创建虚拟环境，请安装 python3-venv"; }
      local get_pip="$RUN_DIR/get-pip.py"
      curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$get_pip" \
        || die "下载 get-pip.py 失败，请检查网络"
      "$py" "$get_pip" >/dev/null \
        || die "venv 内引导 pip 失败，请查看上方输出"
      rm -f "$get_pip"
    fi
    "$venv/bin/pip" install --quiet --upgrade pip
  fi
  if ! "$py" -c 'import fastapi, uvicorn, pymodbus, websockets' 2>/dev/null; then
    info "后端依赖缺失或损坏，执行 pip install -r requirements.txt"
    "$venv/bin/pip" install --quiet -r "$BACKEND_DIR/requirements.txt"
  fi
  "$py" -c 'import fastapi, uvicorn, pymodbus, websockets' \
    || die "后端依赖校验失败：无法 import fastapi/uvicorn/pymodbus/websockets，请检查 requirements.txt 安装输出"
  ok "后端依赖就绪（$("$py" -c 'import fastapi;print(fastapi.__version__)')）"
}

ensure_frontend_deps() {
  local need_install=0
  if [[ ! -d "$FRONTEND_DIR/node_modules" ]]; then
    need_install=1
  else
    # 真实校验关键可执行与模块是否可解析，而不是只看目录在不在
    [[ -x "$FRONTEND_DIR/node_modules/.bin/vite" ]] || need_install=1
    [[ -x "$FRONTEND_DIR/node_modules/.bin/vue-tsc" ]] || need_install=1
    (cd "$FRONTEND_DIR" && node -e "require.resolve('vue'); require.resolve('axios')") 2>/dev/null || need_install=1
  fi
  if [[ "$need_install" -eq 1 ]]; then
    info "前端依赖缺失或损坏，执行 npm install"
    (cd "$FRONTEND_DIR" && npm install --no-fund --no-audit)
  fi
  (cd "$FRONTEND_DIR" && node -e "require.resolve('vue'); require.resolve('vite'); require.resolve('vue-tsc'); require.resolve('axios')") \
    || die "前端依赖校验失败：关键模块无法解析，请查看 npm install 输出"
  ok "前端依赖就绪"
}

# ---------- 构建校验 ----------
validate_build() {
  step "构建校验（不通过会立即中止并打印原因）"
  clean_artifacts

  info "后端语法/导入校验：compileall + import app.main"
  (cd "$BACKEND_DIR" && "$BACKEND_DIR/.venv/bin/python" -m compileall -q app)
  (cd "$BACKEND_DIR" && "$BACKEND_DIR/.venv/bin/python" -c 'from app.main import app')
  ok "后端代码可正常导入"

  info "前端类型检查与构建：npm run build（vue-tsc && vite build）"
  (cd "$FRONTEND_DIR" && npm run build)
  ok "前端类型检查与构建通过"

  # 构建产物只是校验副产品，立即删除，避免被下次运行或 dev server 误用为旧结果
  rm -rf "$FRONTEND_DIR/dist"
  find "$BACKEND_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
  ok "已删除校验产生的中间产物"
}

# ---------- 进程 / 端口 ----------
_stop_group() {
  local pidfile="$1" name="$2"
  [[ -f "$pidfile" ]] || return 0
  local pid; pid="$(cat "$pidfile" 2>/dev/null || true)"
  rm -f "$pidfile"
  [[ -n "${pid:-}" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    # setsid 启动时 PID == 进程组 ID，整组结束掉 npm/uvicorn 派生的子进程
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    info "已停止 $name (pid $pid)"
  fi
}

stop_all() {
  _stop_group "$RUN_DIR/frontend.pid" "前端 dev server"
  _stop_group "$RUN_DIR/backend.pid" 后端
}

# 清理“无 PID 文件归属”的陈旧服务进程（例如上一次由外部入口启动、环境已重置的遗留进程）。
# 只匹配工作目录在本项目内、命令行特征吻合的进程，绝不误杀系统进程。
sweep_stale() {
  local cwds="$BACKEND_DIR $FRONTEND_DIR $ROOT"
  local killed=0 p pid cwd

  for p in $(pgrep -f 'uvicorn app\.main:app' 2>/dev/null) \
           $(pgrep -f 'vite( |\.js|$)' 2>/dev/null) \
           $(pgrep -f 'npm run dev' 2>/dev/null); do
    cwd="$(readlink "/proc/$p/cwd" 2>/dev/null || true)"
    [[ -n "$cwd" ]] || continue
    [[ " $cwds " == *" $cwd "* ]] || continue
    # 跳过当前编排脚本自己拉起的进程（它们有 PID 文件登记）
    if [[ -f "$RUN_DIR/backend.pid" && "$p" == "$(cat "$RUN_DIR/backend.pid")" ]] \
       || [[ -f "$RUN_DIR/frontend.pid" && "$p" == "$(cat "$RUN_DIR/frontend.pid")" ]]; then
      continue
    fi
    pid="$p"
    if kill -0 "$pid" 2>/dev/null; then
      local cmdline
      cmdline="$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | cut -c1-80)"
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
      kill -KILL "$pid" 2>/dev/null || true
      info "已清理陈旧进程 pid=$pid ($cmdline)"
      killed=1
    fi
  done
  [[ "$killed" -eq 0 ]] || sleep 1
}

port_free() { # $1=port
  # SO_REUSEADDR 只放过 TIME_WAIT 残留；若有真实 LISTEN 占用仍然绑定失败
  python3 - "$1" <<'EOF'
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
EOF
}

preflight_ports() {
  local who
  for spec in "$BACKEND_PORT:后端" "$FRONTEND_PORT:前端"; do
    local port="${spec%%:*}" name="${spec##*:}"
    if ! port_free "$port"; then
      who="$(ss -ltnp 2>/dev/null | grep ":$port " || true)"
      die "端口 $port（$name）已被占用。${who:+占用信息: $who；}请释放该端口，或在 .env 中修改端口后重试"
    fi
  done
  ok "端口 $BACKEND_PORT(后端) / $FRONTEND_PORT(前端) 均空闲"
}

wait_http() { # $1=url $2=timeout-seconds $3=label
  local url="$1" deadline=$(( $(date +%s) + $2 ))
  while (( $(date +%s) < deadline )); do
    if curl -sf -o /dev/null "$url"; then return 0; fi
    sleep 0.5
  done
  return 1
}

tail_log() { echo -e "  ${C_YELLOW}---- $1 末尾日志 ----${C_OFF}"; tail -n 30 "$1" 2>/dev/null || true; echo -e "  ${C_YELLOW}----------------------${C_OFF}"; }

# ---------- 启动 ----------
# 关键点：setsid 在调用方恰为进程组首进程时会 fork，$! 拿到的可能是随即退出的父 PID。
# 因此让新会话内的 bash 自己把 $$ 写入 PID 文件再 exec 服务，
# 保证 PID 文件记录的就是真实服务进程，且它是进程组首进程，可整组回收。
start_services() {
  step "启动前后端（日志: $LOG_DIR）"
  mkdir -p "$LOG_DIR"

  (cd "$BACKEND_DIR" && setsid env BACKEND_PORT="$BACKEND_PORT" bash -c '
      echo $$ > "$0"
      exec "$1" -m uvicorn app.main:app --host 127.0.0.1 --port "$2"
    ' "$RUN_DIR/backend.pid" "$BACKEND_DIR/.venv/bin/python" "$BACKEND_PORT" \
    >"$LOG_DIR/backend.log" 2>&1 &)
  wait_pidfile "$RUN_DIR/backend.pid"
  ok "后端已拉起 (pid $(cat "$RUN_DIR/backend.pid"), 日志 $LOG_DIR/backend.log)"

  (cd "$FRONTEND_DIR" && setsid env \
      FRONTEND_PORT="$FRONTEND_PORT" BACKEND_PORT="$BACKEND_PORT" \
      VITE_API_PROXY_TARGET="$VITE_API_PROXY_TARGET" BROWSER_OPEN="$BROWSER_OPEN" \
    bash -c '
      echo $$ > "$0"
      exec npm run dev
    ' "$RUN_DIR/frontend.pid" \
    >"$LOG_DIR/frontend.log" 2>&1 &)
  wait_pidfile "$RUN_DIR/frontend.pid"
  ok "前端已拉起 (pid $(cat "$RUN_DIR/frontend.pid"), 日志 $LOG_DIR/frontend.log)"
}

wait_pidfile() { # $1=pidfile
  local f="$1" i=0
  while { [[ ! -s "$f" ]] || ! kill -0 "$(cat "$f" 2>/dev/null)" 2>/dev/null; } && (( i < 40 )); do
    sleep 0.25; i=$((i + 1))
  done
  [[ -s "$f" ]] || die "等待 $f 超时，服务可能启动失败，请查看 $LOG_DIR 下日志"
}

health_checks() {
  step "健康检查（失败会打印对应日志并停止本次启动的进程）"
  if ! wait_http "http://127.0.0.1:$BACKEND_PORT/api/health" 30 后端; then
    tail_log "$LOG_DIR/backend.log"
    stop_all
    die "后端 30s 内未通过健康检查: GET /api/health"
  fi
  ok "后端健康检查通过"

  if ! wait_http "http://127.0.0.1:$FRONTEND_PORT/" 40 前端; then
    tail_log "$LOG_DIR/frontend.log"
    stop_all
    die "前端 40s 内未启动: http://127.0.0.1:$FRONTEND_PORT/"
  fi
  ok "前端 dev server 可访问"

  # 端到端验证：经 vite 代理打到后端拿到真实设备数据
  if ! curl -sf "http://127.0.0.1:$FRONTEND_PORT/api/modbus/devices" | grep -q 'dev1'; then
    tail_log "$LOG_DIR/frontend.log"; tail_log "$LOG_DIR/backend.log"
    stop_all
    die "前后端联通失败：经前端代理访问 /api/modbus/devices 未拿到数据，请检查 VITE_API_PROXY_TARGET=$VITE_API_PROXY_TARGET"
  fi
  ok "前后端联通正常（前端 /api -> 后端）"
}

print_ready() {
  echo
  echo -e "${C_GREEN}========================================================${C_OFF}"
  echo -e "${C_GREEN} 监控大屏已启动:${C_OFF}"
  echo -e "  前端大屏 : http://localhost:$FRONTEND_PORT/"
  echo -e "  后端接口 : http://localhost:$BACKEND_PORT/api/modbus/devices"
  echo -e "  健康检查 : http://localhost:$BACKEND_PORT/api/health"
  echo -e "  日志目录 : $LOG_DIR"
  echo -e "  停止服务: Ctrl-C 或 ./scripts/dev.sh down"
  echo -e "  恢复数据: ./scripts/dev.sh reset-data（然后点浏览器刷新）"
  echo -e "${C_GREEN}========================================================${C_OFF}"
}

# ---------- 子命令 ----------
cmd_check() {
  mkdir -p "$RUN_DIR"
  step "依赖检查"
  require_versions
  ensure_backend_deps
  ensure_frontend_deps
  validate_build
  echo -e "${C_GREEN}全部检查通过。${C_OFF}"
}

cmd_up() {
  mkdir -p "$RUN_DIR"
  step "停止上次运行的残留进程"
  stop_all
  sweep_stale
  load_env
  step "依赖检查（缺失会自动安装，安装后做真实导入校验）"
  require_versions
  ensure_backend_deps
  ensure_frontend_deps
  validate_build
  step "端口预检"
  preflight_ports
  start_services
  health_checks
  print_ready
  trap - ERR
  trap 'echo; info "收到退出信号，停止服务..."; stop_all; exit 0' INT TERM
  # 阻塞等待，任一进程退出则整体停止
  local bp fp
  bp="$(cat "$RUN_DIR/backend.pid")"; fp="$(cat "$RUN_DIR/frontend.pid")"
  while kill -0 "$bp" 2>/dev/null && kill -0 "$fp" 2>/dev/null; do sleep 1; done
  echo -e "  ${C_RED}检测到有进程提前退出，打印日志并停止全部服务${C_OFF}" >&2
  tail_log "$LOG_DIR/backend.log"; tail_log "$LOG_DIR/frontend.log"
  stop_all
  exit 1
}

cmd_down() {
  mkdir -p "$RUN_DIR"
  load_env >/dev/null 2>&1 || true
  stop_all
  info "完成"
}

cmd_reset_data() {
  load_env
  step "恢复示例数据（seed -> data）"
  require_versions
  ensure_backend_deps
  (cd "$BACKEND_DIR" && "$BACKEND_DIR/.venv/bin/python" - <<'EOF'
from app.services.modbus_service import reset_sample_data
devs = reset_sample_data()
print(f"已恢复 {len(devs)} 台设备的初始示例数据：")
for d in devs:
    vals = ", ".join(f"{r['name']}={r['value']}{r['unit']}" for r in d.get('registers', []))
    print(f"  - {d['id']} {d['name']} online={d['online']} | {vals}")
EOF
  )
  ok "示例数据已还原。大屏刷新页面后展示即为上述初始数据（后端每次从文件实时读取，无需重启）"
}

cmd_clean() {
  step "清理构建产物与缓存（保留 node_modules / .venv / 示例数据）"
  clean_artifacts
  ok "完成。如需连依赖一起删除: ./scripts/dev.sh nuke"
}

cmd_nuke() {
  step "删除所有本地产物（依赖、运行目录、当前工作数据），保留 seed"
  read -r -p "确认删除 node_modules / .venv / .run / backend/data ? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "已取消"
  stop_all || true
  rm -rf "$FRONTEND_DIR/node_modules" "$FRONTEND_DIR/dist" \
         "$BACKEND_DIR/.venv" "$BACKEND_DIR/data" "$RUN_DIR"
  find "$BACKEND_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
  ok "已重置为干净状态，重新运行 ./scripts/dev.sh 即可从零搭建"
}

case "${1:-up}" in
  up)          cmd_up ;;
  check)       cmd_check ;;
  reset-data)  cmd_reset_data ;;
  down|stop)   cmd_down ;;
  clean)       cmd_clean ;;
  nuke)        cmd_nuke ;;
  *)
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    die "未知子命令: $1"
    ;;
esac
