# Stop hook — tmux idle-with-question 자가 차단

## 배경

각 에이전트 (back / front / review) 의 CLAUDE.md 에는 **"사용자/PM 확인이 필요해 진행이 막힐 때는 콘솔/tmux 에 질문만 띄우고 idle 로 멈추지 말 것 — 즉시 `messages/pm/` 으로 메시지 보낼 것"** 이라는 규칙이 있다 (예: back CLAUDE.md L40, L43, L54).

그러나 실제 운영에서 모델이 이 규칙을 미끄러뜨려 tmux 에 "이대로 진행해도 될까요?" 같은 질문을 띄운 채 idle 로 멈추는 사례 발생. PM 워처는 `messages/pm/` 만 감시하므로 tmux idle 은 사람이 알아채 줄 때까지 무한 대기 → 실시간성 손실.

이 문서는 Claude Code Stop hook 으로 해당 패턴을 감지하고 self-remediation 을 강제하는 안전망 설정을 정의한다. 본질 해결 (CLAUDE.md 룰 가시성 강화) 은 별개로 진행하되, 모델이 또 미끄러질 때 잡아주는 백업 레이어.

## 작동 원리

Claude Code Stop hook 은 에이전트가 턴을 종료하려는 시점에 발동한다. JSON 입력으로 `transcript_path` (현 세션의 메시지 로그) 와 `stop_hook_active` (이미 hook 루프 안인지) 를 받는다. 출력으로 `{"decision":"block","reason":"..."}` 를 내면 종료가 차단되고 `reason` 이 모델 컨텍스트로 들어가 다음 턴 강제 진행. exit 0 이면 정상 종료.

이 hook 은:

1. 마지막 assistant 텍스트 메시지에 사용자/PM 향 **질문 패턴** (`?`, `습니까`, `할까요`, `어느 쪽`, `확인 부탁`, `PM에게`, `보낼까`) 이 있는지 검사
2. 이번 턴에 `Write` 도구로 `messages/pm/` 경로에 신규 파일을 만들었는지 검사
3. **질문 있음 + PM 메시지 작성 없음** → 종료 차단 + remediation 안내
4. `stop_hook_active=true` 면 즉시 exit 0 (무한 루프 방지 안전망)

## 설치

### 1. 스크립트 — `.claude/hooks/check-pm-question.sh`

스크립트 본체는 같은 디렉토리의 [`hooks/check-pm-question.sh`](hooks/check-pm-question.sh) 에 동봉. 그대로 워크트리의 `.claude/hooks/` 로 복사하면 됨.

```bash
# 예: back 워크트리에 적용
mkdir -p object_storage_for_tools_back/.claude/hooks
cp llm-comm-docs/setting_example/hooks/check-pm-question.sh \
   object_storage_for_tools_back/.claude/hooks/
chmod +x object_storage_for_tools_back/.claude/hooks/check-pm-question.sh
```

`chmod +x` 가 권한상 막혀 있는 환경이면, settings.json 에서 hook 호출을 `bash <script>` 형태로 적어 실행 비트 의존을 우회 (아래 settings.json 예시 참조).

스크립트는 `jq` 와 `grep` 에 의존. `jq` 는 대부분 설치돼 있음. 없으면 `sudo apt install -y jq`.

### 2. settings.json 병합

워크트리 루트의 `.claude/settings.json` 에 다음 hook 추가. 기존 `Stop` 항목이 있으면 array 에 append, 없으면 신설:

실행 비트가 있는 경우:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/check-pm-question.sh" }
        ]
      }
    ]
  }
}
```

실행 비트 없이 `bash` 로 호출하는 경우 (chmod 막힌 환경):

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/check-pm-question.sh" }
        ]
      }
    ]
  }
}
```

기존 `permissions.allow` 에 `Bash(*)` 가 있으면 추가 권한 불필요.

## 검증 시나리오 (설치 직후 1회)

1. **차단 동작**: 임시 응답에 `?` 만 끝에 두고 종료 시도 → block 떠야 함. block 메시지 보고 모델이 messages/pm/ 작성 후 통과하는지 확인.
2. **정상 통과**: 질문 없는 일반 마무리 (예: "작업 완료. push 됨.") → 통과.
3. **메시지 동시 작성**: 질문 + 같은 턴에 messages/pm/ Write 동시 발생 → 통과 (정상).
4. **무한 루프 방지**: 차단된 직후 다음 stop 시도 → `stop_hook_active=true` 로 즉시 exit 0.

각 시나리오 PASS 확인 후 commit. 검증 중에 임시로 추가한 테스트 메시지 / 파일은 모두 정리.

## False positive / 회피 위험

- **자기-수사형 의문문**: "테스트 깨졌나? 재실행 중." 같은 사례. 실 운영에선 거의 안 나옴. 발생 시 정규식 조정.
- **모델이 패턴 회피**: 의도적으로 질문을 평서문화 ("승인 필요합니다.") → regex 우회. 80% 케이스 잡는 안전망으로 충분히 가치 있음. 회피가 잦아지면 LLM judge 로 업그레이드.
- **PM 메시지 작성했지만 콘솔에도 또 질문**: pm_write 흔적 검사로 통과해 버림 (현재 한계). 후속 개선 여지: "messages/pm/ Write 후에도 콘솔 질문 남기면 차단" — 일단 단순 형태로 시작.

## 적용 대상 — 일단 back 만

본 hook 은 인시던트가 발생한 **back 부터 적용**. 효과 관찰 후 front / review 로 확장.

- back: 우선 적용 권장 (인시던트 발생)
- front: 미적용 — front 도 "묻고 idle" 패턴 발견 시 적용
- review: 미적용 — 동일 기준
- pm: **적용 금지** — PM 은 사용자 질문이 정상 흐름 (이슈 합의, 결정 받기 등)

## 본질 해결 (병행 권장)

이 hook 은 안전망이지 본질 해결이 아니다. 본질은 **CLAUDE.md 룰을 모델이 무시하지 않게** 만드는 것:

1. 해당 룰을 CLAUDE.md **최상단** 으로 이동 (현재 L40, L43, L54 분산)
2. **자가 체크리스트** 형태로 재작성 — "응답 종료 직전: 콘솔/tmux 에 질문이 있는가? 있다면 messages/pm/ 으로 옮겼는가?" 라는 자기 점검 단계를 명시
3. 짧은 단일 단락에 핵심 룰 압축 — "잘못된 패턴 / 올바른 패턴" 대비

이 둘을 같이 적용하면 hook 발동 빈도 자체가 낮아진다. hook 은 그래도 미끄러질 때를 위한 보험.
