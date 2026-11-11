#!/usr/bin/env bash
# docs/plan.md 단계 4: Serena MCP 서버를 읽기 전용 설정으로 띄워 참조를 묻는다.
# 사용: OPENSRE_DIR=<opensre 체크아웃> bash serena-refs.sh <출력 접두어>
# 결과: <접두어>.jsonl(tools/list와 응답), <접두어>.err(Serena 로그). 경로는 기록 전에 sanitize.sh로 바꾼다.
set -euo pipefail
: "${OPENSRE_DIR:?OPENSRE_DIR가 필요하다}"
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
out="$1"
uv run --no-project --with mcp==2.2.0 python "$ROOT/scripts/mcp/mcp_call.py" \
  --call find_referencing_symbols '{"name_path":"record_evidence_entry","relative_path":"core/domain/types/evidence.py","max_answer_chars":5000000}' \
  --call find_referencing_symbols '{"name_path":"SessionManager/close","relative_path":"core/agent_harness/session/lifecycle.py","max_answer_chars":5000000}' \
  -- serena start-mcp-server \
     --context "$ROOT/config/serena/context-readonly.yml" \
     --project "$OPENSRE_DIR" \
     --agent-interface tools \
     --enable-web-dashboard False --open-web-dashboard False \
  >"$out.jsonl" 2>"$out.err"
