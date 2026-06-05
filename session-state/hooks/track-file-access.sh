#!/bin/bash
# PostToolUse hook (async): log file accesses for state.md curation
INPUT=$(cat)
SID=$(echo "$INPUT" | jq -r '.session_id' | cut -c1-8)
DIR="${CLAUDE_PROJECT_DIR}/.claude/sessions/${SID}"
mkdir -p "$DIR"
touch "$DIR/.heartbeat"

TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
case "$TOOL" in
  Read|Edit|Write)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
    [ -n "$FILE" ] && echo "[$(date +%H:%M:%S)] $TOOL $FILE" >> "$DIR/files.log"
    ;;
esac
exit 0
