#!/usr/bin/env bash
# Xeon 분석 서버에 OpenJDK 21과 Joern을 설치한다 (docs/plan.md 단계 2).
#
# 실행: 서버에서 root 권한으로 실행한다. 여러 번 실행해도 결과가 같다.
#   sudo bash install-joern.sh
#
# 결과
#   - openjdk-21-jdk-headless (Ubuntu 패키지)
#   - joern 전용 system 계정: 로그인 불가, sudo/docker/lxd 그룹 미포함
#   - /opt/joern/<버전>/joern-cli  (root 소유, joern 계정은 읽기·실행만)
#   - /opt/joern/current -> 설치한 버전
#
# 접속 정보(서버 주소, 계정, 키)는 이 파일에 넣지 않는다.
set -euo pipefail

JOERN_VERSION="${JOERN_VERSION:-v4.0.680}"
JOERN_USER="joern"
JOERN_HOME="/var/lib/joern"
INSTALL_ROOT="/opt/joern"
ASSET="joern-cli-linux-x86_64.zip"
BASE_URL="https://github.com/joernio/joern/releases/download/${JOERN_VERSION}"

if [[ $EUID -ne 0 ]]; then
  echo "root 권한으로 실행해야 한다: sudo bash $0" >&2
  exit 1
fi

echo "== 패키지 설치"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q openjdk-21-jdk-headless unzip curl

echo "== 전용 계정"
if ! id "$JOERN_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$JOERN_HOME" --create-home \
          --shell /usr/sbin/nologin "$JOERN_USER"
fi
for g in sudo docker lxd adm; do
  if id -nG "$JOERN_USER" | tr ' ' '\n' | grep -qx "$g"; then
    echo "$JOERN_USER 계정이 $g 그룹에 있다. 권한 분리가 깨지므로 중단한다." >&2
    exit 1
  fi
done

echo "== Joern ${JOERN_VERSION}"
target="${INSTALL_ROOT}/${JOERN_VERSION}"
if [[ ! -x "${target}/joern-cli/joern" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "${tmp}/${ASSET}" "${BASE_URL}/${ASSET}"
  curl -fsSL -o "${tmp}/${ASSET}.sha512" "${BASE_URL}/${ASSET}.sha512"
  expected="$(awk '{print $1}' "${tmp}/${ASSET}.sha512")"
  actual="$(sha512sum "${tmp}/${ASSET}" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    echo "sha512 불일치: ${ASSET}" >&2
    exit 1
  fi
  mkdir -p "$target"
  unzip -q "${tmp}/${ASSET}" -d "$target"
  chown -R root:root "$target"
  chmod -R go-w "$target"
fi
ln -sfn "$target" "${INSTALL_ROOT}/current"

echo "== 확인"
java -version 2>&1 | head -1
ls "${INSTALL_ROOT}/current/joern-cli/joern"
id "$JOERN_USER"
