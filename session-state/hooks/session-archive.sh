#!/bin/bash
# SessionEnd hook: if session dir still exists (not cleared by /session-clear), archive to history
INPUT=$(cat)
SID=$(echo "$INPUT" | jq -r '.session_id' | cut -c1-8)
DIR="${CLAUDE_PROJECT_DIR}/.claude/sessions/${SID}"
HISTORY="${CLAUDE_PROJECT_DIR}/.claude/sessions/history"

[ ! -d "$DIR" ] && exit 0
mkdir -p "$HISTORY"
mv "$DIR" "$HISTORY/${SID}" 2>/dev/null
exit 0
