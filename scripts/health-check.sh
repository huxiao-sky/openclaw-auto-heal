#!/bin/bash
# Gateway 健康检查脚本 v3.2
#
# v3.2 改进:
# - 自动发现 openclaw / bash / tee / stat / gzip 路径
# - 去掉 /opt/homebrew/bin 硬编码
# - 增加基础目录初始化与函数封装

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

FAILURE_COUNT_FILE="$HOME/.openclaw/logs/failure-count"
LOG_FILE="$HOME/.openclaw/logs/healthcheck.log"
AUTO_HEAL_SCRIPT="$HOME/.openclaw/scripts/auto-heal-ai.sh"
FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-3}"
FAILURE_COUNT_MAX="${FAILURE_COUNT_MAX:-10}"
LOG_ROTATE_SIZE="${LOG_ROTATE_SIZE:-10485760}"
DEFAULT_CHANNEL="${DEFAULT_CHANNEL:-feishu}"

find_cmd() {
    local name="$1"
    shift || true
    local candidate
    for candidate in "$@"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    return 1
}

require_cmd() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        echo "缺少依赖命令: $name" >&2
        exit 1
    fi
}

OPENCLAW_BIN="$(find_cmd openclaw /opt/homebrew/bin/openclaw /usr/local/bin/openclaw || true)"
BASH_BIN="$(find_cmd bash /bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash || true)"
TEE_BIN="$(find_cmd tee /usr/bin/tee /bin/tee || true)"
STAT_BIN="$(find_cmd stat /usr/bin/stat /bin/stat || true)"
GZIP_BIN="$(find_cmd gzip /usr/bin/gzip /bin/gzip || true)"
MKDIR_BIN="$(find_cmd mkdir /bin/mkdir /usr/bin/mkdir || true)"
CAT_BIN="$(find_cmd cat /bin/cat /usr/bin/cat || true)"

require_cmd openclaw "$OPENCLAW_BIN"
require_cmd bash "$BASH_BIN"
require_cmd tee "$TEE_BIN"
require_cmd stat "$STAT_BIN"
require_cmd mkdir "$MKDIR_BIN"
require_cmd cat "$CAT_BIN"

ensure_parent_dirs() {
    "$MKDIR_BIN" -p "$(dirname "$LOG_FILE")"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | "$TEE_BIN" -a "$LOG_FILE"
}

rotate_log_if_needed() {
    if [ -f "$LOG_FILE" ] && [ "$("$STAT_BIN" -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$LOG_ROTATE_SIZE" ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
        if [ -n "$GZIP_BIN" ]; then
            "$GZIP_BIN" "$LOG_FILE.old" 2>/dev/null &
        fi
    fi
}

run_openclaw() {
    "$OPENCLAW_BIN" "$@"
}

send_notification() {
    local message="$1"
    run_openclaw message send --channel "$DEFAULT_CHANNEL" --message "$message" >> "$LOG_FILE" 2>&1 || true
}

status_ok() {
    run_openclaw status &>/dev/null
}

ensure_parent_dirs
rotate_log_if_needed

if pgrep -f "openclaw.*restart" > /dev/null 2>&1; then
    log "Gateway正在重启,跳过本次检查"
    exit 0
fi

log "开始健康检查..."

if status_ok; then
    log "✓ Gateway运行正常"
    echo 0 > "$FAILURE_COUNT_FILE"
    exit 0
fi

COUNT="$(cat "$FAILURE_COUNT_FILE" 2>/dev/null || echo 0)"
COUNT=$((COUNT + 1))

if [ "$COUNT" -gt "$FAILURE_COUNT_MAX" ]; then
    COUNT="$FAILURE_COUNT_MAX"
    log "失败计数已达上限"
fi

echo "$COUNT" > "$FAILURE_COUNT_FILE"
log "✗ Gateway异常 (失败次数: $COUNT)"

if [ "$COUNT" -ge "$FAILURE_THRESHOLD" ]; then
    log "连续失败${FAILURE_THRESHOLD}次,触发AI自动修复..."

    send_notification "⚠️ Gateway健康检查失败\n\n连续失败: $COUNT次\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n正在触发自动修复..."

    if [ ! -x "$AUTO_HEAL_SCRIPT" ]; then
        log "✗ 自动修复脚本不存在或不可执行: $AUTO_HEAL_SCRIPT"
        send_notification "❌ 自动修复脚本不存在或不可执行，请人工检查"
        exit 1
    fi

    "$BASH_BIN" "$AUTO_HEAL_SCRIPT" >> "$LOG_FILE" 2>&1
fi
