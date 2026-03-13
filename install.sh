#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.openclaw"
SCRIPTS_DIR="$TARGET_DIR/scripts"
LOGS_DIR="$TARGET_DIR/logs"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
USERNAME="$(whoami)"

mkdir -p "$SCRIPTS_DIR" "$LOGS_DIR" "$LAUNCH_AGENTS_DIR"

cp "$PROJECT_DIR/scripts/auto-heal-ai.sh" "$SCRIPTS_DIR/auto-heal-ai.sh"
cp "$PROJECT_DIR/scripts/health-check.sh" "$SCRIPTS_DIR/health-check.sh"
chmod +x "$SCRIPTS_DIR"/*.sh

if [ -f "$TARGET_DIR/openclaw.json" ] && [ ! -f "$LOGS_DIR/openclaw.json.safe-backup" ]; then
  cp "$TARGET_DIR/openclaw.json" "$LOGS_DIR/openclaw.json.safe-backup"
fi

sed "s|YOUR_USERNAME|$USERNAME|g" "$PROJECT_DIR/launchd/com.openclaw.gateway.plist" > "$LAUNCH_AGENTS_DIR/com.openclaw.gateway.plist"
sed "s|YOUR_USERNAME|$USERNAME|g" "$PROJECT_DIR/launchd/com.openclaw.healthcheck.plist" > "$LAUNCH_AGENTS_DIR/com.openclaw.healthcheck.plist"

launchctl unload "$LAUNCH_AGENTS_DIR/com.openclaw.gateway.plist" >/dev/null 2>&1 || true
launchctl unload "$LAUNCH_AGENTS_DIR/com.openclaw.healthcheck.plist" >/dev/null 2>&1 || true
launchctl load "$LAUNCH_AGENTS_DIR/com.openclaw.gateway.plist"
launchctl load "$LAUNCH_AGENTS_DIR/com.openclaw.healthcheck.plist"

echo "✅ OpenClaw Auto Heal 安装完成"
echo "- 脚本目录: $SCRIPTS_DIR"
echo "- LaunchAgents: $LAUNCH_AGENTS_DIR"
echo "- 用户名模板已替换: $USERNAME"
