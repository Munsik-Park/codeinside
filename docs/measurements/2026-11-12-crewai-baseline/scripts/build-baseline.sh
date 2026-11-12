#!/usr/bin/env bash
# crewAI 기준 커밋의 codebadger 그래프를 만들고 시간·자원을 기록한다 (docs/plan.md 단계 6, crewAI 기준값).
# Xeon에서 docker 그룹 계정으로 실행한다.
#   bash build-baseline.sh <codeinside 사본 루트> <출력 폴더>
# 1. 기준 커밋을 GitHub에서 받아 git archive로 playground에 푼다(<이름>-<SHA 8자리>).
# 2. 러너 네트워크의 일회용 컨테이너에서 mcp_http.py로 generate_cpg를 부르고 ready/failed까지 5초마다 상태를 본다.
# 3. 그동안 sample-load.sh로 메모리·스레드·heap을 샘플링한다.
# 4. 끝나면 codebadger 로그에서 이 그래프의 단계별 시각을 뽑고, ready면 그래프 규모를 묻는다.
set -euo pipefail
SRC="$1"; OUT="$2"
REPO=Munsik-Park/crewAI
SHA=71d68117e38f620dff02ec1dc358f37a1f74a740
NAME=crewAI-${SHA:0:8}
PG=/opt/codebadger/playground/codebases
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
if [ ! -d "$PG/$NAME" ]; then
  tmp=$(mktemp -d); git -C "$tmp" init -q; git -C "$tmp" fetch -q --depth 1 "https://github.com/$REPO" "$SHA"
  mkdir "$PG/.$NAME"; git -C "$tmp" archive --format=tar "$SHA" | tar -x -C "$PG/.$NAME"; mv "$PG/.$NAME" "$PG/$NAME"; rm -rf "$tmp"
fi
du -sm "$PG/$NAME" | awk '{print "source_mb="$1}' > "$OUT/summary.txt"
mcp() { docker run --rm --network codeinside-joern-ci -v "$SRC/scripts/mcp:/s:ro" --entrypoint python3 librechat-ci-runner:latest \
          /s/mcp_http.py --url http://codeinside-mcp-proxy:4242/mcp "$@"; }
field() { python3 -c "import sys,json; print(json.loads(json.loads(sys.stdin.read().strip().splitlines()[-1])['text']).get('$1'))"; }
bash "$HERE/sample-load.sh" "" "$OUT/sample-gen" & SPID=$!
t0=$(date +%s); echo "generate_request=$(date -u +%T)" >> "$OUT/summary.txt"
mcp --call generate_cpg "{\"source_type\":\"local\",\"source_path\":\"/app/playground/codebases/$NAME\",\"language\":\"python\",\"force\":true}" > "$OUT/generate.jsonl"
HASH=$(field codebase_hash < "$OUT/generate.jsonl"); echo "codebase_hash=$HASH" >> "$OUT/summary.txt"
kill $SPID; wait $SPID 2>/dev/null || true
bash "$HERE/sample-load.sh" "$HASH" "$OUT/sample" & SPID=$!
: > "$OUT/status.log"
while :; do
  st=$(mcp --call get_cpg_status "{\"codebase_hash\":\"$HASH\"}" | field status)
  echo "$(date -u +%T) $st" >> "$OUT/status.log"
  [ "$st" = ready ] || [ "$st" = failed ] && break
  sleep 5
done
echo "final_status=$st generate_to_final_seconds=$(( $(date +%s) - t0 ))" >> "$OUT/summary.txt"
kill $SPID; wait $SPID 2>/dev/null || true
docker logs --since "$(( $(date +%s) - t0 + 120 ))s" codebadger-mcp 2>&1 | grep "$HASH" | grep -vE 'Deps|CPGs  |python      (generating|loading)' > "$OUT/codebadger.log" || true
if [ "$st" = ready ]; then
  stats='List(s"STATS files=${cpg.file.size} methods=${cpg.method.size} calls=${cpg.call.size} overlays=${cpg.metaData.overlays.l.mkString(",")} version=${cpg.metaData.version.l.mkString(",")}")'
  mcp --call run_cpgql_query "$(python3 -c 'import json,sys; print(json.dumps({"codebase_hash":sys.argv[1],"query":sys.argv[2]}))' "$HASH" "$stats")" > "$OUT/stats.jsonl"
fi
ls -l "/opt/codebadger/playground/cpgs/$HASH/" | awk 'NR>1{print "cpg_file", $5, $9}' >> "$OUT/summary.txt"
cat "$OUT/summary.txt"
