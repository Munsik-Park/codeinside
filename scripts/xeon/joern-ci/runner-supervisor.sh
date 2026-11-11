#!/usr/bin/env bash
# opensre 분석 러너 supervisor (docs/plan.md 단계 6). codeinside-joern-runner.service가 띄운다.
# librechat 러너 supervisor와 같은 ephemeral 방식이다.
#   1. PAT로 opensre 레포 단위 등록 토큰을 발급한다(작업마다, 저장하지 않음).
#   2. 러너 컨테이너 하나를 띄운다: 노드 3 cpuset·메모리 노드, 메모리 상한, non-root, 프록시 네트워크.
#   3. 컨테이너가 작업 하나를 끝내고 지워지면, 남은 등록이 있으면 지우고 1로 돌아간다.
#
# 필수 환경 변수: RUNNER_REG_PAT (/etc/codeinside-joern-ci/runner.env, 권한 600, 커밋하지 않음)
# 설정: /etc/codeinside-joern-ci/runner.conf (config/joern-ci/runner.conf.example)
set -euo pipefail
: "${RUNNER_REG_PAT:?RUNNER_REG_PAT must be set}"
REPO="${JOERN_CI_REPO:?JOERN_CI_REPO must be set}"
IMAGE="${JOERN_CI_RUNNER_IMAGE:?}"
NET="${JOERN_CI_NETWORK:?}"
MEMORY="${JOERN_CI_RUNNER_MEMORY:?}"
CPUS="${JOERN_CI_RUNNER_CPUS:?}"
CPUSET_CPUS="${JOERN_CI_CPUSET_CPUS:?}"
CPUSET_MEMS="${JOERN_CI_CPUSET_MEMS:?}"
ENTRYPOINT="${JOERN_CI_ENTRYPOINT:?}"
SRC_HOST_DIR="${JOERN_CI_SRC_HOST_DIR:?}"
SRC_MCP_DIR="${JOERN_CI_SRC_MCP_DIR:?}"
MCP_URL="${JOERN_CI_MCP_URL:?}"
CONTAINER="${JOERN_CI_RUNNER_NAME:-codeinside-joern-runner}"

log() { printf '[%s] joern-runner-supervisor: %s\n' "$(date -u +%FT%TZ)" "$*"; }
stop_container() { docker stop -t 30 "${CONTAINER}" >/dev/null 2>&1 || true; }
RUN_LOG="$(mktemp "${TMPDIR:-/tmp}/codeinside-joern-runner.XXXXXX")"
trap 'log "stopping on signal"; stop_container; wait; rm -f "${RUN_LOG}"; exit 0' TERM INT

github_api() {
  curl -fsS -H "Authorization: Bearer ${RUNNER_REG_PAT}" -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}
mint_registration_token() {
  github_api -X POST "https://api.github.com/repos/${REPO}/actions/runners/registration-token" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
}
# ephemeral 러너는 작업을 끝냈을 때만 등록을 지운다. 작업 없이 끝난 컨테이너의 등록은 여기서 지운다.
remove_leftover_registration() {
  local name id
  name="$(sed -n 's/^entrypoint: registering runner \(codeinside-joern-[A-Za-z0-9._-]*\)$/\1/p' "${RUN_LOG}" | head -1)"
  [ -n "${name}" ] || return 0
  id="$(github_api "https://api.github.com/repos/${REPO}/actions/runners?name=${name}" \
    | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runners"] if not x["busy"]]; print(r[0]["id"] if r else "")')" || return 0
  [ -n "${id}" ] || return 0
  github_api -X DELETE "https://api.github.com/repos/${REPO}/actions/runners/${id}" >/dev/null \
    && log "removed leftover registration ${name} (id ${id})"
}

STREAK=0
log "starting for ${REPO} (image ${IMAGE}, cpuset ${CPUSET_CPUS} mems ${CPUSET_MEMS}, memory ${MEMORY})"
while true; do
  stop_container
  if ! TOKEN="$(mint_registration_token)" || [ -z "${TOKEN}" ]; then
    log "failed to mint registration token; retrying in 60s"
    sleep 60
    continue
  fi
  log "launching one ephemeral runner container"
  docker run --rm --name "${CONTAINER}" \
    --memory="${MEMORY}" --memory-swap="${MEMORY}" \
    --cpus="${CPUS}" --cpuset-cpus="${CPUSET_CPUS}" --cpuset-mems="${CPUSET_MEMS}" \
    --user runner --cap-drop ALL --security-opt no-new-privileges \
    --network "${NET}" \
    -e JOERN_CI_REPO_URL="https://github.com/${REPO}" \
    -e CODEBADGER_MCP_URL="${MCP_URL}" \
    -e CODEBADGER_SRC_DIR=/codebadger-src \
    -e CODEBADGER_SRC_MCP_DIR="${SRC_MCP_DIR}" \
    -v "${SRC_HOST_DIR}:/codebadger-src" \
    -v "${ENTRYPOINT}:/codeinside/entrypoint.sh:ro" \
    --entrypoint /codeinside/entrypoint.sh \
    "${IMAGE}" "${TOKEN}" >"${RUN_LOG}" 2>&1 &
  wait $! || log "runner container exited non-zero"
  unset TOKEN
  cat "${RUN_LOG}"
  remove_leftover_registration || true
  if grep -q ': Running job: ' "${RUN_LOG}"; then STREAK=0; else STREAK=$((STREAK + 1)); fi
  delay=$(( STREAK == 0 ? 2 : (STREAK > 6 ? 300 : 5 << (STREAK - 1)) ))
  sleep "${delay}"
done
