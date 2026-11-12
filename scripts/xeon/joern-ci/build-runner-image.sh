#!/usr/bin/env bash
# 분석 러너 이미지를 만든다 (docs/plan.md 단계 6, 러너 전용 uid).
# librechat 러너 이미지 위에 호스트 전용 계정과 같은 uid/gid의 사용자를 하나 더한다.
# 러너가 PR 코드를 이 uid로 돌리므로, 호스트의 작업자 로그인 계정(uid 1000)과 겹치지 않는다.
# /actions-runner 전체를 chown하면 674MB 레이어가 하나 더 생긴다(Docker data-root가 tmpfs).
# 그래서 폴더 자체와 러너가 쓰는 _diag, _work만 새 uid 소유로 둔다. config.sh가 만드는 .runner, .credentials 등은 이 폴더에 새로 생긴다.
# Docker data-root가 tmpfs라 재부팅하면 이미지가 사라진다. codeinside-joern-ci-net.service가 부팅 때 다시 부른다.
#
# 설정: JOERN_CI_BASE_IMAGE, JOERN_CI_RUNNER_IMAGE, JOERN_CI_RUNNER_UID, JOERN_CI_RUNNER_GID
set -euo pipefail
BASE="${JOERN_CI_BASE_IMAGE:?}"
IMAGE="${JOERN_CI_RUNNER_IMAGE:?}"
UID_="${JOERN_CI_RUNNER_UID:?}"
GID_="${JOERN_CI_RUNNER_GID:?}"
docker build -q -t "$IMAGE" \
  --label "codeinside.base=$(docker image inspect "$BASE" --format '{{.Id}}')" \
  --build-arg BASE="$BASE" --build-arg RUID="$UID_" --build-arg RGID="$GID_" - <<'DOCKERFILE'
ARG BASE
FROM ${BASE}
ARG RUID
ARG RGID
USER root
RUN groupadd -g "${RGID}" jrunner \
 && useradd -u "${RUID}" -g "${RGID}" -m -d /home/jrunner -s /bin/bash jrunner \
 && mkdir -p /actions-runner/_diag /actions-runner/_work \
 && chown "${RUID}:${RGID}" /actions-runner /actions-runner/_diag /actions-runner/_work
USER jrunner
WORKDIR /actions-runner
DOCKERFILE
docker run --rm --entrypoint sh "$IMAGE" -c 'echo "image user: $(id)"; test -w /actions-runner && echo "/actions-runner writable"'
