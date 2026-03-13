#!/bin/bash
# OpenClaw Gateway AI 自动修复脚本 v3.4
#
# 功能:
# 1. 检测配置错误并调用 AI 生成修复脚本
# 2. JSON 完全损坏时直接从安全备份恢复
# 3. 独立安全备份机制,防止配置丢失
#
# v3.4 改进:
# - 支持独立 AI 配置优先，OpenClaw 配置兜底
# - 统一 AI 请求构建逻辑
# - 增强修复脚本安全检查，限制修改范围到目标配置文件

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# ========== 配置文件路径 ==========
LOG_FILE="$HOME/.openclaw/logs/auto-heal.log"
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
BACKUP_FILE="$HOME/.openclaw/logs/openclaw.json.broken"
RETRY_COUNT_FILE="$HOME/.openclaw/logs/heal-retry-count"
LOCK_FILE="$HOME/.openclaw/logs/auto-heal.lock"
SAFE_BACKUP="$HOME/.openclaw/logs/openclaw.json.safe-backup"

MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_WINDOW="${RETRY_WINDOW:-3600}"
LOG_ROTATE_SIZE="${LOG_ROTATE_SIZE:-10485760}"
DEFAULT_API_ENDPOINT="${DEFAULT_API_ENDPOINT:-https://code.newcli.com/claude/droid/v1/messages}"
DEFAULT_MODEL="${DEFAULT_MODEL:-claude-sonnet-4-5}"
DEFAULT_CHANNEL="${DEFAULT_CHANNEL:-feishu}"
DEFAULT_MAX_TOKENS="${DEFAULT_MAX_TOKENS:-4096}"
DEFAULT_API_HEADER_KEY="${DEFAULT_API_HEADER_KEY:-x-api-key}"
DEFAULT_API_VERSION_HEADER="${DEFAULT_API_VERSION_HEADER:-anthropic-version}"
DEFAULT_API_VERSION_VALUE="${DEFAULT_API_VERSION_VALUE:-2023-06-01}"
AUTO_HEAL_PROVIDER="${AUTO_HEAL_PROVIDER:-}"
AUTO_HEAL_API_KEY="${AUTO_HEAL_API_KEY:-}"
AUTO_HEAL_API_ENDPOINT="${AUTO_HEAL_API_ENDPOINT:-}"
AUTO_HEAL_MODEL="${AUTO_HEAL_MODEL:-}"
AUTO_HEAL_API_HEADER_VALUE="${AUTO_HEAL_API_HEADER_VALUE:-}"
AUTO_HEAL_API_VERSION_VALUE="${AUTO_HEAL_API_VERSION_VALUE:-}"
ENABLE_DOCTOR_FIX="${ENABLE_DOCTOR_FIX:-1}"
DRY_RUN="${DRY_RUN:-0}"
SHOW_DIFF="${SHOW_DIFF:-1}"

# ========== 工具发现 ==========
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
CURL_BIN="$(find_cmd curl /usr/bin/curl /opt/homebrew/bin/curl /usr/local/bin/curl || true)"
JQ_BIN="$(find_cmd jq /opt/homebrew/bin/jq /usr/local/bin/jq "$HOME/.local/bin/jq" || true)"
PYTHON_BIN="$(find_cmd python3 /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 || true)"
GZIP_BIN="$(find_cmd gzip /usr/bin/gzip /bin/gzip || true)"
STAT_BIN="$(find_cmd stat /usr/bin/stat /bin/stat || true)"
TEE_BIN="$(find_cmd tee /usr/bin/tee /bin/tee || true)"
MKDIR_BIN="$(find_cmd mkdir /bin/mkdir /usr/bin/mkdir || true)"
CAT_BIN="$(find_cmd cat /bin/cat /usr/bin/cat || true)"
GREP_BIN="$(find_cmd grep /usr/bin/grep /bin/grep || true)"
DIFF_BIN="$(find_cmd diff /usr/bin/diff /bin/diff || true)"

require_cmd openclaw "$OPENCLAW_BIN"
require_cmd curl "$CURL_BIN"
require_cmd jq "$JQ_BIN"
require_cmd python3 "$PYTHON_BIN"
require_cmd stat "$STAT_BIN"
require_cmd tee "$TEE_BIN"
require_cmd mkdir "$MKDIR_BIN"
require_cmd cat "$CAT_BIN"
require_cmd grep "$GREP_BIN"

# ========== 公共函数 ==========
ensure_parent_dirs() {
    "$MKDIR_BIN" -p "$(dirname "$LOG_FILE")"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | "$TEE_BIN" -a "$LOG_FILE"
}

run_openclaw() {
    "$OPENCLAW_BIN" "$@"
}

rotate_log_if_needed() {
    local file="$1"
    if [ -f "$file" ] && [ "$("$STAT_BIN" -f%z "$file" 2>/dev/null || echo 0)" -gt "$LOG_ROTATE_SIZE" ]; then
        mv "$file" "$file.old"
        if [ -n "$GZIP_BIN" ]; then
            "$GZIP_BIN" "$file.old" 2>/dev/null &
        fi
    fi
}

send_notification() {
    local message="$1"
    run_openclaw message send --channel "$DEFAULT_CHANNEL" --message "$message" >> "$LOG_FILE" 2>&1 || true
}

status_ok() {
    run_openclaw status &>/dev/null
}

gateway_restart() {
    run_openclaw gateway restart >> "$LOG_FILE" 2>&1
}

validate_config() {
    run_openclaw config validate "$@"
}

json_valid() {
    "$PYTHON_BIN" -c "import json; json.load(open('$1'))" 2>/dev/null
}

json_get() {
    local file="$1"
    local expr="$2"
    "$JQ_BIN" -r "$expr // empty" "$file" 2>/dev/null | head -1
}

detect_model_config_from_openclaw() {
    local source_file="$1"

    PROVIDER="$(json_get "$source_file" '.models.defaultProvider')"
    if [ -z "$PROVIDER" ] || [ "$PROVIDER" = "null" ]; then
        PROVIDER="$(json_get "$source_file" '.models.providers | keys[0]')"
    fi

    if [ -z "$PROVIDER" ] || [ "$PROVIDER" = "null" ]; then
        return 1
    fi

    API_KEY="$(json_get "$source_file" ".models.providers.\"$PROVIDER\".apiKey")"
    API_ENDPOINT="$(json_get "$source_file" ".models.providers.\"$PROVIDER\".endpoint")"
    MODEL="$(json_get "$source_file" ".models.providers.\"$PROVIDER\".model")"
    API_HEADER_KEY="$DEFAULT_API_HEADER_KEY"
    API_HEADER_VALUE="$API_KEY"
    API_VERSION_HEADER="$DEFAULT_API_VERSION_HEADER"
    API_VERSION_VALUE="$DEFAULT_API_VERSION_VALUE"
    AI_CONFIG_SOURCE="openclaw-config"

    if [ -z "$API_ENDPOINT" ] || [ "$API_ENDPOINT" = "null" ]; then
        API_ENDPOINT="$DEFAULT_API_ENDPOINT"
    fi

    if [ -z "$MODEL" ] || [ "$MODEL" = "null" ]; then
        MODEL="$DEFAULT_MODEL"
    fi

    [ -n "$API_KEY" ] && [ "$API_KEY" != "null" ]
}

detect_model_config_from_env() {
    if [ -z "$AUTO_HEAL_API_KEY" ]; then
        return 1
    fi

    PROVIDER="${AUTO_HEAL_PROVIDER:-external}"
    API_KEY="$AUTO_HEAL_API_KEY"
    API_ENDPOINT="${AUTO_HEAL_API_ENDPOINT:-$DEFAULT_API_ENDPOINT}"
    MODEL="${AUTO_HEAL_MODEL:-$DEFAULT_MODEL}"
    API_HEADER_KEY="$DEFAULT_API_HEADER_KEY"
    API_HEADER_VALUE="${AUTO_HEAL_API_HEADER_VALUE:-$AUTO_HEAL_API_KEY}"
    API_VERSION_HEADER="$DEFAULT_API_VERSION_HEADER"
    API_VERSION_VALUE="${AUTO_HEAL_API_VERSION_VALUE:-$DEFAULT_API_VERSION_VALUE}"
    AI_CONFIG_SOURCE="env"

    [ -n "$API_HEADER_VALUE" ]
}

detect_model_config() {
    if detect_model_config_from_env; then
        return 0
    fi
    detect_model_config_from_openclaw "$1"
}

restore_from_safe_backup() {
    local reason="$1"
    local success_message="$2"

    log "$reason"
    cp "$SAFE_BACKUP" "$CONFIG_FILE"
    gateway_restart
    sleep 5

    if status_ok; then
        log "✓ 从安全备份恢复成功"
        echo 0 > "$RETRY_COUNT_FILE"
        [ -n "$success_message" ] && send_notification "$success_message"
        return 0
    fi

    log "✗ 恢复后 Gateway 仍然失败"
    return 1
}

build_ai_request_body() {
    "$PYTHON_BIN" - <<PY
import json
body = {
    "model": ${MODEL@Q},
    "max_tokens": int(${DEFAULT_MAX_TOKENS@Q}),
    "messages": [
        {
            "role": "user",
            "content": ${PROMPT@Q}
        }
    ]
}
print(json.dumps(body, ensure_ascii=False))
PY
}

extract_ai_text() {
    local response_file="$1"
    "$JQ_BIN" -r '
        .content[0].text //
        .choices[0].message.content //
        .output_text //
        empty
    ' "$response_file" 2>/dev/null
}

show_config_diff() {
    if [ "$SHOW_DIFF" != "1" ]; then
        return 0
    fi
    if [ -n "$DIFF_BIN" ] && [ -f "$BACKUP_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        log "配置变更 diff 如下:"
        "$DIFF_BIN" -u "$BACKUP_FILE" "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 || true
    fi
}

doctor_fix() {
    if [ "$ENABLE_DOCTOR_FIX" != "1" ]; then
        return 2
    fi

    log "尝试官方修复链路: openclaw doctor --fix"

    if [ "$DRY_RUN" = "1" ]; then
        log "DRY-RUN 模式：跳过执行 openclaw doctor --fix"
        return 2
    fi

    if run_openclaw doctor --fix >> "$LOG_FILE" 2>&1; then
        log "✓ 官方 doctor --fix 执行完成，开始重新验证配置"
        if validate_config >> "$LOG_FILE" 2>&1; then
            log "✓ doctor --fix 后配置验证通过"
            gateway_restart
            sleep 5
            if status_ok; then
                log "✓ doctor --fix 修复成功，Gateway 已恢复"
                cp "$CONFIG_FILE" "$SAFE_BACKUP.tmp"
                if json_valid "$SAFE_BACKUP.tmp"; then
                    mv "$SAFE_BACKUP.tmp" "$SAFE_BACKUP"
                    log "✓ 安全备份已更新"
                else
                    rm -f "$SAFE_BACKUP.tmp"
                    log "✗ doctor --fix 后新配置未通过 JSON 检查，保留旧备份"
                fi
                echo 0 > "$RETRY_COUNT_FILE"
                send_notification "✅ 官方 doctor --fix 修复成功"
                return 0
            fi
        fi
        log "✗ doctor --fix 执行后仍未恢复，继续尝试 AI 修复"
        return 1
    fi

    log "✗ 官方 doctor --fix 执行失败，继续尝试 AI 修复"
    return 1
}

validate_fix_script_security() {
    local script_file="$1"
    local config_realpath
    config_realpath="$(python3 - <<PY
from pathlib import Path
print(Path(${CONFIG_FILE@Q}).expanduser().resolve())
PY
)"

    if "$GREP_BIN" -qE 'rm -rf /|sudo|eval\(|exec\(|__import__|os\.system|subprocess\.(call|run|Popen)|pty\.spawn|shutil\.rmtree|Path\("/"\)|open\("/etc/|open\("/Users/|requests\.|urllib\.' "$script_file"; then
        log "✗ 检测到危险操作，拒绝执行"
        return 1
    fi

    "$PYTHON_BIN" - <<PY
import ast
import sys
from pathlib import Path

script_path = Path(${script_file@Q})
config_path = Path(${config_realpath@Q})
source = script_path.read_text(encoding='utf-8')
allowed_open_targets = {str(config_path), str(config_path.expanduser())}

try:
    tree = ast.parse(source)
except SyntaxError as e:
    print(f"语法错误: {e}", file=sys.stderr)
    sys.exit(1)

for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            if alias.name in {"os", "subprocess", "shutil", "requests", "urllib"}:
                print(f"禁止导入模块: {alias.name}", file=sys.stderr)
                sys.exit(1)
    if isinstance(node, ast.ImportFrom):
        if node.module in {"os", "subprocess", "shutil", "requests", "urllib"}:
            print(f"禁止 from-import 模块: {node.module}", file=sys.stderr)
            sys.exit(1)
    if isinstance(node, ast.Call):
        func = node.func
        if isinstance(func, ast.Name) and func.id == 'open' and node.args:
            arg = node.args[0]
            if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                target = str(Path(arg.value).expanduser())
                if target not in allowed_open_targets:
                    print(f"禁止写入其他文件: {target}", file=sys.stderr)
                    sys.exit(1)
        if isinstance(func, ast.Attribute):
            chain = []
            cur = func
            while isinstance(cur, ast.Attribute):
                chain.append(cur.attr)
                cur = cur.value
            if isinstance(cur, ast.Name):
                chain.append(cur.id)
            full = '.'.join(reversed(chain))
            banned_prefixes = (
                'os.system', 'os.remove', 'os.unlink', 'os.rmdir',
                'subprocess.run', 'subprocess.call', 'subprocess.Popen',
                'shutil.rmtree', 'requests.', 'urllib.'
            )
            if any(full == p or full.startswith(p) for p in banned_prefixes):
                print(f"禁止调用: {full}", file=sys.stderr)
                sys.exit(1)

print('ok')
PY
}

ensure_parent_dirs
rotate_log_if_needed "$LOG_FILE"

# ========== 并发保护 ==========
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    if [ -n "$LOCK_PID" ] && ps -p "$LOCK_PID" > /dev/null 2>&1; then
        log "另一个修复进程正在运行 (PID: $LOCK_PID)"
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

log "========== AI 自动修复开始 =========="

# ========== 安全备份机制 ==========
if [ ! -f "$SAFE_BACKUP" ]; then
    log "首次运行,创建安全备份..."

    if validate_config &>/dev/null; then
        cp "$CONFIG_FILE" "$SAFE_BACKUP"
        log "✓ 从当前配置创建安全备份"
    else
        log "当前配置无效,搜索有效备份..."
        for backup in "$HOME/.openclaw/openclaw.json.bak" "$HOME/.openclaw/openclaw.json.bak.1" "$HOME/.openclaw/openclaw.json.bak.2"; do
            if [ -f "$backup" ]; then
                cp "$backup" /tmp/test-backup.json
                if validate_config --config /tmp/test-backup.json &>/dev/null; then
                    cp "$backup" "$SAFE_BACKUP"
                    log "✓ 从 $backup 创建安全备份"
                    rm -f /tmp/test-backup.json
                    break
                fi
                rm -f /tmp/test-backup.json
            fi
        done

        if [ ! -f "$SAFE_BACKUP" ]; then
            log "✗ 无法找到有效配置创建安全备份"
            exit 1
        fi
    fi
fi

# ========== 重试次数检查(时间窗口重置) ==========
if [ -f "$RETRY_COUNT_FILE" ]; then
    LAST_RETRY_TIME="$("$STAT_BIN" -f %m "$RETRY_COUNT_FILE" 2>/dev/null || echo 0)"
    CURRENT_TIME="$(date +%s)"

    if [ $((CURRENT_TIME - LAST_RETRY_TIME)) -gt "$RETRY_WINDOW" ]; then
        echo 0 > "$RETRY_COUNT_FILE"
        log "重试计数已重置（超过1小时窗口）"
    fi
fi

RETRY_COUNT="$(cat "$RETRY_COUNT_FILE" 2>/dev/null || echo 0)"
RETRY_COUNT=$((RETRY_COUNT + 1))
echo "$RETRY_COUNT" > "$RETRY_COUNT_FILE"

if [ "$RETRY_COUNT" -gt "$MAX_RETRIES" ]; then
    log "✗ 已达最大重试次数 ($MAX_RETRIES)"
    log "从安全备份恢复配置..."

    if [ ! -f "$SAFE_BACKUP" ]; then
        log "✗ 安全备份不存在,无法恢复"
        send_notification "❌ 严重错误：安全备份丢失，无法自动恢复"
        exit 1
    fi

    cp "$SAFE_BACKUP" "$CONFIG_FILE"
    gateway_restart
    sleep 5

    if status_ok; then
        log "✓ 从安全备份恢复成功"
        send_notification "✅ AI修复失败 $MAX_RETRIES 次，已从安全备份恢复成功"
    else
        log "✗ 恢复后 Gateway 仍然失败"
        send_notification "❌ 从安全备份恢复失败，需要人工介入"
    fi

    echo 0 > "$RETRY_COUNT_FILE"
    exit 1
fi

log "第 $RETRY_COUNT 次修复尝试（最多 $MAX_RETRIES 次）"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# ========== JSON 格式检查 ==========
log "检查 JSON 格式..."

if ! json_valid "$CONFIG_FILE"; then
    log "✗ JSON 完全损坏,无法解析"
    restore_from_safe_backup "直接从安全备份恢复..." "✅ JSON 损坏，已从安全备份恢复"
    exit $?
fi

log "✓ JSON 格式正常,继续修复流程"

# ========== 官方 doctor 修复链路 ==========
if doctor_fix; then
    exit 0
fi

# ========== 模型配置提取 ==========
log "检测 AI 配置..."
if ! detect_model_config "$SAFE_BACKUP"; then
    log "✗ 无法获取可用的 AI 配置（环境变量和 OpenClaw 配置都不可用）"
    exit 1
fi
log "✓ AI 配置检测成功 (source=$AI_CONFIG_SOURCE, provider=$PROVIDER, model=$MODEL)"

# ========== 收集错误信息 ==========
log "收集配置错误信息..."
VALIDATION_ERROR="$(validate_config 2>&1 || true)"
log "✓ 错误信息已收集"

# ========== 构建 AI 提示 ==========
PROMPT=$(cat <<PROMPTEND | "$JQ_BIN" -Rs .
你是 OpenClaw 配置修复专家。

**配置验证错误:**
$VALIDATION_ERROR

**配置文件路径:** $CONFIG_FILE

**任务:** 生成最小修改的 Python 修复脚本，只允许读写这一个配置文件，不能访问网络，不能执行子进程，不能修改其他文件。

只输出可执行的 Python 代码:
\`\`\`python
import json
from pathlib import Path

config_path = Path("$CONFIG_FILE").expanduser()
with open(config_path) as f:
    config = json.load(f)

# 根据错误修复配置
# 例如: null 值改为空字符串
# 例如: 删除未识别的字段

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("✓ 配置已修复")
\`\`\`
PROMPTEND
)

# ========== 调用 AI API ==========
log "调用 AI 生成修复脚本..."
REQUEST_BODY="$(build_ai_request_body)"
RESPONSE_FILE="/tmp/auto-heal-response-$$.json"

HTTP_CODE="$(
  "$CURL_BIN" -sS --max-time 60 --connect-timeout 10 \
    -X POST "$API_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "$API_HEADER_KEY: $API_HEADER_VALUE" \
    -H "$API_VERSION_HEADER: $API_VERSION_VALUE" \
    -d "$REQUEST_BODY" \
    -o "$RESPONSE_FILE" \
    -w '%{http_code}'
)"

if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
    log "✗ API 调用失败 (HTTP $HTTP_CODE)"
    [ -f "$RESPONSE_FILE" ] && "$CAT_BIN" "$RESPONSE_FILE" >> "$LOG_FILE"
    rm -f "$RESPONSE_FILE"
    exit 1
fi

RESPONSE_TEXT="$(extract_ai_text "$RESPONSE_FILE")"
rm -f "$RESPONSE_FILE"

if [ -z "$RESPONSE_TEXT" ]; then
    log "✗ AI 返回中未找到可解析文本"
    exit 1
fi

log "✓ AI 响应成功"

# ========== 提取并执行修复脚本 ==========
FIX_SCRIPT="/tmp/fix-$$.py"
AI_FULL_TEXT="/tmp/ai-full-$$.txt"
printf '%s' "$RESPONSE_TEXT" > "$AI_FULL_TEXT"
sed -n '/```python/,/```/p' "$AI_FULL_TEXT" | sed '1d;$d' > "$FIX_SCRIPT"
rm -f "$AI_FULL_TEXT"

if [ ! -s "$FIX_SCRIPT" ]; then
    log "✗ AI 未生成有效的修复脚本"
    exit 1
fi

# ========== 安全检查 ==========
if ! validate_fix_script_security "$FIX_SCRIPT" >> "$LOG_FILE" 2>&1; then
    log "✗ 修复脚本未通过安全检查，拒绝执行"
    "$CAT_BIN" "$FIX_SCRIPT" >> "$LOG_FILE"
    send_notification "⚠️ AI修复被阻止\n修复脚本未通过安全检查"
    rm -f "$FIX_SCRIPT"
    exit 1
fi
log "✓ 代码安全检查通过"

# ========== 执行修复 ==========
log "执行 AI 生成的修复脚本..."

if "$PYTHON_BIN" "$FIX_SCRIPT" >> "$LOG_FILE" 2>&1; then
    log "✓ 修复脚本执行成功"
else
    log "✗ 修复脚本执行失败"
    rm -f "$FIX_SCRIPT"
    exit 1
fi

rm -f "$FIX_SCRIPT"

if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN 模式：已生成并执行修复脚本，但不会覆盖安全备份，也不会重启 Gateway"
    show_config_diff
    exit 0
fi

show_config_diff

# ========== 验证并更新备份 ==========
log "验证修复后的配置..."

if validate_config >> "$LOG_FILE" 2>&1; then
    log "✓ 配置验证通过"

    cp "$CONFIG_FILE" "$SAFE_BACKUP.tmp"
    if json_valid "$SAFE_BACKUP.tmp"; then
        mv "$SAFE_BACKUP.tmp" "$SAFE_BACKUP"
        log "✓ 安全备份已更新"
    else
        rm -f "$SAFE_BACKUP.tmp"
        log "✗ 新配置验证失败，保留旧备份"
    fi
else
    log "✗ 配置验证失败,从安全备份恢复"
    cp "$SAFE_BACKUP" "$CONFIG_FILE"
    exit 1
fi

# ========== 重启并验证 ==========
log "重启 Gateway..."
gateway_restart
sleep 5

if status_ok; then
    log "✓ Gateway 启动成功"
    echo 0 > "$RETRY_COUNT_FILE"
    send_notification "✅ AI自动修复成功（第 ${RETRY_COUNT} 次尝试）"
    exit 0
else
    log "✗ Gateway 仍然失败"
    exit 1
fi
