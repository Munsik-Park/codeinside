#!/usr/bin/env bash
# codebadger 이미지 빌드가 남긴 BuildKit 캐시만 지운다 (docs/plan.md 단계 5).
# Xeon의 Docker 데몬은 CI 러너와 함께 쓰므로 전체 prune을 하지 않는다.
#
# 사용: bash prune-codebadger-buildcache.sh <생성일 접두어, 예: 2026-11-11> [--dry-run]
# 고르는 기준: 생성일이 주어진 날짜이고, 설명이 codebadger Dockerfile(Dockerfile, Dockerfile.mcp)의 단계나
# 그 베이스 이미지(eclipse-temurin:21-jdk-noble, python:3.13-slim) 또는 빌드 컨텍스트인 레코드.
# 지우기 전에 고른 목록을 출력한다.
set -euo pipefail
day="$1"; dry="${2:-}"
pat='rustup|joern|JOERN|eclipse-temurin:21-jdk-noble|python:3\.13-slim|requirements\.txt|DOCKER_CLI|main\.py config\.example|config\.example\.yaml|COPY src|cargo|/entrypoint|/playground|/app/logs|WORKDIR /app|local source for (dockerfile|context)|apt-get update && apt-get install -y'
select_ids() { docker buildx du --verbose | python3 -c '
import re, sys
day, pat = sys.argv[1], re.compile(sys.argv[2])
for r in sys.stdin.read().split("\n\n"):
    g = lambda k: (re.search(rf"^{k}:\s+(.*)$", r, re.M) or [None, ""])[1].strip()
    if g("ID") and g("Created at").startswith(day) and pat.search(g("Description")):
        print(g("ID"), g("Size"), g("Description")[:80], sep="\t", file=sys.stderr)
        print(g("ID"))
' "$day" "$pat"; }
ids=$(select_ids)
echo "selected $(echo "$ids" | grep -c .) records"
[[ "$dry" == --dry-run ]] && exit 0
# 자식 레코드가 남아 있으면 부모는 지워지지 않으므로, 남은 레코드가 줄지 않을 때까지 반복한다.
prev=-1
for pass in $(seq 1 20); do
  for id in $ids; do docker buildx prune -f --filter "id=$id" >/dev/null; done
  ids=$(select_ids 2>/dev/null)
  n=$(echo "$ids" | grep -c . || true)
  echo "pass $pass: $n records left"
  [[ "$n" == 0 || "$n" == "$prev" ]] && break
  prev=$n
done
echo "remaining build cache: $(docker buildx du | tail -1)"
