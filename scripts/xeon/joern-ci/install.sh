#!/usr/bin/env bash
# codeinside Joern 분석 러너를 Xeon에 설치한다 (docs/plan.md 단계 6). 대상 레포는 runner.conf의 JOERN_CI_REPO다. sudo로 실행한다.
#   sudo bash install.sh <codeinside 사본 루트>
# 하는 일:
#   1. 시스템 계정 codeinside-ci(docker 그룹, supervisor 실행)와 codeinside-runner(러너 컨테이너 uid, 로그인 불가)를 만든다.
#   2. 스크립트를 /opt/codeinside-joern-ci에, 설정을 /etc/codeinside-joern-ci에 둔다.
#      PAT는 처음 한 번 입력받아 runner.env(권한 600)에 쓴다. 바꿀 때는 ROTATE_PAT=1.
#   3. runner.conf의 러너 uid/gid와 이미지 이름을 채우고, CI 소스 폴더를 그 uid 소유로 둔다.
#   4. systemd 유닛 2개를 설치하고 다시 띄운다(net 유닛이 러너 이미지를 빌드한다).
# 이미 설치된 상태에서 다시 실행해도 된다(PAT는 그대로 두고 스크립트·유닛·설정 키만 갱신한다).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "sudo로 실행한다" >&2; exit 1; }
SRC="${1:?codeinside 사본 루트가 필요하다}"
OPT=/opt/codeinside-joern-ci
ETC=/etc/codeinside-joern-ci

id codeinside-ci >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin codeinside-ci
usermod -aG docker codeinside-ci
id codeinside-runner >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin codeinside-runner
RUID=$(id -u codeinside-runner); RGID=$(id -g codeinside-runner)

install -d -m 755 "$OPT"
install -m 755 "$SRC/scripts/xeon/joern-ci/entrypoint.sh" "$SRC/scripts/xeon/joern-ci/runner-supervisor.sh" \
  "$SRC/scripts/xeon/joern-ci/setup-network.sh" "$SRC/scripts/xeon/joern-ci/build-runner-image.sh" "$OPT/"
install -m 644 "$SRC/scripts/xeon/joern-ci/tcp_proxy.py" "$OPT/"

install -d -m 755 "$ETC"
[ -f "$ETC/runner.conf" ] || install -m 644 "$SRC/config/joern-ci/runner.conf.example" "$ETC/runner.conf"
if [ ! -f "$ETC/runner.env" ] || [ "${ROTATE_PAT:-0}" = 1 ]; then
  read -rsp "대상 레포(runner.conf의 JOERN_CI_REPO) Administration 쓰기 권한 PAT: " pat; echo
  [ -n "$pat" ] || { echo "PAT가 비었다" >&2; exit 1; }
  umask 077
  printf 'RUNNER_REG_PAT=%s\n' "$pat" > "$ETC/runner.env.tmp"
  mv "$ETC/runner.env.tmp" "$ETC/runner.env"
  unset pat
fi
chown root:root "$ETC/runner.env"; chmod 600 "$ETC/runner.env"

# 설정 키를 채우거나 바꾼다. 없는 키는 예시 파일 값으로 더한다.
set_conf() { if grep -q "^$1=" "$ETC/runner.conf"; then sed -i "s|^$1=.*|$1=$2|" "$ETC/runner.conf"; else printf '%s=%s\n' "$1" "$2" >> "$ETC/runner.conf"; fi; }
for k in JOERN_CI_BASE_IMAGE JOERN_CI_RUNNER_IMAGE; do
  grep -q "^$k=" "$ETC/runner.conf" || set_conf "$k" "$(sed -n "s|^$k=||p" "$SRC/config/joern-ci/runner.conf.example")"
done
# 예전 설정은 러너 이미지로 librechat 이미지를 직접 썼다. 이제 그 값은 베이스 이미지다.
grep -q '^JOERN_CI_RUNNER_IMAGE=librechat-ci-runner:latest$' "$ETC/runner.conf" && set_conf JOERN_CI_RUNNER_IMAGE codeinside-joern-runner:latest
set_conf JOERN_CI_RUNNER_UID "$RUID"
set_conf JOERN_CI_RUNNER_GID "$RGID"
set -a; . "$ETC/runner.conf"; set +a
install -d -o "$RUID" -g "$RGID" -m 755 "$JOERN_CI_SRC_HOST_DIR"
chown -R "$RUID:$RGID" "$JOERN_CI_SRC_HOST_DIR"

install -m 644 "$SRC/config/joern-ci/systemd/codeinside-joern-ci-net.service" \
  "$SRC/config/joern-ci/systemd/codeinside-joern-runner.service" /etc/systemd/system/
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/codeinside-joern-ci-net.service /etc/systemd/system/codeinside-joern-runner.service
systemctl enable codeinside-joern-ci-net.service codeinside-joern-runner.service
systemctl restart codeinside-joern-ci-net.service
systemctl restart codeinside-joern-runner.service
sleep 15
systemctl --no-pager --lines=0 status codeinside-joern-ci-net.service codeinside-joern-runner.service | grep -E '●|Active:'
journalctl -u codeinside-joern-ci-net.service --no-pager -n 5 -o cat | grep -E 'image user|writable|network=' || true
journalctl -u codeinside-joern-runner.service --no-pager -n 20 | grep -E 'joern-runner-supervisor|Listening for Jobs|Connected to GitHub|error' || true
echo "runner uid/gid: $RUID/$RGID"
docker inspect "$JOERN_CI_RUNNER_NAME" --format 'container user={{.Config.User}} image={{.Config.Image}}' 2>/dev/null || true
