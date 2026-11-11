#!/usr/bin/env bash
# opensre 분석 러너를 Xeon에 설치한다 (docs/plan.md 단계 6). sudo로 실행한다.
#   sudo bash install.sh <codeinside 사본 루트>
# 하는 일:
#   1. 시스템 계정 codeinside-ci(docker 그룹)를 만든다.
#   2. 스크립트를 /opt/codeinside-joern-ci에, 설정을 /etc/codeinside-joern-ci에 둔다.
#      PAT는 처음 한 번 입력받아 runner.env(권한 600)에 쓴다. 바꿀 때는 ROTATE_PAT=1.
#   3. codebadger playground 아래 CI 소스 폴더를 러너 컨테이너 계정(uid 1000) 소유로 만든다.
#   4. systemd 유닛 2개를 설치하고 켠다.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "sudo로 실행한다" >&2; exit 1; }
SRC="${1:?codeinside 사본 루트가 필요하다}"
OPT=/opt/codeinside-joern-ci
ETC=/etc/codeinside-joern-ci

id codeinside-ci >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin codeinside-ci
usermod -aG docker codeinside-ci

install -d -m 755 "$OPT"
install -m 755 "$SRC/scripts/xeon/joern-ci/entrypoint.sh" "$SRC/scripts/xeon/joern-ci/runner-supervisor.sh" \
  "$SRC/scripts/xeon/joern-ci/setup-network.sh" "$OPT/"
install -m 644 "$SRC/scripts/xeon/joern-ci/tcp_proxy.py" "$OPT/"

install -d -m 755 "$ETC"
[ -f "$ETC/runner.conf" ] || install -m 644 "$SRC/config/joern-ci/runner.conf.example" "$ETC/runner.conf"
if [ ! -f "$ETC/runner.env" ] || [ "${ROTATE_PAT:-0}" = 1 ]; then
  read -rsp "Munsik-Park/opensre Administration 쓰기 권한 PAT: " pat; echo
  [ -n "$pat" ] || { echo "PAT가 비었다" >&2; exit 1; }
  umask 077
  printf 'RUNNER_REG_PAT=%s\n' "$pat" > "$ETC/runner.env.tmp"
  mv "$ETC/runner.env.tmp" "$ETC/runner.env"
  unset pat
fi
chown root:root "$ETC/runner.env"; chmod 600 "$ETC/runner.env"

set -a; . "$ETC/runner.conf"; set +a
install -d -o 1000 -g 1000 -m 755 "$JOERN_CI_SRC_HOST_DIR"

install -m 644 "$SRC/config/joern-ci/systemd/codeinside-joern-ci-net.service" \
  "$SRC/config/joern-ci/systemd/codeinside-joern-runner.service" /etc/systemd/system/
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/codeinside-joern-ci-net.service /etc/systemd/system/codeinside-joern-runner.service
systemctl enable codeinside-joern-ci-net.service codeinside-joern-runner.service
systemctl restart codeinside-joern-ci-net.service
systemctl restart codeinside-joern-runner.service
sleep 15
systemctl --no-pager --lines=0 status codeinside-joern-ci-net.service codeinside-joern-runner.service | grep -E '●|Active:'
journalctl -u codeinside-joern-runner.service --no-pager -n 20 | grep -E 'joern-runner-supervisor|Listening for Jobs|Connected to GitHub|error' || true
