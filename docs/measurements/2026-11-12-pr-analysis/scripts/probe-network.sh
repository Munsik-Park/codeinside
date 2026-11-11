#!/usr/bin/env bash
# docs/plan.md 단계 6: 러너 네트워크에서 닿는 곳과 막힌 곳, 러너·프록시 컨테이너 설정을 본다.
# Xeon에서 docker 그룹 계정으로 실행한다. 출력의 IP 주소는 <ip>로 가린다.
set -euo pipefail
NET=codeinside-joern-ci
ip_of(){ docker inspect "$1" --format "{{(index .NetworkSettings.Networks \"$2\").IPAddress}}"; }
W=$(docker ps --format '{{.Names}}' | grep -E '^codebadger-joern-[0-9a-f]{16}$' | head -1 || true)
WIP=$([ -n "$W" ] && ip_of "$W" codebadger || echo "")
MIP=$(ip_of codebadger-mcp codebadger); PIP=$(ip_of codebadger-postgres codebadger); RIP=$(ip_of codebadger-redis codebadger)
GW=$(docker network inspect $NET --format '{{(index .IPAM.Config 0).Gateway}}')
echo "== containers on $NET: $(docker network inspect $NET --format '{{range .Containers}}{{.Name}} {{end}}')"
echo "== containers on codebadger: $(docker network inspect codebadger --format '{{range .Containers}}{{.Name}} {{end}}')"
for c in codeinside-joern-runner codeinside-mcp-proxy; do
  docker inspect "$c" --format "== $c: cpuset={{.HostConfig.CpusetCpus}} mems={{.HostConfig.CpusetMems}} memory={{.HostConfig.Memory}} memory_swap={{.HostConfig.MemorySwap}} nanocpus={{.HostConfig.NanoCpus}} user={{.Config.User}} capdrop={{.HostConfig.CapDrop}} secopt={{.HostConfig.SecurityOpt}} readonly={{.HostConfig.ReadonlyRootfs}} ports={{json .HostConfig.PortBindings}}"
done
docker exec codeinside-joern-runner sh -c 'echo "== runner cgroup: cpus=$(cat /sys/fs/cgroup/cpuset.cpus.effective) mems=$(cat /sys/fs/cgroup/cpuset.mems.effective) memory.max=$(cat /sys/fs/cgroup/memory.max) cpu.max=$(cat /sys/fs/cgroup/cpu.max)"; echo "== runner env ACTIONS_RESULTS_URL (pid 1 environ): $(tr "\0" "\n" </proc/1/environ | grep -c ^ACTIONS_RESULTS_URL= || true) / Runner.Listener: $(for p in $(pgrep -f Runner.Listener); do tr "\0" "\n" </proc/$p/environ | grep -c ^ACTIONS_RESULTS_URL= ; done | head -1)"'
docker run --rm --network $NET -e WIP="$WIP" -e MIP="$MIP" -e PIP="$PIP" -e RIP="$RIP" -e GW="$GW" --entrypoint bash librechat-ci-runner:latest -c '
probe(){ [ -z "$1" ] && { echo "$3 $2: (no target)"; return; }; if timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; then echo "$3 $2: OPEN"; else echo "$3 $2: blocked"; fi; }
echo "== MCP initialize via proxy"
curl -sS -m 10 -o /tmp/b -w "http %{http_code} %{content_type}\n" -X POST http://codeinside-mcp-proxy:4242/mcp -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"probe\",\"version\":\"0\"}}}"
grep -o "\"serverInfo\":{[^}]*}" /tmp/b
echo "== reachability from a probe container on the runner network"
probe codeinside-mcp-proxy 4242 proxy; probe codeinside-mcp-proxy 8080 proxy
probe "$WIP" 8080 query-worker; probe "$MIP" 4242 codebadger-mcp-direct; probe codebadger-mcp 4242 codebadger-mcp-by-name
probe "$PIP" 5432 postgres; probe "$RIP" 6379 redis
for p in 4242 55432 56379 13371; do probe "$GW" $p host-gateway; done
curl -sS -m 10 -o /dev/null -w "github api %{http_code}\n" https://api.github.com/zen
' 2>&1
