# ast-grep Screening 규칙

후보 목록은 `python3 scripts/screen/candidates.py <대상 레포> -o <출력.json>`으로 만든다. 출력은 정렬된 JSON이라 같은 커밋에서 두 번 돌리면 바이트 단위로 같다.

| 규칙 | 거르는 것 |
| --- | --- |
| `py-env-read` | 환경 변수를 읽는 곳. 실행 환경에 따라 동작이 갈리는 지점 |
| `py-global-state` | 함수 안의 `global` 문. 모듈 전역 상태를 바꿔 다른 호출의 동작을 바꾸는 지점 |
| `py-runtime-assert` | 테스트 밖의 `assert` 문. `python -O`에서 사라지는 런타임 검사 |
| `py-except-swallow` | 본문이 `pass` 하나뿐인 `except` 절. 실패가 조용히 사라지는 지점 |
| `py-subprocess-shell` | `shell=True`로 부르는 `subprocess` 호출. 셸 해석을 거치는 외부 명령 실행 지점 |
