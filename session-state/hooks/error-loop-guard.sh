#!/bin/bash
# PostToolUse hook (sync, Bash only): on 3 consecutive failures, JSON-block Claude
INPUT=$(cat)
SID=$(echo "$INPUT" | jq -r '.session_id' | cut -c1-8)
DIR="${CLAUDE_PROJECT_DIR}/.claude/sessions/${SID}"
mkdir -p "$DIR"
COUNTER="$DIR/error.count"

TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
[ "$TOOL" != "Bash" ] && exit 0

RESULT=$(echo "$INPUT" | jq -r '.tool_response // .tool_result // "" | if type == "string" then . else tostring end')

if echo "$RESULT" | grep -qiE "(^error|error:|^fail|failed|exit code [1-9]|cannot access|no such file|command not found|permission denied)"; then
  COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER"

  if [ "$COUNT" -ge 3 ]; then
    echo "0" > "$COUNTER"
    jq -n --arg sid "$SID" '{
      "decision": "block",
      "reason": "[HOOK:ERROR_LOOP] 连续 3 次 Bash 失败，触发错误循环守卫。按 CLAUDE.md 规程：停止当前执行路径，不再重试相同方案；分析三次失败的共同根因；重新阅读任务相关文档；写出新方案后等待用户确认再执行。",
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": ("[HOOK:ERROR_LOOP] 会话目录: .claude/sessions/" + $sid)
      }
    }'
  fi
else
  echo "0" > "$COUNTER"
fi
exit 0
