#!/usr/bin/env bash
# ast-grep MCP와 Serena MCP를 이 체크아웃의 Claude Code에 붙인다 (docs/plan.md 단계 4).
#
# 사용: OPENSRE_DIR=<분석 대상 체크아웃> bash scripts/mcp/register.sh
#
# - 등록은 `claude mcp add --scope local`로 한다. 절대 경로가 들어간 설정은 사용자 홈의 Claude Code 설정에만
#   남고 레포에는 들어가지 않는다. 레포에는 자리 표시자만 쓴 config/mcp/mcp.example.json을 둔다.
# - 분석 대상 체크아웃에 Serena 프로젝트 설정(config/serena/project.yml)을 복사한다.
set -euo pipefail
: "${OPENSRE_DIR:?OPENSRE_DIR가 필요하다}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="$(cd "$OPENSRE_DIR" && pwd)"

# ast-grep-mcp에는 태그가 없어 커밋으로 고정한다.
AST_GREP_MCP_REV=51d5a23f025c73c02032a98748dc06942548c5e1

mkdir -p "$TARGET/.serena"
cp "$ROOT/config/serena/project.yml" "$TARGET/.serena/project.yml"

cd "$ROOT"
claude mcp remove --scope local ast-grep >/dev/null 2>&1 || true
claude mcp remove --scope local serena >/dev/null 2>&1 || true

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

claude mcp list
