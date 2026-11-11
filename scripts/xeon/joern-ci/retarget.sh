#!/usr/bin/env bash
# 분석 러너의 대상 레포를 바꾼다 (docs/plan.md 단계 6, 대상 변경). sudo로 실행한다.
#   sudo bash retarget.sh <owner/repo>            설정만 바꾸고 다시 띄운다(PAT의 레포 범위를 미리 넓혀 둔 경우)
#   sudo ROTATE_PAT=1 bash retarget.sh <owner/repo>  새 PAT도 입력받는다
# 이전 레포에 남는 러너 등록은 이 스크립트가 지우지 않는다. 작업자 쪽에서 API로 지운다.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "sudo로 실행한다" >&2; exit 1; }
REPO="${1:?owner/repo가 필요하다}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "owner/repo 형식이 아니다: $REPO" >&2; exit 1; }
ETC=/etc/codeinside-joern-ci
if [ "${ROTATE_PAT:-0}" = 1 ]; then
  read -rsp "$REPO Administration 쓰기 권한 PAT: " pat; echo
  [ -n "$pat" ] || { echo "PAT가 비었다" >&2; exit 1; }
  umask 077
  printf 'RUNNER_REG_PAT=%s\n' "$pat" > "$ETC/runner.env.tmp"
  mv "$ETC/runner.env.tmp" "$ETC/runner.env"
  unset pat
  chown root:root "$ETC/runner.env"; chmod 600 "$ETC/runner.env"
fi
sed -i "s|^JOERN_CI_REPO=.*|JOERN_CI_REPO=${REPO}|" "$ETC/runner.conf"
grep '^JOERN_CI_REPO=' "$ETC/runner.conf"
systemctl restart codeinside-joern-runner.service
sleep 15
systemctl --no-pager --lines=0 status codeinside-joern-runner.service | grep -E 'Active:'
journalctl -u codeinside-joern-runner.service --no-pager -n 5 -o cat | grep -E 'joern-runner-supervisor' || true
