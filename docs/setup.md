# 환경 구축

순서대로 한다. 각 스크립트의 사용법은 머리 주석에 있다. 서버 주소, 계정, 터널 명령은 이 레포에 넣지 않는다.

## 1. Xeon

| 할 일 | 링크 |
| --- | --- |
| codebadger 올리기(패치, 설정) | [scripts/xeon/deploy-codebadger.sh](../scripts/xeon/deploy-codebadger.sh), [config/codebadger/](../config/codebadger/) |
| 이미지 묶음 저장, 부팅 복원 유닛 | [scripts/xeon/save-codebadger-images.sh](../scripts/xeon/save-codebadger-images.sh), [config/codebadger/systemd/](../config/codebadger/systemd/) |
| 분석 러너 설치 | [scripts/xeon/joern-ci/install.sh](../scripts/xeon/joern-ci/install.sh), [config/joern-ci/runner.conf.example](../config/joern-ci/runner.conf.example) |

## 2. 대상 레포 CI 연결

| 할 일 | 링크 |
| --- | --- |
| 워크플로 견본을 대상 레포 `.github/workflows/`에 복사 | [config/joern-ci/workflow.example.yml](../config/joern-ci/workflow.example.yml) |
| 러너 대상 레포 변경 | [scripts/xeon/joern-ci/retarget.sh](../scripts/xeon/joern-ci/retarget.sh) |
| 그래프 제외 규칙(`exclusion_patterns`) | [config/codebadger/codebadger-v0.7.0-beta.patch](../config/codebadger/codebadger-v0.7.0-beta.patch) |
| 확인 질의 파일 | [config/queries/crewai.json](../config/queries/crewai.json) |
| CI 없이 기준 그래프 만들기(새 레포 등록) | [scripts/xeon/manual-graph.sh](../scripts/xeon/manual-graph.sh) |

## 3. AI가 도는 머신

| 구성 | 버전 | 설치 |
| --- | --- | --- |
| ast-grep CLI | 0.51.2 | `brew install ast-grep` |
| uv | 0.11.32 | uv 문서의 설치 방법 |
| Serena | 2.1.0 | `uv tool install -p 3.13 serena-agent==2.1.0` |
| Pyright | 1.1.403 | Serena가 uvx로 띄운다 |
| gh | 인증된 상태 | 그래프 고르기가 커밋 상태를 읽는다 |
| Claude Code | 2.1.322 | |

- MCP 등록: [scripts/mcp/register.sh](../scripts/mcp/register.sh). Pyright 설정 예: [config/serena/crewai/pyrightconfig.json](../config/serena/crewai/pyrightconfig.json)
- `JOERN_MCP_URL`은 커밋하지 않는 로컬 설정에서 읽는다.

## 4. 세션을 띄우는 쪽

- 이슈의 SHA를 그래프 ID로 바꾼다: [scripts/joern/resolve_graph.py](../scripts/joern/resolve_graph.py)
- 세션에는 체크아웃 경로, SHA, 출력의 `codebase_hash`를 넘긴다. `exact: false`이면 `changed_files`도 넘긴다.

## 5. 확인 기록

- [2026-11-12-usage-check](measurements/2026-11-12-usage-check/README.md): 명령을 crewAI에서 다시 돌린 결과
- [2026-11-12-ai-docs](measurements/2026-11-12-ai-docs/README.md): 등록 스크립트, 워크플로 견본, AI 세션 확인
