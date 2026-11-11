# 작업 규칙

## 작업 전에

- 작업 전에 docs/plan.md와 docs/architecture.md를 먼저 읽는다.

## 공개 범위

이 레포는 공개 레포다.

- 접속 정보는 커밋하지 않는다. 서버 주소, IP, 호스트명, 계정, 비밀번호, 키, 토큰, .env 파일이 여기에 해당한다.
- 적어도 되는 것: 서버 운영 사양(CPU, 메모리, NUMA 구성, JVM 설정 등), llmroute 통계 기록.
- 절대 넣지 않는 것: 접속 방법, IP, 계정, 키. 코드, 문서, 커밋 메시지, PR 본문 모두 같다.
- 접속 정보가 필요한 스크립트는 환경 변수나 커밋되지 않는 로컬 파일에서 읽는다.

## GitHub 작업

- opensre 업스트림(Tracer-Cloud/opensre)에는 PR과 이슈를 만들지 않는다.
- PR은 항상 `--repo`로 대상을 지정한다. 예: `gh pr create --repo Munsik-Park/opensre`, `gh pr create --repo Munsik-Park/codeinside`
