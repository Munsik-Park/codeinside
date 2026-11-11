#!/usr/bin/env bash
# docs/plan.md 단계 5: Claude Code 작업 세션(헤드리스)에서 Joern MCP(codebadger), ast-grep MCP, Serena MCP를 직접 부른다.
# 사용: OPENSRE_DIR=<opensre 체크아웃> MCP_URL=http://127.0.0.1:<터널 포트>/mcp CODEBASE_HASH=<hash> bash run-session.sh <출력 파일>
# --strict-mcp-config로 이 세 서버만 붙이고, 내장 도구는 끈다(--tools "").
set -euo pipefail
: "${OPENSRE_DIR:?}"; : "${MCP_URL:?}"; : "${CODEBASE_HASH:?}"
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
TARGET="$(cd "$OPENSRE_DIR" && pwd)"
cfg="$(mktemp)"; trap 'rm -f "$cfg"' EXIT
cat >"$cfg" <<JSON
{"mcpServers": {
  "joern": {"type": "http", "url": "$MCP_URL"},
  "ast-grep": {"type": "stdio", "command": "uvx",
    "args": ["--from", "git+https://github.com/ast-grep/ast-grep-mcp@51d5a23f025c73c02032a98748dc06942548c5e1", "ast-grep-server"]},
  "serena": {"type": "stdio", "command": "serena",
    "args": ["start-mcp-server", "--context", "$ROOT/config/serena/context-readonly.yml", "--project", "$TARGET",
             "--agent-interface", "tools", "--enable-web-dashboard", "False", "--open-web-dashboard", "False"]}
}}
JSON
prompt="Use only MCP tools. Do the following three steps and report the raw numbers.
1. Joern MCP: call run_cpgql_query with codebase_hash \"$CODEBASE_HASH\" and this query, unchanged:
{ def source = cpg.method.fullNameExact(\".github/ci/git_changes.py:<module>.git\").parameter; def sink = cpg.call.methodFullNameExact(\"subprocess.py:<module>.check_output\").argument; sink.reachableByFlows(source).map(_.elements.map(e => s\"\${e.code}@\${e.lineNumber.getOrElse(-1)}\").mkString(\" -> \")).l }
   Report how many flows came back and list each flow path.
2. ast-grep MCP: call find_code with project_folder \"$TARGET\", language python, pattern record_evidence_entry(\$\$\$). Report the total match count the tool prints.
3. Serena MCP: call find_referencing_symbols with name_path record_evidence_entry and relative_path core/domain/types/evidence.py. Report how many files and how many referencing symbols came back.
Do not guess; if a call fails, report the error text."
cd "$ROOT"
MCP_TIMEOUT=120000 claude -p "$prompt" \
  --mcp-config "$cfg" --strict-mcp-config \
  --tools "" \
  --allowedTools "mcp__joern__run_cpgql_query" "mcp__ast-grep__find_code" "mcp__serena__find_referencing_symbols" \
  --output-format stream-json --verbose --max-budget-usd 3 >"$1"
