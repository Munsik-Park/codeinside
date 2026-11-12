#!/usr/bin/env bash
# ast-grep MCP, Serena MCP, Joern(codebadger) MCP를 이 체크아웃의 Claude Code에 붙인다 (docs/plan.md 단계 4~6).
#
# 사용: TARGET_DIR=<분석 대상 체크아웃> [PROJECT_NAME=<이름>] [PYRIGHTCONFIG=<Pyright 설정>] [JOERN_MCP_URL=<주소>] \
#         bash scripts/mcp/register.sh
#
# - TARGET_DIR(필수): 분석 대상 체크아웃. Serena가 이 폴더를 프로젝트로 연다.
# - PROJECT_NAME(선택): Serena project_name. 기본은 TARGET_DIR 폴더 이름.
# - PYRIGHTCONFIG(선택): 체크아웃 루트에 pyrightconfig.json으로 복사할 Pyright 설정. "//" 키(주석)는 빼고 쓴다.
# - JOERN_MCP_URL(선택): 있으면 joern을 streamable HTTP MCP로 등록한다.
# - 등록은 `claude mcp add --scope local`로 한다. 절대 경로가 들어간 설정은 사용자 홈의 Claude Code 설정에만
#   남고 레포에는 들어가지 않는다. 레포에는 자리 표시자만 쓴 config/mcp/mcp.example.json을 둔다.
# - 같은 이름이 있으면 `claude mcp add`가 실패하므로 ast-grep, serena, joern을 먼저 지운다.
set -euo pipefail
: "${TARGET_DIR:?TARGET_DIR가 필요하다}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="$(cd "$TARGET_DIR" && pwd)"
NAME="${PROJECT_NAME:-$(basename "$TARGET")}"

# ast-grep-mcp에는 태그가 없어 커밋으로 고정한다.
AST_GREP_MCP_REV=51d5a23f025c73c02032a98748dc06942548c5e1

mkdir -p "$TARGET/.serena"
NAME="$NAME" python3 -c 'import json,os,sys
s = open(sys.argv[1], encoding="utf-8").read()
lines = [("project_name: " + json.dumps(os.environ["NAME"])) if l.startswith("project_name:") else l
         for l in s.splitlines()]
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(lines) + "\n")' \
  "$ROOT/config/serena/project.yml" "$TARGET/.serena/project.yml"

if [ -n "${PYRIGHTCONFIG:-}" ]; then
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); d.pop("//", None)
json.dump(d, open(sys.argv[2], "w"), indent=2)' "$PYRIGHTCONFIG" "$TARGET/pyrightconfig.json"
fi

cd "$ROOT"
for s in ast-grep serena joern; do
  claude mcp remove --scope local "$s" >/dev/null 2>&1 || true
done

# ast-grep-mcp README "Running with uvx"
claude mcp add --scope local ast-grep -- \
  uvx --from "git+https://github.com/ast-grep/ast-grep-mcp@${AST_GREP_MCP_REV}" ast-grep-server

# Serena docs/02-usage/030_clients.md "Claude Code" (Per-Project Configuration)에 읽기 전용 설정을 더했다.
claude mcp add --scope local serena -- \
  serena start-mcp-server \
    --context "$ROOT/config/serena/context-readonly.yml" \
    --project "$TARGET" \
    --agent-interface tools \
    --enable-web-dashboard False --open-web-dashboard False

if [ -n "${JOERN_MCP_URL:-}" ]; then
  claude mcp add --scope local --transport http joern "$JOERN_MCP_URL"
fi

claude mcp list
