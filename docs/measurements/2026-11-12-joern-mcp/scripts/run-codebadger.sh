#!/usr/bin/env bash
# docs/plan.md 단계 5: codebadger MCP로 opensre 그래프를 만들고 3단계 Q1~Q5를 두 번씩 묻는다.
# 사용: MCP_URL=http://127.0.0.1:<터널 포트>/mcp bash run-codebadger.sh <출력 접두어>
# MCP는 Xeon 루프백에만 열려 있으므로 작업자 쪽에서 SSH 터널로 붙는다.
set -euo pipefail
: "${MCP_URL:?MCP_URL이 필요하다}"
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
out="$1"
call() { uv run --no-project -q --with mcp==2.2.0 python "$ROOT/scripts/mcp/mcp_call.py" --url "$MCP_URL" "$@"; }
field() { python3 -c "import sys,json; print(json.loads(json.loads(sys.stdin.read().strip().splitlines()[-1])['text']).get('$1'))"; }

t0=$(date +%s)
call --call generate_cpg '{"source_type":"local","source_path":"/app/playground/codebases/opensre-a5c1acbd","language":"python"}' >"$out.generate.jsonl"
hash=$(field codebase_hash <"$out.generate.jsonl")
while :; do
  call --call get_cpg_status "{\"codebase_hash\":\"$hash\"}" >"$out.status.jsonl"
  st=$(field status <"$out.status.jsonl")
  [[ "$st" == ready || "$st" == failed ]] && break
  sleep 5
done
echo "status=$st generate_to_ready_seconds=$(( $(date +%s) - t0 ))" >"$out.summary.txt"

stats='List(s"STATS files=${cpg.file.size} methods=${cpg.method.size} calls=${cpg.call.size} overlays=${cpg.metaData.overlays.l.mkString(",")} version=${cpg.metaData.version.l.mkString(",")}")'
call --call run_cpgql_query "$(python3 -c 'import json,sys; print(json.dumps({"codebase_hash":sys.argv[1],"query":sys.argv[2]}))' "$hash" "$stats")" >"$out.stats.jsonl"

args=()
while IFS=$'\t' read -r tool a; do args+=(--call "$tool" "$a"); done < <(
  python3 "$HERE/queries.py" run_cpgql_query "{\"codebase_hash\":\"$hash\",\"timeout\":300}" |
  python3 -c 'import sys,json; [print(t+"\t"+a) for t,a in json.load(sys.stdin)]')
call "${args[@]}" >"$out.queries.jsonl"
python3 - "$out" <<'PY' >>"$out.summary.txt"
import json, re, sys
out = sys.argv[1]
s = open(out + ".stats.jsonl").read()
m = re.search(r'STATS files=[0-9][^"\\]*', s); print(m.group(0) if m else "STATS 없음")
for l in open(out + ".queries.jsonl"):
    d = json.loads(l)
    if "call" not in d: continue
    m = re.search(r'RESULT [^"\\]*', d.get("text") or "")
    print(f'{m.group(0) if m else (d.get("text") or d.get("exception"))[:200]} mcp_seconds={d.get("seconds")}')
PY
cat "$out.summary.txt"
