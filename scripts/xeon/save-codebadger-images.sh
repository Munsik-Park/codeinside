#!/usr/bin/env bash
# codebadger 이미지를 디스크에 docker save로 저장하고 부팅 복원 유닛을 설치한다 (docs/plan.md 단계 5).
# 실행: Xeon에서 sudo 가능한 docker 그룹 계정으로
#   bash save-codebadger-images.sh <config/codebadger 사본 폴더>
# 이미지를 새로 빌드하면 다시 실행해 묶음을 갱신한다.
set -euo pipefail
SRC="$1"
sudo install -d -m 755 /etc/codebadger
[[ -f /etc/codebadger/codebadger.conf ]] || sudo install -m 644 "$SRC/systemd/codebadger.conf.example" /etc/codebadger/codebadger.conf
set -a; . /etc/codebadger/codebadger.conf; set +a
sudo install -d -m 755 "$(dirname "$CODEBADGER_IMAGE_TARBALL")"
tmp="$CODEBADGER_IMAGE_TARBALL.tmp"
# shellcheck disable=SC2086
sudo docker save $CODEBADGER_IMAGES -o "$tmp"
sudo mv "$tmp" "$CODEBADGER_IMAGE_TARBALL"
ls -l "$CODEBADGER_IMAGE_TARBALL"
sudo tar -xOf "$CODEBADGER_IMAGE_TARBALL" manifest.json | python3 -c 'import sys,json; print("tags in tarball:", [t for m in json.load(sys.stdin) for t in (m.get("RepoTags") or [])])'
sudo install -m 644 "$SRC/systemd/codebadger-image-restore.service" "$SRC/systemd/codebadger-stack.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemd-analyze verify /etc/systemd/system/codebadger-image-restore.service /etc/systemd/system/codebadger-stack.service
sudo systemctl enable codebadger-image-restore.service codebadger-stack.service
systemctl is-enabled codebadger-image-restore.service codebadger-stack.service
