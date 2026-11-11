#!/usr/bin/env bash
# pysrc2cpg 프런트엔드를 따로 돌려 그래프 파일을 만들고, 시간과 최대 메모리를 잰다 (docs/plan.md 단계 3).
#
# 실행: 서버에서 joern 계정으로 실행한다.
#   sudo -u joern -H bash measure-frontend.sh <label> <xmx> <numa-node> <input-dir> [pysrc2cpg 추가 인자...]
# 예:
#   sudo -u joern -H bash measure-frontend.sh core 8G 3 ~/src/opensre/core
#   sudo -u joern -H bash measure-frontend.sh full 32G 3 ~/src/opensre --exclude tests
#
# 결과: ~/measure/<label>-<xmx>.log (GNU time -v 출력 포함), ~/cpg/<label>.bin
set -euo pipefail

label="$1"; xmx="$2"; node="$3"; input="$4"; shift 4
J=/opt/joern/current/joern-cli
out="$HOME/cpg/${label}.bin"
log="$HOME/measure/${label}-${xmx}.log"
mkdir -p "$HOME/cpg" "$HOME/measure"
rm -f "$out"

{
  echo "label=${label} xmx=${xmx} numa_node=${node} input=${input} extra=$*"
  echo "commit=$(git -C "$input" rev-parse HEAD 2>/dev/null || true)"
  echo "start=$(date -u +%FT%TZ)"
  set +e
  numactl --cpunodebind="$node" --membind="$node" \
    /usr/bin/time -v "$J/pysrc2cpg" "-J-Xmx${xmx}" "$input" -o "$out" "$@"
  rc=$?
  set -e
  echo "end=$(date -u +%FT%TZ)"
  echo "exit=${rc}"
  if [[ -f "$out" ]]; then
    echo "cpg_bytes=$(stat -c %s "$out")"
  else
    echo "cpg_bytes=none"
  fi
} >"$log" 2>&1
tail -n 3 "$log"
