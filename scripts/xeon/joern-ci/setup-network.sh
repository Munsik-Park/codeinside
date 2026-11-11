#!/usr/bin/env bash
# opensre 분석 러너용 네트워크와 MCP 프록시 컨테이너를 만든다 (docs/plan.md 단계 6, 연결 방식 A).
#
#   러너 컨테이너 ── JOERN_CI_NETWORK ── 프록시 컨테이너 ── codebadger 네트워크 ── codebadger-mcp:4242
#
# 러너는 codebadger 네트워크에 붙지 않으므로 인증 없는 질의 워커, Postgres, Redis에 닿지 않는다.
# 프록시는 codebadger-mcp:4242 한 곳으로만 넘긴다(tcp_proxy.py).
# Docker data-root가 tmpfs라 재부팅하면 네트워크와 컨테이너가 사라진다. 부팅 때 codeinside-joern-ci-net.service가 다시 부른다.
# 여러 번 불러도 결과가 같다.
#
# 설정(환경 변수, /etc/codeinside-joern-ci/runner.conf):
#   JOERN_CI_NETWORK, JOERN_CI_PROXY_NAME, JOERN_CI_PROXY_IMAGE, JOERN_CI_PROXY_SCRIPT,
#   JOERN_CI_CPUSET_CPUS, JOERN_CI_CPUSET_MEMS, CODEBADGER_NETWORK
set -euo pipefail
NET="${JOERN_CI_NETWORK:-codeinside-joern-ci}"
PROXY="${JOERN_CI_PROXY_NAME:-codeinside-mcp-proxy}"
IMAGE="${JOERN_CI_PROXY_IMAGE:-codebadger-mcp:latest}"
SCRIPT="${JOERN_CI_PROXY_SCRIPT:?JOERN_CI_PROXY_SCRIPT(tcp_proxy.py 경로)가 필요하다}"
CB_NET="${CODEBADGER_NETWORK:-codebadger}"
CPUS="${JOERN_CI_CPUSET_CPUS:-30-39,70-79}"
MEMS="${JOERN_CI_CPUSET_MEMS:-3}"

docker network inspect "$NET" >/dev/null 2>&1 || docker network create --driver bridge "$NET" >/dev/null
docker network inspect "$CB_NET" >/dev/null   # codebadger 스택이 먼저 떠 있어야 한다

if docker container inspect "$PROXY" >/dev/null 2>&1; then
  docker rm -f "$PROXY" >/dev/null
fi
docker run -d --name "$PROXY" --restart unless-stopped \
  --network "$NET" \
  --memory 128m --memory-swap 128m --cpus 1 \
  --cpuset-cpus "$CPUS" --cpuset-mems "$MEMS" \
  --read-only --cap-drop ALL --security-opt no-new-privileges \
  --user 65534:65534 \
  -v "$SCRIPT:/proxy/tcp_proxy.py:ro" \
  --entrypoint python3 \
  "$IMAGE" /proxy/tcp_proxy.py >/dev/null
docker network connect "$CB_NET" "$PROXY"
echo "network=$NET proxy=$PROXY networks=$(docker inspect "$PROXY" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}')"
