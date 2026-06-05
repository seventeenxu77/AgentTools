#!/bin/bash
# PostToolUse hook (sync): real-token-based context warning, model-aware
# Reads model from transcript, looks up context window, warns at 70%
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
SID=$(echo "$INPUT" | jq -r '.session_id' | cut -c1-8)
DIR="${CLAUDE_PROJECT_DIR}/.claude/sessions/${SID}"
mkdir -p "$DIR"

[ ! -f "$TRANSCRIPT" ] && exit 0

LAST_ASSISTANT=$(grep '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null | tail -1)
[ -z "$LAST_ASSISTANT" ] && exit 0

MODEL=$(echo "$LAST_ASSISTANT" | jq -r '.message.model // ""')
TOKENS=$(echo "$LAST_ASSISTANT" | jq -r '(.message.usage.input_tokens // 0) +
                                          (.message.usage.cache_creation_input_tokens // 0) +
                                          (.message.usage.cache_read_input_tokens // 0)' 2>/dev/null)

[ -z "$TOKENS" ] || [ "$TOKENS" = "null" ] && exit 0

# model -> context window (tokens)
# 加新模型时按"长 → 短"顺序加 case，避免短 pattern 抢先匹配
case "$MODEL" in
  *opus-4-8*|*opus-4.8*)      MAX=1000000 ;;
  *opus-4-7*|*opus-4.7*)      MAX=1000000 ;;
  *opus-4-6*|*opus-4.6*)      MAX=200000  ;;
  *sonnet-4-6*|*sonnet-4.6*)  MAX=200000  ;;
  *haiku-4-5*|*haiku-4.5*)    MAX=200000  ;;
  *opus*)                      MAX=200000  ;;
  *sonnet*)                    MAX=200000  ;;
  *haiku*)                     MAX=200000  ;;
  *)                           MAX=200000  ;;  # 未知模型保守默认
esac

THRESHOLD=$((MAX * 70 / 100))

[ "$TOKENS" -lt "$THRESHOLD" ] && exit 0

# 60s 节流
LAST_WARN="$DIR/.last-warn"
NOW=$(date +%s)
if [ -f "$LAST_WARN" ]; then
  DIFF=$((NOW - $(cat "$LAST_WARN")))
  [ "$DIFF" -lt 60 ] && exit 0
fi
echo "$NOW" > "$LAST_WARN"

PCT=$((TOKENS * 100 / MAX))
jq -n --arg sid "$SID" --arg tokens "$TOKENS" --arg pct "$PCT" --arg model "$MODEL" --arg max "$MAX" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": ("[HOOK:CONTEXT_WARN] " + $model + " 当前 " + $tokens + " / " + $max + " tokens (~" + $pct + "%)，超过 70% 阈值。按规程：读 files.log 筛选关键文档，写 .claude/sessions/" + $sid + "/state.md，然后 /compact。")
  }
}'
exit 0
