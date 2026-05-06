#!/bin/bash
# Stop hook: tmux idle-with-question 자가 차단
# 마지막 assistant 응답에 PM/사용자 향 질문이 있고 이번 턴에 messages/pm/ Write 가 없으면 종료 차단.
# 자세한 설명: ../stop-hook-pm-question-guard.md

set -euo pipefail
input=$(cat)
stop_hook_active=$(jq -r '.stop_hook_active // false' <<<"$input")
[[ "$stop_hook_active" == "true" ]] && exit 0   # 무한 루프 방지

transcript=$(jq -r '.transcript_path' <<<"$input")
[[ -f "$transcript" ]] || exit 0

# 마지막 assistant text 메시지 (최근 50줄)
last_assistant=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$transcript" | tail -50)

# 질문 패턴
if grep -qE '(\?|습니까|할까요|괜찮을까|어느 쪽|확인 부탁|PM에게|보낼까)' <<<"$last_assistant"; then
  # 이번 턴에 messages/pm/ 으로 Write 한 흔적
  pm_write=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Write") | .input.file_path' "$transcript" 2>/dev/null \
    | grep -F 'messages/pm/' | tail -5 || true)
  if [[ -z "$pm_write" ]]; then
    jq -n --arg reason "❌ tmux/콘솔에 PM/사용자 질문을 남기고 종료 시도. CLAUDE.md 규칙 위반 (묻고 idle 금지).
필수 조치:
1. 위 질문을 ../llm-comm-docs/messages/pm/YYYY-MM-DD-{role}-{topic}.md 파일로 옮길 것.
   frontmatter: from: {role}, to: pm, re: 관련 이슈/메시지 링크
2. 작성 후 다시 종료 시도. messages/pm/ 에 신규 파일이 있으면 통과." \
      '{decision:"block", reason:$reason}'
    exit 0
  fi
fi
exit 0
