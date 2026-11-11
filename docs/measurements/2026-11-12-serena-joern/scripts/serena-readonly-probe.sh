#!/usr/bin/env bash
# docs/plan.md 단계 4: 읽기 전용 설정에서 셸 실행과 파일 생성 도구를 직접 불러 거부되는지 본다.
# 사용: OPENSRE_DIR=<opensre 체크아웃> bash serena-readonly-probe.sh <출력 접두어>
set -euo pipefail
: "${OPENSRE_DIR:?OPENSRE_DIR가 필요하다}"
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
out="$1"
uv run --no-project --with mcp==2.2.0 python "$ROOT/scripts/mcp/mcp_call.py" \
  --call execute_shell_command '{"command":"touch readonly-probe-shell.txt"}' \
  --call create_text_file '{"relative_path":"readonly-probe-create.txt","content":"x"}' \
  --call replace_content '{"relative_path":"core/domain/types/evidence.py","needle":"record_evidence_entry","repl":"x","mode":"literal"}' \
  -- serena start-mcp-server \
     --context "$ROOT/config/serena/context-readonly.yml" \
     --project "$OPENSRE_DIR" \
     --agent-interface tools \
     --enable-web-dashboard False --open-web-dashboard False \
  >"$out.jsonl" 2>"$out.err"
ls "$OPENSRE_DIR"/readonly-probe-*.txt 2>/dev/null || echo "no probe files created"
git -C "$OPENSRE_DIR" status --porcelain --untracked-files=no | sed 's/^/modified: /' || true
git -C "$OPENSRE_DIR" status --porcelain --untracked-files=no | grep -q . || echo "tracked files unchanged"
