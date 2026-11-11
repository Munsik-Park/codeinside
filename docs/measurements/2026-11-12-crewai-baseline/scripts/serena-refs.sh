#!/usr/bin/env bash
# docs/plan.md 단계 6(crewAI 기준값): Serena MCP 서버를 읽기 전용 설정으로 띄워 Q1, C1의 참조를 묻는다.
# 사용: CREWAI_DIR=<crewAI 체크아웃> bash serena-refs.sh <default|extrapaths> <출력 접두어>
#   default    : Pyright 설정 없이(4단계와 같은 조건)
#   extrapaths : config/serena/crewai/pyrightconfig.json을 체크아웃 루트에 둔다(lib/*/src를 import 경로에 더함)
# 두 경우 모두 .serena/project.yml은 config/serena/project.yml에서 project_name만 바꿔 둔다.
set -euo pipefail
: "${CREWAI_DIR:?CREWAI_DIR가 필요하다}"
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
mode="$1"; out="$2"
mkdir -p "$CREWAI_DIR/.serena"
sed 's/^project_name: .*/project_name: "crewAI"/' "$ROOT/config/serena/project.yml" > "$CREWAI_DIR/.serena/project.yml"
case "$mode" in
  default) rm -f "$CREWAI_DIR/pyrightconfig.json" ;;
  extrapaths) python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("//",None); json.dump(d,open(sys.argv[2],"w"),indent=2)' \
                "$ROOT/config/serena/crewai/pyrightconfig.json" "$CREWAI_DIR/pyrightconfig.json" ;;
  *) echo "mode: default|extrapaths" >&2; exit 1 ;;
esac
uv run --no-project --with mcp==2.2.0 python "$ROOT/scripts/mcp/mcp_call.py" \
  --call find_referencing_symbols '{"name_path":"BaseLLM/_emit_call_completed_event","relative_path":"lib/crewai/src/crewai/llms/base_llm.py","max_answer_chars":5000000}' \
  --call find_referencing_symbols '{"name_path":"Memory/close","relative_path":"lib/crewai/src/crewai/memory/unified_memory.py","max_answer_chars":5000000}' \
  -- serena start-mcp-server \
     --context "$ROOT/config/serena/context-readonly.yml" \
     --project "$CREWAI_DIR" \
     --agent-interface tools \
     --enable-web-dashboard False --open-web-dashboard False \
  >"$out.jsonl" 2>"$out.err"
