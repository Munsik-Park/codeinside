#!/usr/bin/env bash
# CI 없이 커밋 하나의 Joern 그래프를 만든다(새 레포 등록 때 기준 그래프). Xeon 호스트에서 sudo로 실행한다.
#   sudo bash manual-graph.sh <owner/repo> <커밋 SHA>
#   sudo ROTATE_PAT=1 bash manual-graph.sh <owner/repo> <커밋 SHA>   토큰 파일을 새로 입력받는다
# 토큰 파일: /etc/codeinside-joern-ci/manual-graph/<owner>/<repo>.env (GITHUB_TOKEN=..., root 소유, 권한 600)
#   대상 레포 하나만 고른 fine-grained PAT. 권한은 Commit statuses write, Actions read.
#   파일이 없으면 입력받아 만든다. 소유자나 권한이 다르면 멈춘다.
# 하는 일:
#   1. 대상 레포에 queued나 in_progress인 Actions run이 있으면 멈춘다. 분석 워크플로의 prune_cpgs.py가
#      CI 소스 폴더의 `<레포 이름>-*` 폴더를 지우기 때문이다.
#   2. SHA를 전체 SHA로 바꾸고(토큰 없이 REST API), 러너 계정 codeinside-runner 소유 임시 폴더에 그 커밋만 받는다.
#      토큰 없이 받으므로 공개 레포만 된다.
#   3. runner.conf의 JOERN_CI_SRC_HOST_DIR, JOERN_CI_SRC_MCP_DIR와 CODEBADGER_MCP_URL=http://127.0.0.1:4242/mcp로
#      scripts/ci/joern_cpg_job.py를 러너 계정으로 돌린다. 커밋 상태 `codeinside/joern-cpg`와 색인(.cpg-index.jsonl)은
#      CI와 같게 남는다. GITHUB_RUN_ID가 없으므로 커밋 상태에 target_url은 없다.
#   4. 임시 폴더를 지운다. 출력 끝의 `RECORD {json}` 줄에 codebase_hash, generate→ready 초, STATS가 있다.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "sudo로 실행한다" >&2; exit 1; }
REPO="${1:?owner/repo가 필요하다}"
SHA_ARG="${2:?커밋 SHA가 필요하다}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "owner/repo 형식이 아니다: $REPO" >&2; exit 1; }
[[ "$SHA_ARG" =~ ^[0-9a-f]{7,40}$ ]] || { echo "커밋 SHA 형식이 아니다: $SHA_ARG" >&2; exit 1; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ETC=/etc/codeinside-joern-ci
RUNNER=codeinside-runner
MCP_URL=http://127.0.0.1:4242/mcp
umask 022

conf() { sed -n "s|^$1=||p" "$ETC/runner.conf" | tail -n 1; }
SRC_HOST=$(conf JOERN_CI_SRC_HOST_DIR)
SRC_MCP=$(conf JOERN_CI_SRC_MCP_DIR)
[ -n "$SRC_HOST" ] && [ -n "$SRC_MCP" ] || { echo "$ETC/runner.conf에 JOERN_CI_SRC_HOST_DIR, JOERN_CI_SRC_MCP_DIR가 없다" >&2; exit 1; }
[ -d "$SRC_HOST" ] || { echo "CI 소스 폴더가 없다: $SRC_HOST" >&2; exit 1; }
id "$RUNNER" >/dev/null

TOKEN_FILE="$ETC/manual-graph/$REPO.env"
if [ ! -f "$TOKEN_FILE" ] || [ "${ROTATE_PAT:-0}" = 1 ]; then
  read -rsp "$REPO fine-grained PAT(Commit statuses write, Actions read): " pat; echo
  [ -n "$pat" ] || { echo "PAT가 비었다" >&2; exit 1; }
  install -d -m 700 -o root -g root "$ETC/manual-graph" "$(dirname "$TOKEN_FILE")"
  (umask 077; printf 'GITHUB_TOKEN=%s\n' "$pat" > "$TOKEN_FILE.tmp")
  mv "$TOKEN_FILE.tmp" "$TOKEN_FILE"
  unset pat
fi
[ "$(stat -c '%u %a' "$TOKEN_FILE")" = "0 600" ] || { echo "$TOKEN_FILE는 root 소유, 권한 600이어야 한다" >&2; exit 1; }
GITHUB_TOKEN=$(sed -n 's|^GITHUB_TOKEN=||p' "$TOKEN_FILE")
[ -n "$GITHUB_TOKEN" ] || { echo "$TOKEN_FILE에 GITHUB_TOKEN이 없다" >&2; exit 1; }
export GITHUB_TOKEN

# Actions run 확인(토큰), 전체 SHA 얻기(토큰 없이). 토큰은 환경 변수로만 넘긴다.
FULL_SHA=$(python3 - "$REPO" "$SHA_ARG" <<'PY'
import json, os, sys, urllib.request
repo, sha = sys.argv[1:]
def get(path, auth):
    h = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"}
    if auth:
        h["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    with urllib.request.urlopen(urllib.request.Request(f"https://api.github.com{path}", headers=h), timeout=30) as r:
        return json.loads(r.read())
busy = []
for status in ("queued", "in_progress"):
    runs = get(f"/repos/{repo}/actions/runs?status={status}&per_page=100", True)["workflow_runs"]
    busy += [f"run {r['id']} {r['name']} {status} head={r['head_sha'][:12]}" for r in runs]
if busy:
    sys.exit("Actions run이 있어 멈춘다. 끝난 뒤 다시 실행한다.\n  " + "\n  ".join(busy))
print("Actions run: queued 0, in_progress 0", file=sys.stderr)
print(get(f"/repos/{repo}/commits/{sha}", False)["sha"])
PY
)
echo "target: $REPO $FULL_SHA"

WORK=$(mktemp -d /tmp/codeinside-manual-graph.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
install -d "$WORK/codeinside/scripts/ci" "$WORK/codeinside/scripts/mcp"
install -m 644 "$ROOT/scripts/ci/joern_cpg_job.py" "$WORK/codeinside/scripts/ci/"
install -m 644 "$ROOT/scripts/mcp/mcp_http.py" "$WORK/codeinside/scripts/mcp/"
chown -R "$RUNNER:$RUNNER" "$WORK"
chmod 700 "$WORK"
cd "$WORK"

# setpriv는 uid/gid만 바꾸고 환경 변수는 그대로 넘긴다(GITHUB_TOKEN 포함).
as_runner() {
  setpriv --reuid="$RUNNER" --regid="$RUNNER" --clear-groups -- \
    env -u GITHUB_RUN_ID -u GITHUB_STEP_SUMMARY -u XDG_CONFIG_HOME HOME="$WORK" "$@"
}
as_runner git init -q "$WORK/target"
as_runner git -C "$WORK/target" fetch -q --depth=1 "https://github.com/$REPO.git" "$FULL_SHA"
as_runner GITHUB_REPOSITORY="$REPO" CODEBADGER_MCP_URL="$MCP_URL" \
  CODEBADGER_SRC_DIR="$SRC_HOST" CODEBADGER_SRC_MCP_DIR="$SRC_MCP" \
  python3 "$WORK/codeinside/scripts/ci/joern_cpg_job.py" --checkout "$WORK/target" --sha "$FULL_SHA"
