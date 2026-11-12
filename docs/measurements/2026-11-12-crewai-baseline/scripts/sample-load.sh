#!/usr/bin/env bash
# crewAI 기준 그래프의 생성·적재 중 자원 사용을 샘플링한다 (docs/plan.md 단계 6, crewAI 기준값).
# Xeon에서 docker 그룹 계정으로 실행한다. 멈출 때까지(SIGTERM) 돈다.
#   bash sample-load.sh <codebase_hash 또는 빈 값> <출력 접두어>
# 출력:
#   <접두어>.mem.tsv     1초마다: 시각, 생성 컨테이너 memory.current, 워커 컨테이너 memory.current
#   <접두어>.threads.log 2초마다: 워커 JVM 스레드 중 CPU 상위 6개(top -H, 1초 간격 두 번째 측정값)
#   <접두어>.gen.log     2초마다: 생성 컨테이너 안 java 프로세스(RSS, CPU%, 스레드 수)
#   <접두어>.heap.log    10초마다: 워커 JVM GC.heap_info
# 컨테이너 cgroup의 memory.peak는 컨테이너가 뜬 뒤 누적값이고 이 커널(6.8)에서는 되돌릴 수 없어서 memory.current를 샘플링한다.
set -uo pipefail
HASH="${1:-}"
OUT="$2"
GEN=codebadger-joern-server
cg() { local id; id=$(docker inspect "$1" --format '{{.Id}}' 2>/dev/null) || return 1; echo "/sys/fs/cgroup/system.slice/docker-$id.scope"; }
GEN_CG=$(cg $GEN)
printf 'time\tgen_mem_current\tworker_mem_current\n' > "$OUT.mem.tsv"
: > "$OUT.threads.log"; : > "$OUT.gen.log"; : > "$OUT.heap.log"
worker_cg=""; n=0
trap 'exit 0' TERM INT
while :; do
  ts=$(date -u +%T)
  W="codebadger-joern-${HASH}"
  if [ -n "$HASH" ] && [ -z "$worker_cg" ]; then worker_cg=$(cg "$W" || true); fi
  if [ -n "$worker_cg" ] && [ ! -d "$worker_cg" ]; then worker_cg=$(cg "$W" || true); fi
  wm=$([ -n "$worker_cg" ] && cat "$worker_cg/memory.current" 2>/dev/null || echo "")
  printf '%s\t%s\t%s\n' "$ts" "$(cat "$GEN_CG/memory.current")" "$wm" >> "$OUT.mem.tsv"
  if (( n % 2 == 0 )); then
    gp=$(for p in $(cat "$GEN_CG/cgroup.procs"); do [ "$(cat /proc/$p/comm 2>/dev/null)" = java ] && echo $p; done | paste -sd, -)
    [ -n "$gp" ] && ps -o pid=,rss=,pcpu=,nlwp=,etimes= -p "$gp" | sed "s/^/$ts gen /" >> "$OUT.gen.log"
    if [ -n "$worker_cg" ] && [ -d "$worker_cg" ]; then
      wp=$(for p in $(cat "$worker_cg/cgroup.procs"); do [ "$(cat /proc/$p/comm 2>/dev/null)" = java ] && echo $p; done | head -1)
      if [ -n "$wp" ]; then
        { echo "== $ts pid=$wp"; top -H -b -n 2 -d 1 -p "$wp" | awk '/^top -/{blk++} blk==2 && $1 ~ /^[0-9]+$/ {print}' | sort -k9 -nr | head -6; } >> "$OUT.threads.log"
        if (( n % 10 == 0 )); then
          { echo "== $ts"; docker exec "$W" sh -c 'jcmd $(pgrep -o java) GC.heap_info' 2>&1 | grep -E 'garbage-first heap|Metaspace'; } >> "$OUT.heap.log"
        fi
      fi
    fi
  fi
  n=$((n+1)); sleep 1
done
