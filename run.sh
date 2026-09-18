#!/usr/bin/env bash
# =============================================================================
# 监控大屏启动入口（编排逻辑见 scripts/dev.sh）
#
#   ./run.sh dev   等价于 ./scripts/dev.sh up：
#                  依赖检查 -> 构建校验 -> 端口预检 -> 启动前后端 -> 健康检查
#
# 其余参数直接透传给 scripts/dev.sh，例如:
#   ./run.sh check / reset-data / down / clean / nuke
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

cmd="${1:-dev}"
if [[ "$cmd" == "dev" ]]; then
  shift || true
  exec ./scripts/dev.sh up "$@"
fi
exec ./scripts/dev.sh "$@"
