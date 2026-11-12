#!/usr/bin/env bash
# codeinside Joern 분석 러너 컨테이너의 entrypoint (docs/plan.md 단계 6).
# librechat 러너 이미지에 전용 uid만 더한 이미지(build-runner-image.sh)를 쓰고 entrypoint는 이 파일로 바꾼다(supervisor가 읽기 전용으로 마운트).
# 등록 토큰($1)으로 대상 레포(runner.conf의 JOERN_CI_REPO) 단위 ephemeral 러너를 등록하고, 작업 하나를 받은 뒤 끝난다.
#
# 인자: $1 등록 토큰(supervisor가 작업마다 발급, 약 1시간 유효)
# 환경 변수: JOERN_CI_REPO_URL, JOERN_CI_LABELS(기본 joern)
set -euo pipefail
REG_TOKEN="${1:?registration token required as \$1}"
REPO_URL="${JOERN_CI_REPO_URL:?JOERN_CI_REPO_URL required}"
LABELS="${JOERN_CI_LABELS:-joern}"

# 러너 이름은 작업 로그에 공개된다. 호스트 이름 대신 컨테이너 ID(컨테이너 안 hostname)를 쓴다.
RUNNER_NAME="codeinside-joern-$(hostname)"
# supervisor가 이 줄로 남은 등록을 지운다. 작업 코드보다 먼저 찍힌다.
printf 'entrypoint: registering runner %s\n' "${RUNNER_NAME}"

# 이미지에 librechat 캐시 서버 주소가 ENV로 들어 있다. 이 러너는 쓰지 않으므로 작업 환경에서 뺀다.
unset ACTIONS_RESULTS_URL

cd /actions-runner
./config.sh \
  --url "${REPO_URL}" \
  --token "${REG_TOKEN}" \
  --ephemeral \
  --disableupdate \
  --labels "${LABELS}" \
  --name "${RUNNER_NAME}" \
  --unattended \
  --replace
unset REG_TOKEN
exec ./run.sh
