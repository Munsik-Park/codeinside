#!/usr/bin/env bash
# docs/plan.md 단계 5: `joern --server`에 JAVA_TOOL_OPTIONS를 주면 서버 JVM의 heap 상한에 닿는지 jcmd로 본다.
# 실행: Xeon에서 joern 계정으로 (sudo -u joern -H bash server-jto-probe.sh <포트> <인증 파일>)
# 인증 파일은 "사용자:비밀번호" 한 줄이며 커밋하지 않는다.
set -euo pipefail
port="$1"; auth="$(cat "$2")"
# java_command에 인증 사용자와 비밀번호가 그대로 찍히므로 출력에서 가린다
exec > >(sed -E -e 's/(--server-auth-password )[^ ]+/\1<redacted>/g' -e 's/(--server-auth-username )[^ ]+/\1<redacted>/g') 2>&1
J=/opt/joern/current/joern-cli
cd ~
JAVA_TOOL_OPTIONS=-Xmx4G numactl --cpunodebind=3 --membind=3 \
  "$J/joern" --server --server-host 127.0.0.1 --server-port "$port" \
  --server-auth-username "${auth%%:*}" --server-auth-password "${auth#*:}" >/tmp/joern-server-probe.log 2>&1 &
for i in $(seq 1 90); do
  code="$(curl -s -o /dev/null -w '%{http_code}' -u "$auth" -X POST -H 'Content-Type: application/json' \
    -d '{"query":"1+1"}' "http://127.0.0.1:$port/query-sync" || true)"
  [[ "$code" == 200 ]] && break; sleep 2
done
echo "query-sync with auth: HTTP $code"
echo "query-sync without auth: HTTP $(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"query":"1+1"}' "http://127.0.0.1:$port/query-sync")"
echo "== JVMs of this user"
for pid in $(jps -q); do
  cmd="$(jcmd "$pid" VM.command_line 2>/dev/null | grep -E '^java_command' || true)"
  [[ -z "$cmd" || "$cmd" == *Jps* ]] && continue
  echo "pid=$pid $cmd"
  jcmd "$pid" VM.flags | tr ' ' '\n' | grep -E 'MaxHeapSize'
  grep -E 'Cpus_allowed_list' "/proc/$pid/status"
  # numactl --membind는 cpuset이 아니라 메모리 정책으로 걸리므로 numa_maps의 정책을 센다
  echo "numa_maps policy: $(awk '{print $2}' "/proc/$pid/numa_maps" | sort | uniq -c | tr '\n' ' ')"
  echo "numa_maps pages on node: $(grep -oE 'N[0-9]+=[0-9]+' "/proc/$pid/numa_maps" | awk -F'[N=]' '{a[$2]+=$3} END{for(n in a) printf "N%s=%d ", n, a[n]}')"
done
echo "== listening"
ss -ltnH | awk '{print $4}' | grep -E ":$port\$"
head -3 /tmp/joern-server-probe.log
pkill -u "$(id -u)" -f "joern-cli.*--server-port $port" || true
sleep 2
echo "remaining joern servers: $(pgrep -u "$(id -u)" -fc 'ReplBridge --server' || true)"
