# codeinside

분석 대상 레포의 코드를 AI 세션이 MCP 3개로 찾고 따라가게 하는 도구 레포다.

## MCP

| MCP | 쓰는 질문 |
| --- | --- |
| ast-grep | 패턴에 맞는 곳을 레포 전체에서 넓게 찾기 |
| Serena | 심볼을 실제로 참조하는 곳, 정의, 구현 |
| Joern | 호출 관계를 몇 단계 따라가기, 값의 흐름 |

## 세션이 받는 값

- 분석 대상 체크아웃 경로
- 이슈의 SHA
- 그 SHA의 그래프 ID(`codebase_hash`)

## 규칙

- Joern은 `get_cpg_status`가 `ready`일 때만 묻는다.
- 흔한 이름이나 다시 내보낸 심볼의 호출 관계는 Serena로 본다.
- 테스트 폴더는 Joern 그래프에 없다. 테스트 쪽은 Serena로 본다.
- 조상 그래프로 받았으면 바뀐 파일 목록에 든 파일의 답은 믿지 않는다.

## 문서

- [docs/usage.md](docs/usage.md): 도구 이름, 인자, 응답 모양
- [docs/setup.md](docs/setup.md): 환경 구축
- [docs/architecture.md](docs/architecture.md): 구성
- [docs/plan.md](docs/plan.md): 계획과 단계 기록
