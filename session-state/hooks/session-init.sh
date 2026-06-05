#!/bin/bash
# SessionStart hook: create session dir, clean stale history, output paths to Claude
INPUT=$(cat)
SID=$(echo "$INPUT" | jq -r '.session_id' | cut -c1-8)
DIR="${CLAUDE_PROJECT_DIR}/.claude/sessions/${SID}"
mkdir -p "$DIR"
touch "$DIR/.heartbeat"

HISTORY="${CLAUDE_PROJECT_DIR}/.claude/sessions/history"
if [ -d "$HISTORY" ]; then
  find "$HISTORY" -maxdepth 1 -mindepth 1 -type d -mtime +3 -exec rm -rf {} \; 2>/dev/null
fi

echo "[SESSION] 当前会话目录: .claude/sessions/${SID}"
echo "[SESSION] 状态文件路径: .claude/sessions/${SID}/state.md"
echo "[SESSION] 文件访问日志: .claude/sessions/${SID}/files.log"
exit 0
