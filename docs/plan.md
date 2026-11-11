# AI 코드 분석 도구 구축 계획

2026-11-11 · 원본: [claude.ai 문서](https://claude.ai/artifact/DAPVDmG6FzjpyqirLbrQ2e). 이 파일은 작업자가 읽을 수 있도록 레포에 넣은 사본이다. 원본이 바뀌면 이 파일도 같이 고친다.

## 목표와 범위

criterion review에서 코드 탐색을 AI가 매번 하지 않고 결정적인 도구에 맡기는 환경을 만든다. 시험은 opensre 포크에서 하고, 구성은 비공개 코드에도 그대로 쓸 수 있게 사내 서버 안에서만 돌린다.

- 이번 계획: 도구 설치, 기준값 측정, MCP 연결, PR 자동 분석, criterion review 연결까지
- 마지막 단계: llmroute에 적용해 기존 측정과 비교
- 실행은 연결된 codeinside 폴더의 Claude Code 작업자가 맡는다. 이 문서는 그 작업자에게 넘길 계획이다

codeinside 폴더를 GitHub 레포로 만들어 연결하는 일도 범위에 들어간다. 도구 설정, MCP 래퍼, 스크립트, 측정 기록은 모두 이 레포에 둔다.

## 정해진 것

테스트 레포, 분석 서버, 도구 짝은 정해졌다. 남은 선택은 마지막 절에 모았다.

| 항목 | 결정 | 근거 |
| --- | --- | --- |
| 테스트 레포 | [Munsik-Park/opensre](https://github.com/Munsik-Park/opensre) 포크 | 공개, Apache 2.0. 거의 Python이고 테스트를 빼면 약 33만 줄. autoflow 이슈 브랜치가 20여 개 있다 |
| 업스트림 연결 | 끊지 않음 | 작업은 내 레포에서만 한다. 포크를 해제하면 이슈와 PR이 사라진다 |
| 분석 서버 | Xeon E7-4820 v4 머신 | 4소켓 40코어(80스레드), 메모리 512GB(바로 쓸 수 있는 양 약 467GB), NUMA 4노드. 이미 러너로 쓰고 있다 |
| Ryzen 9 5900 머신 | 지금처럼 러너로만 씀 | 메모리 64GB라 Joern과 러너 작업이 부딪히기 쉽다 |
| 넓게 찾기(Screening) | ast-grep + 공식 MCP | DB 없이 그때그때 검색한다. MIT |
| 깊게 따라가기(In-depth) | Joern + MCP | 미리 만든 그래프에서 호출과 데이터 흐름을 따라간다. Apache 2.0 |
| Java | OpenJDK 21 | Joern README의 요구 버전. Xeon에는 아직 설치되지 않았다 |
| 실행 주체 | codeinside 폴더의 Claude Code 작업자 | 작업자가 서버 접속 정보를 갖고 있다 |

## 전체 구조

그래프를 만들고 보관하고 질의를 받는 일은 Xeon이 맡는다. ast-grep 검색과 모든 질의는 작업자 쪽에서 시작한다.

![전체 구조 · GitHub, Xeon, 작업자 쪽](images/plan-structure.png)

사전 스크립트가 ast-grep 결과로 후보 목록을 만들어 작업 세션에 넣는다. 작업 세션은 더 필요할 때만 ast-grep이나 Joern에 직접 묻는다.

블록도는 [architecture.md](architecture.md)에 따로 있다.

## 구성 요소별 설계

서버가 필요한 건 Joern뿐이다. ast-grep은 작업자 체크아웃에서 바로 돈다.

### codeinside 레포

- GitHub 레포는 Munsik-Park/codeinside(공개)로 만들었다. 연결된 폴더는 아직 비어 있고 git 레포도 아니라서, 둘을 잇는 일이 남았다.
- 여기에 둔다: ast-grep 규칙, Joern MCP 래퍼, 후보 목록을 만드는 사전 스크립트, Xeon 설치 절차, 측정 기록.
- opensre 쪽에는 워크플로 파일만 넣고, 실제 작업은 codeinside의 스크립트를 불러서 한다.

### ast-grep

- 작업자 쪽에 설치하고 공식 MCP를 로컬 프로세스로 붙인다.
- 공식 MCP 도구는 구문 트리 보기, 규칙 시험, 패턴 검색, 규칙 검색 4가지다. 스스로 실험 단계라고 밝힌다.
- 저장할 것이 없으므로 SHA별 보관도 필요 없다.

### Joern 서버 (Xeon)

- `joern --server`로 상주시키고 basic auth를 건다. 문서에 "격리가 없다"고 명시돼 있어 내부망에서만 연다.
- `-Xmx`로 메모리 상한을 둔다. `importCode`는 같은 상한의 JVM을 하나 더 띄우므로, 문서 권고대로 프런트엔드를 따로 돌려 그래프 파일을 만들고 `importCpg`로 올린다.
- NUMA 노드 하나를 Joern 전용으로 두는 것을 기본으로 한다. 노드 간 거리가 10 대 11이라 성능보다는 러너와 섞이지 않게 하려는 것이다.

### Joern MCP

- 작업자 쪽에서 띄우는 얇은 래퍼가 Joern 서버에 HTTP로 질의한다(`/query-sync`).
- 대안은 codebadger(Docker, Postgres, Redis)다. 어느 쪽으로 할지는 남은 결정에 둔다.

### 트리거와 저장

- Xeon 러너에 라벨 하나(예: `joern`)를 붙여 분석 작업만 이 머신으로 보낸다.
- PR이 열리거나 main이 바뀌면 그래프를 만들고 커밋 SHA 이름으로 저장한다. 브랜치는 SHA를 가리키기만 한다.
- 해당 SHA 결과가 없으면 가장 가까운 조상 커밋의 결과를 쓴다.
- 포크에 딸려 온 업스트림 워크플로 14개는 먼저 끈다.

## 단계별 실행 계획

일곱 단계를 순서대로 진행한다. 각 단계는 codeinside의 Claude Code 작업자가 맡고, 끝내는 기준을 만족해야 다음으로 넘어간다.

1. **codeinside 레포 만들기**
    - 만들어 둔 공개 레포 Munsik-Park/codeinside를 연결된 폴더와 잇는다. 공개 레포이므로 서버 주소, 계정 같은 접속 정보는 올리지 않는다. 연구 목표와 이 계획을 담은 README와 CLAUDE.md를 넣는다.
    - 끝: 첫 커밋이 원격에 올라가 있다.
2. **Xeon 준비**
    - OpenJDK 21과 Joern을 설치한다. 설치 절차는 codeinside에 스크립트로 남긴다.
    - 끝: `java -version`이 21을 보여 주고 Joern 콘솔이 뜬다.
3. **기준값 측정 (수동)**
    - opensre의 core 폴더(약 5만 줄)로 그래프를 만든 뒤 전체(약 33만 줄)로 넓힌다. 질의 몇 개의 응답 시간도 잰다.
    - 끝: 측정·검증 표의 1~3행이 채워져 있고, 이 값으로 `-Xmx`와 노드 고정 여부를 정한다.
4. **ast-grep 연결**
    - 작업자 쪽에 설치하고 공식 MCP를 붙인다. Screening용 규칙을 몇 개 쓴다.
    - 끝: 같은 SHA에서 두 번 돌려 같은 후보 목록이 나온다.
5. **Joern 서버와 MCP 연결**
    - Xeon에 서버를 상주시키고 MCP 래퍼를 붙인다.
    - 끝: 작업 세션에서 MCP로 호출 관계를 물어 답을 받는다.
6. **PR 자동 분석**
    - opensre의 업스트림 워크플로를 끄고, Xeon 러너 라벨과 분석 워크플로를 넣는다. SHA별 저장과 조상 대체도 구현한다.
    - 끝: 시험 PR을 하나 열면 그 SHA의 그래프가 저장되고 MCP로 질의된다.
7. **criterion review 연결과 비교**
    - 작업 에이전트를 띄우기 전에 사전 스크립트가 후보 목록을 넣는다. opensre 정답 사례로 AI 단독 방식과 비교하고, 이어서 llmroute에서 기존 측정과 비교한다.
    - 끝: 측정·검증 표의 4~6행이 채워져 있다.

## 측정·검증 항목

목표는 모든 문제를 찾는 것이 아니라 루프 횟수와 비용을 줄이는 것이다. 성공 기준 숫자는 3단계 측정을 본 뒤에 정한다. 결과 칸은 작업자가 채운다.

| # | 항목 | 재는 것 | 단계 | 비교 기준 | 결과 |
| --- | --- | --- | --- | --- | --- |
| 1 | 그래프 생성 시간 | core와 전체 각각 | 3 | 없음(처음 재는 값) | |
| 2 | 생성 중 최대 메모리와 그래프 크기 | core와 전체 각각 | 3 | 없음 | |
| 3 | 질의 응답 시간 | 호출 관계·데이터 흐름 질의 몇 개 | 3 | 없음 | |
| 4 | 탐지 | 정답 사례에서 동작을 결정하는 코드를 찾은 비율 | 7 | AI 단독. llmroute는 C7 탐지 1/3 | |
| 5 | 비용 | 기록당 비용 | 7 | AI 단독. llmroute는 $1.8–4.6에서 $10–26으로 증가 | |
| 6 | 루프 횟수 | 리뷰에서 재작업으로 돌아간 횟수 | 7 | AI 단독 | |

## 확인되지 않은 것과 위험

가장 큰 미확인은 Joern이 바뀐 파일만 갱신할 수 있는지다. 안 되면 커밋마다 그래프를 통째로 다시 만들어야 한다.

| 항목 | 상태 | 대응 |
| --- | --- | --- |
| Joern 부분 갱신 | 확인 안 됨 | 3단계에서 확인한다. 안 되면 조상 대체는 ast-grep에만 적용한다 |
| opensre 규모의 메모리와 시간 | 재지 않음 | core부터 재고 넓힌다 |
| Xeon 코어당 속도 | 2.0GHz, 터보 없음 | 너무 느리면 그래프 생성은 Ryzen, 보관과 질의는 Xeon으로 나눈다 |
| ast-grep 공식 MCP | 스스로 실험 단계라고 밝힘 | 사전 스크립트는 MCP 없이 CLI를 직접 부른다 |
| Joern 서버 격리 없음 | 문서에 명시 | 내부망 전용, basic auth, 외부 노출 금지 |
| opensre 정답지 | 없음 | 지난 autoflow PR에서 사례를 골라 사람이 결정 코드를 확인해 둔다 |
| SHA별 그래프 누적 | 크기 모름 | 2행 측정 뒤 보관 기간을 정한다 |

## 남은 결정

단계 1을 막는 결정은 없다. 나머지는 진행하면서 정한다.

- [x] codeinside 레포: Munsik-Park/codeinside, 공개로 정함
- [ ] Joern MCP: 직접 얇게 만들기 또는 codebadger (단계 5 전)
- [ ] Joern `-Xmx` 값과 NUMA 노드 고정 여부 (단계 3 측정 뒤)
- [ ] 그래프를 둘 위치와 보관 기간 (단계 6 전)
- [ ] opensre 정답 사례로 쓸 이슈·PR (단계 7 전)

## 출처

- [Joern README — JDK 21 요구](https://github.com/joernio/joern)
- [Joern 서버 모드 — 격리 없음, basic auth](https://docs.joern.io/server/)
- [Joern 설치 — 메모리, -Xmx, importCpg](https://docs.joern.io/installation/)
- [ast-grep 공식 MCP — 도구 4개, 실험 단계](https://mcpservers.org/en/servers/ast-grep/ast-grep-mcp)
- [codebadger(Joern MCP) — Docker, Postgres, Redis](https://glama.ai/mcp/servers/@Lekssays/joern-mcp)
- [Intel Xeon E7-4820 v4 사양](https://www.intel.com/content/www/us/en/products/sku/93814/intel-xeon-processor-e74820-v4-25m-cache-2-00-ghz/specifications.html)
- [포크 해제 — 이슈·PR 소실](https://docs.github.com/en/pull-requests/how-tos/work-with-forks/detaching-a-fork)
