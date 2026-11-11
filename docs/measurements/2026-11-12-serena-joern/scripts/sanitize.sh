#!/usr/bin/env bash
# 원본 로그를 레포에 넣기 전에 로컬 절대 경로를 자리 표시자로 바꾼다.
# 사용: OPENSRE_DIR=... CODEINSIDE_DIR=... bash sanitize.sh <입력> <출력>
set -euo pipefail
: "${OPENSRE_DIR:?}"; : "${CODEINSIDE_DIR:?}"
o="$(cd "$OPENSRE_DIR" && pwd)"; c="$(cd "$CODEINSIDE_DIR" && pwd)"
sed -e "s|$o|\$OPENSRE_DIR|g" -e "s|$c|\$CODEINSIDE_DIR|g" -e "s|$HOME|\$HOME|g" "$1" > "$2"
