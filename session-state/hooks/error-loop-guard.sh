#!/bin/bash
# PostToolUseFailure hook (Bash only)：同一个真失败(exit≠0)本会话累计 3 次 -> 注入 [HOOK:ERROR_LOOP] 提醒。
#
# 为什么注册在 PostToolUseFailure（而非旧的 PostToolUse）：
#   实证 dump 确认——Bash 命令 exit≠0 走 PostToolUseFailure，stdin 带 .error 字段(="Exit code N\n<stderr>")；
#   命令 exit0 走 PostToolUse(.tool_response 是 {stdout,stderr,...} 对象，无 exit_code)。
#   旧版误注册在 PostToolUse，只能 grep 成功命令输出里的 error 字样 → 既误报(成功命令含error字样)又漏报(真失败它收不到)。
# 失败判定：不再 grep 输出文本。能进到 PostToolUseFailure 本身 = 命令真失败（零误报）。
# 去重：error_fp.py 把 .error 归一化成指纹，同指纹累计；不同的失败各自计数，互不干扰。
INPUT=$(cat)
SID=$(echo "$INPUT" | jq -r '.session_id' | cut -c1-8)
DIR="${CLAUDE_PROJECT_DIR}/.claude/sessions/${SID}"
mkdir -p "$DIR"

TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
[ "$TOOL" != "Bash" ] && exit 0

# 用户主动中断(Ctrl+C)的命令不算"踩坑循环"
INTR=$(echo "$INPUT" | jq -r '.is_interrupt // false')
[ "$INTR" = "true" ] && exit 0

ERR=$(echo "$INPUT" | jq -r '.error // ""')
[ -z "$ERR" ] && exit 0

OUT=$(printf '%s' "$ERR" | python "${CLAUDE_PROJECT_DIR}/.claude/hooks/error_fp.py" "$DIR")
COUNT=$(printf '%s' "$OUT" | cut -f1)
SUMMARY=$(printf '%s' "$OUT" | cut -f2-)

# 指纹太短没输出 / 非数字 -> 跳过
case "$COUNT" in ''|*[!0-9]*) exit 0 ;; esac

if [ "$COUNT" -ge 3 ]; then
  rm -f "$DIR/error.fps"   # 重置，避免连环提醒
  jq -n --arg s "$SUMMARY" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUseFailure",
      "additionalContext": ("[HOOK:ERROR_LOOP] 同一个失败本会话已累计 3 次：「" + $s + "」。按 CLAUDE.md 规程：停止重试相同方案，分析三次失败的共同根因，重读相关文档，写出新方案后等用户确认再执行。")
    }
  }'
fi
exit 0
