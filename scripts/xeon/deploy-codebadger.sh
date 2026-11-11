#!/usr/bin/env bash
# codebadger v0.7.0-beta를 Xeon에 올린다 (docs/plan.md 단계 5).
#
# 실행: Xeon에서 docker 그룹 계정으로
#   CB_DIR=<설치 폴더> bash deploy-codebadger.sh <codeinside 체크아웃 또는 config/codebadger 사본 폴더>
# 전제: $CB_DIR/.env가 있다(config/codebadger/env.example 참고, 커밋하지 않음).
# JOERN_680=1이면 이미지의 Joern을 4.0.594에서 4.0.680으로 바꾸는 패치도 적용한다.
set -euo pipefail
: "${CB_DIR:?CB_DIR가 필요하다}"
SRC="$1"
TAG=v0.7.0-beta
if [[ ! -d "$CB_DIR/.git" ]]; then
  git clone -q --depth 1 --branch "$TAG" https://github.com/Lekssays/codebadger.git "$CB_DIR"
fi
cd "$CB_DIR"
git checkout -q "$TAG" -- .
git apply "$SRC/codebadger-v0.7.0-beta.patch"
if [[ "${JOERN_680:-0}" == 1 ]]; then git apply "$SRC/codebadger-joern-4.0.680.patch"; fi
grep -E '^ENV JOERN_VERSION=' Dockerfile
cp "$SRC/docker-compose.override.yml" docker-compose.override.yml
test -f .env || { echo ".env가 없다" >&2; exit 1; }
set -a; . ./.env; set +a
mkdir -p playground/codebases playground/cpgs logs
docker compose build
docker compose up -d
# 그래프 생성 컨테이너의 메모리 노드 고정(compose에는 cpuset_mems가 없다)
docker update --cpuset-cpus "$JOERN_WORKER_CPUSET_CPUS" --cpuset-mems "$JOERN_WORKER_CPUSET_MEMS" codebadger-joern-server
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${MCP_PORT:-4242}/health" >/dev/null 2>&1; then break; fi
  sleep 2
done
curl -fsS "http://127.0.0.1:${MCP_PORT:-4242}/health"; echo
