# AI 코드 분석 도구 구축 계획

2026-11-12 · 원본: [claude.ai 문서](https://claude.ai/artifact/DAPVDmG6FzjpyqirLbrQ2e). 이 파일은 작업자가 읽을 수 있도록 레포에 넣은 사본이다. 원본이 바뀌면 이 파일도 같이 고친다.

## 목표와 범위

criterion review에서 코드 탐색을 AI가 매번 하지 않고 결정적인 도구에 맡기는 환경을 만든다. 시험은 opensre 포크(3~5단계)와 crewAI 포크(6단계부터)에서 하고, 구성은 비공개 코드에도 그대로 쓸 수 있게 사내 서버 안에서만 돌린다.

- 이번 계획: 도구 설치, 기준값 측정, MCP 연결, PR 자동 분석, 사용법 문서까지. 도구를 만들고 돌아가는 것까지가 범위다
- 범위 밖: 이슈를 푸는 흐름(criterion review)에 연결하는 일, AI 단독 방식이나 llmroute 기존 측정과의 비교
- 실행은 연결된 codeinside 폴더의 Claude Code 작업자가 맡는다. 이 문서는 그 작업자에게 넘길 계획이다

codeinside 폴더를 GitHub 레포로 만들어 연결하는 일도 범위에 들어간다. 도구 설정, MCP 래퍼, 스크립트, 측정 기록은 모두 이 레포에 둔다.

## 정해진 것

테스트 레포, 분석 서버, 뒤에 붙일 도구 세 개는 정해졌다. 도구 하나로 다 하지 않고, 질문 종류마다 맞는 도구를 뒤에 두고 AI는 MCP로 골라 쓴다. 남은 선택은 마지막 절에 모았다.

| 항목 | 결정 | 근거 |
| --- | --- | --- |
| 테스트 레포 | [Munsik-Park/opensre](https://github.com/Munsik-Park/opensre) 포크 | 공개, Apache 2.0. 거의 Python이고 테스트를 빼면 약 33만 줄. autoflow 이슈 브랜치가 20여 개 있다 |
| 업스트림 연결 | 끊지 않음 | 작업은 내 레포에서만 한다. 포크를 해제하면 이슈와 PR이 사라진다 |
| 6단계부터 테스트 레포 | Munsik-Park/crewAI 포크(기준 커밋 71d68117) | opensre 포크는 GitHub 쪽에서 Actions가 막혀 풀 수 없다. 규모와 성격이 비슷한 공개 Python 레포로 골랐다. MIT |
| 포크 동기화 | 하지 않음 | 업스트림의 새 워크플로가 다시 들어오는 것을 막는다. |
| 분석 서버 | Xeon E7-4820 v4 머신 | 4소켓 40코어(80스레드), 메모리 512GB(바로 쓸 수 있는 양 약 467GB), NUMA 4노드. 이미 러너로 쓰고 있다 |
| Ryzen 9 5900 머신 | 지금처럼 러너로만 씀 | 메모리 64GB. 3단계 측정으로 Xeon만으로 충분하다는 것이 확인됐다 |
| 넓게 찾기(Screening) | ast-grep + 공식 MCP | DB 없이 그때그때 검색한다. MIT |
| 정확한 참조(정의·호출처) | Serena + Pyright(Serena 기본 언어 서버) | Joern은 Python 호출을 이름으로 잇는다(3단계). 타입으로 실제 대상만 찾는다. 흔한 이름에서 Joern 결과 14개 중 실제 호출자는 1개였다(4단계). 앱 GPL-3.0 |
| 깊게 따라가기(In-depth) | Joern | 미리 만든 그래프에서 데이터 흐름과 제어 흐름을 따라간다. Apache 2.0. MCP는 codebadger(5단계) |
| 앞단 | 도구별 MCP를 나란히 붙임 | 통합 앞단은 AI가 도구 선택을 헷갈리는 게 보일 때 만든다 |
| Java | OpenJDK 21 | Joern README의 요구 버전. Xeon에 설치했다(2단계) |
| 실행 주체 | codeinside 폴더의 Claude Code 작업자 | 작업자가 서버 접속 정보를 갖고 있다 |

## 전체 구조

그래프를 만들고 보관하고 질의를 받는 일은 Xeon이 맡는다. ast-grep 검색과 모든 질의는 작업자 쪽에서 시작한다.

![전체 구조 · GitHub, Xeon, 작업자 쪽](images/plan-structure.png)

사전 스크립트가 ast-grep 결과로 후보 목록을 만들어 작업 세션에 넣는다. 작업 세션은 더 필요할 때 Serena(정확한 참조)나 Joern(흐름)에 직접 묻는다.

블록도는 [architecture.md](architecture.md)에 따로 있다.

## 구성 요소별 설계

서버가 필요한 건 Joern뿐이다. ast-grep과 Serena는 작업자 체크아웃에서 바로 돈다.

### codeinside 레포

- GitHub 레포는 Munsik-Park/codeinside(공개)이고 연결된 폴더와 이어져 있다(1단계).
- 여기에 둔다: ast-grep 규칙, Serena 설정, Joern MCP 설정 또는 래퍼, 후보 목록을 만드는 사전 스크립트, Xeon 설치·측정 스크립트, 측정 기록.
- 시험 레포(crewAI 포크) 쪽에는 워크플로 파일만 넣고, 실제 작업은 codeinside의 스크립트를 불러서 한다.

### ast-grep

- 작업자 쪽에 설치하고 공식 MCP를 로컬 프로세스로 붙인다.
- 공식 MCP 도구는 구문 트리 보기, 규칙 시험, 패턴 검색, 규칙 검색 4가지다. 스스로 실험 단계라고 밝힌다.
- 저장할 것이 없으므로 SHA별 보관도 필요 없다.
- ast-grep 0.51.2를 쓴다. 공식 MCP는 태그가 없어 커밋으로 고정했다(4단계).
- 사전 스크립트는 CLI 결과를 정렬해 후보 목록을 만든다. 원본 출력은 실행마다 순서가 달라서다. 같은 커밋에서 두 번 돌려 같은 해시가 나왔다(4단계).

### Serena

- 작업자 체크아웃에서 Pyright(Serena 2.1.0 기본값 1.1.403)를 띄워 정의, 참조, 구현을 찾는다. 이름이 같아도 타입으로 실제 대상을 가린다.
- Joern의 Python 프런트엔드는 호출을 이름으로 잇는다. 흔한 이름은 메서드마다 호출 지점이 약 590개씩 붙는다(3단계). 정확한 참조는 Serena가 맡는다.
- 4단계 비교: `record_evidence_entry`는 두 도구가 131쌍 모두 같았다. 흔한 이름인 `SessionManager.close`는 Joern 14개 중 실제 호출자가 1개였고, 실제 호출자 5개 중 Joern이 찾은 것도 1개였다. Joern은 패키지에서 다시 내보낸 이름과 반환 타입 표기를 풀지 못했다.
- 값의 흐름이나 실행 조건은 다루지 않는다. 그건 Joern이 맡는다.
- 코드 편집과 셸 실행 도구도 들어 있으므로 읽기 도구 5개만 켠다. 도구 인터페이스로 고정하고 fixed_tools와 read_only를 함께 건다. REPL 인터페이스에서는 도구 제한이 먹지 않는다(Serena 문서, 4단계 확인).
- 라이선스: 앱은 GPL-3.0, 언어 서버 연결부(SolidLSP)는 MIT. 사내 사용은 문제없고, 고친 버전을 배포하면 소스 공개 의무가 생긴다.

### Joern 서버 (Xeon)

- `joern --server`로 상주시키고 basic auth를 건다. 문서에 "격리가 없다"고 명시돼 있어 내부망에서만 연다. codebadger 질의 워커는 인증 없이 뜨지만 호스트로 포트를 공개하지 않고 codebadger 브리지 네트워크에만 붙는다(5단계).
- 메모리는 부담이 작다. opensre 전체 기준 그래프 생성은 1G로도 되고 적재는 2G부터 된다. 4G나 8G로 올려도 빨라지지 않았다(3단계).
- 메모리 상한은 `JAVA_TOOL_OPTIONS`로 준다. `joern --script`는 JVM을 하나 더 띄우는데 `-J-Xmx`는 그 자식 JVM에 닿지 않는다(3단계 실측). 서버 모드는 JVM 하나로 떠서 JAVA_TOOL_OPTIONS가 그대로 닿는다(5단계 실측).
- 프런트엔드(pysrc2cpg)를 따로 돌려 그래프 파일을 만들고 `importCpg`로 올린다.
- NUMA 노드 3을 Joern 몫으로 둔다. codebadger 질의 워커와 그래프 생성 컨테이너를 cpuset으로 노드 3(CPU 30-39, 70-79)에 고정했다(5단계). CI 러너 5개가 CPU 80개를 모두 나눠 가져서 runner-5 전부와 runner-4 일부는 노드 3과 겹친다.
- 메모리 예산: 질의 워커는 heap 4G(예약 5G)에 전체 예산 80G, 그래프 생성 컨테이너는 8G다. 노드 3(126G)에 runner-5(32G)까지 더해 120G다. runner-4가 노드 3을 얼마나 쓰는지는 재지 않았다(5단계).

### Joern MCP

- codebadger v0.7.0-beta를 쓴다(5단계 결정). 그래프를 내용 해시로 캐시하고 그래프마다 Joern 서버를 띄웠다 재우는 구조다. `/query-sync` 래퍼는 만들지 않았다.
- 패치 2개를 얹는다. 워커에 cpuset과 고정 heap을 넘기고, 그래프 제외 규칙을 최상위 `tests/` 하나로 줄인다. 이미지의 Joern은 4.0.680으로 바꿨다. 기본 4.0.594에서는 Q5가 1건 많고 메서드 수도 달랐다.
- MCP는 Xeon 루프백에만 열고 작업자 쪽은 SSH 터널로 붙는다. codebadger에는 MCP 인증 기능이 없다.
- Docker 저장소가 RAM tmpfs라 이미지를 디스크에 저장해 두고 부팅 때 복원한다. 2026-11-12 재부팅에서 이미지, codebadger 스택, 러너가 복원되는 것을 확인했다(6단계 기록 9절).
- Docker 소켓을 쓰므로 codebadger는 호스트 root와 같은 권한을 갖는다. Xeon은 CI 전용 서버라 받아들인다.

### 트리거와 저장

- Xeon에 시험 레포 전용 러너를 따로 등록했다(라벨 `joern`, ephemeral, 노드 3, 메모리 2g, 전용 uid). 기존 Xeon 러너는 다른 레포 전용이고, 개인 계정이라 러너는 레포 단위로만 등록된다(6단계).
- 러너는 프록시 컨테이너를 거쳐 MCP 4242에만 닿는다. 질의 워커, Postgres, Redis, 호스트 루프백에는 닿지 않는다.
- Joern에는 바뀐 파일만 반영하는 기능이 없다(3단계). PR이 열리거나 main이 바뀌면 그 SHA의 소스를 풀어 그래프를 처음부터 만든다. crewAI 기준 요청부터 ready까지 약 90초다.
- 그래프 저장은 codebadger 캐시(내용 해시)를 쓴다. 커밋 상태 `codeinside/joern-cpg`의 설명에 codebase_hash를 남겨 SHA와 그래프를 잇는다.
- 새 그래프가 만들어지는 동안에는 가장 가까운 조상 커밋의 그래프로 답하고 바뀐 파일 목록을 함께 준다(6단계 시험 통과). ast-grep과 Serena는 작업자 체크아웃에서 돌므로 SHA별 보관이 필요 없다.
- 보관: main first-parent 최근 20개와 열린 PR head의 그래프만 남기고, 그래프가 ready가 되면 풀어 둔 소스를 지운다. 정리 단계는 joern 러너가 하나라는 전제로 짰다.
- 포크에 딸려 온 업스트림 워크플로 19개는 Actions를 켜기 전에 `.github/workflows-upstream/`으로 옮겼다. 업스트림 워크플로 run은 0이다.
- 공개 레포라 워크플로는 포크에서 온 PR을 돌리지 않고, fork PR 승인 정책은 all_external_contributors다.

## 단계별 실행 계획

일곱 단계를 순서대로 진행한다. 각 단계는 codeinside의 Claude Code 작업자가 맡고, 끝내는 기준을 만족해야 다음으로 넘어간다.

1. **codeinside 레포 만들기 (완료, PR #1)**
    - 공개 레포 Munsik-Park/codeinside를 연결된 폴더와 이었다. 접속 정보는 올리지 않는다. README, CLAUDE.md, docs를 넣었다.
2. **Xeon 준비 (완료, PR #2)**
    - OpenJDK 21과 Joern v4.0.680을 joern 전용 계정 기준으로 설치했다. 설치 절차는 `scripts/xeon/install-joern.sh`.
3. **기준값 측정 (완료, PR #3)**
    - opensre `a5c1acbd`의 core와 전체로 그래프 생성, 적재, 질의 시간을 재고 부분 갱신 여부를 확인했다. 결과는 측정·검증 표 1~3행과 위험 표에 있다.
4. **ast-grep과 Serena 연결 (완료, PR #5)**
    - ast-grep 0.51.2와 공식 MCP, Serena 2.1.0(Pyright 1.1.403)을 작업자 쪽에 붙였다. Serena는 읽기 도구 5개만 켰다. Screening 규칙 5개와 후보 목록 스크립트를 넣었다. 결과는 위험 표와 [4단계 기록](measurements/2026-11-12-serena-joern/README.md)에 있다.
5. **Joern 서버와 MCP 연결 (완료, PR #7)**
    - codebadger를 Xeon에 올렸다. 패치 2개와 Joern 4.0.680 이미지로 Q1~Q5 결과와 그래프 규모가 3단계와 같았다. 질의 워커는 노드 3, heap 4G로 고정됐다. 작업 세션에서 Joern, ast-grep, Serena MCP를 모두 불러 답을 받았다. 결과는 위험 표와 [5단계 기록](measurements/2026-11-12-joern-mcp/README.md)에 있다.
6. **PR 자동 분석 (완료, PR #9, #10)**
    - 시험 대상을 crewAI 포크로 옮겼다(opensre 포크는 Actions가 GitHub 쪽에서 막힘). crewAI 기준값을 다시 재고, PR과 main 푸시마다 그래프를 만들어 커밋 상태에 codebase_hash를 남긴다. 조상 그래프 대체와 보관 정리까지 시험을 통과했다. 결과는 [6단계 기록](measurements/2026-11-12-pr-analysis/README.md)과 [crewAI 기준값](measurements/2026-11-12-crewai-baseline/README.md)에 있다.
7. **사용법 문서**
    - crewAI 커밋 하나를 놓고 세 도구를 준비하고 묻는 방법을 레포 docs/usage.md에 모은다. 명령은 4~6단계 기록에서 돌린 것을 쓴다.
    - 끝: 작업자가 문서의 명령을 crewAI에서 다시 돌려 결과를 기록했다.

## 측정·검증 항목

도구가 돌아가는지, 얼마나 걸리는지를 잰다. 결과 칸은 작업자가 채운다.

| # | 항목 | 재는 것 | 단계 | 비교 기준 | 결과 |
| --- | --- | --- | --- | --- | --- |
| 1 | 그래프 생성 시간 | core와 전체 각각 | 3 | 없음(처음 재는 값) | 프런트엔드: core 4.3초, 전체 11.9초. 적재(`importCpg`)는 전체 기준 약 46초 더 걸림 |
| 2 | 생성 중 최대 메모리와 그래프 크기 | core와 전체 각각 | 3 | 없음 | `-Xmx8G`에서 core 0.78GiB / 4.6MiB, 전체 3.96GiB / 29.7MiB. 전체는 `-Xmx1G`에서도 성공. 적재는 1G에서 OOM, 2G부터 성공(최대 3.60GiB) |
| 3 | 질의 응답 시간 | 호출 관계·데이터 흐름 질의 몇 개 | 3 | 없음 | 호출 관계 3개: 첫 실행 3~73ms, 다시 실행 1ms 안팎. 데이터 흐름 2개: 0.65~1.4초 |

3행까지의 측정 조건, 명령, 원본 수치는 [measurements/2026-11-11-baseline](measurements/2026-11-11-baseline/README.md)에 있다. 측정 커밋은 opensre `a5c1acbd`, 실행 위치는 NUMA 노드 3이다.

crewAI 기준값(6단계, 커밋 `71d68117`): 파일 984, 메서드 36,950, 호출 254,956. 요청부터 ready까지 94초, Q1~Q5는 29/18/64/6/1,634건이다. 기록은 [crewAI 기준값](measurements/2026-11-12-crewai-baseline/README.md)에 있다.

## 확인되지 않은 것과 위험

가장 큰 미확인이던 Joern 부분 갱신은 불가로 확인됐다. 커밋마다 새로 만들어도 약 1분이라 운영에는 문제없다. opensre 규모의 메모리·시간과 Xeon 속도에 대한 걱정은 3단계 측정으로 해소됐다.

| 항목 | 상태 | 대응 |
| --- | --- | --- |
| Joern 부분 갱신 | 없음(3단계 확인) | 커밋마다 새로 만든다. 만드는 동안에는 조상 그래프로 답한다 |
| Joern의 Python 호출 연결 | 이름으로 잇는다(3단계). 흔한 이름은 실제 호출자 5개 중 1개만 맞음(4단계) | 정확한 참조는 Serena가 맡는다. 흔한 이름이나 다시 내보낸 심볼은 Joern 호출 관계를 쓰지 않는다 |
| Python 3.12 `type` 문 파싱 실패 | opensre에서 9개 파일(3단계) | 파일 전체가 빠지지는 않는다. 데모에서 한계로 설명한다 |
| `-J-Xmx`가 스크립트 JVM에 안 닿음 | 3단계 실측 | `JAVA_TOOL_OPTIONS`로 준다. 서버 모드는 JVM 하나라 그대로 닿는다(5단계) |
| ast-grep 공식 MCP | 스스로 실험 단계라고 밝힘 | 사전 스크립트는 MCP 없이 CLI를 직접 부른다 |
| Joern 서버 격리 없음 | 문서에 명시 | 내부망 전용, 외부 노출 금지. codebadger 질의 워커는 인증 없이 브리지 네트워크 안에만 열린다. 외부에서 닿는지는 시험 안 함 |
| Serena·codebadger 라이선스 | 둘 다 GPL-3.0(Serena는 앱만) | 사내 사용은 문제없다. 고친 버전을 배포할 때만 소스 공개 의무가 생긴다 |
| Serena 편집·셸 도구 | 읽기 도구 5개만 켬(4단계 확인) | 도구 인터페이스, fixed_tools, read_only. 편집·셸 도구를 부르면 Unknown tool로 거부된다 |
| Pyright 가상환경 | opensre 의존성 없이 돌림(4단계) | 서드파티 타입이 풀리지 않는다. 가상환경을 주면 결과가 달라지는지는 확인 안 됨 |
| 작업 세션의 MCP 질의 | 세 MCP 모두 작업 세션에서 호출 확인(5단계) | 해결됨. 헤드리스 세션에서 Q4 데이터 흐름과 ast-grep·Serena 참조를 받았다 |
| SHA별 그래프 누적 | crewAI 그래프 하나 약 18MB, 풀어 둔 소스 623MB(ready 뒤 삭제) | main 최근 20개와 열린 PR head만 남긴다(6단계 구현). 실패 그래프 정리와 20개 초과 동작은 확인 안 됨 |
| Docker 저장소가 RAM tmpfs | 재부팅하면 이미지와 컨테이너가 사라짐 | 이미지를 디스크에 저장하고 부팅 복원 유닛 2개를 켰다(5단계). 재부팅 복원 확인함(6단계 기록 9절) |
| codebadger MCP 인증 | 기능 없음 | Xeon 루프백에만 열고 작업자 쪽은 SSH 터널로 붙는다 |
| 노드 3 메모리 | 질의 80G + 생성 8G + runner-5 32G = 120G / 126G | runner-4가 노드 3을 얼마나 쓰는지는 재지 않음 |
| codebadger 패치 | v0.7.0-beta에 패치 2개 | codebadger를 올릴 때 패치가 맞는지 다시 확인한다. 이미지를 다시 빌드하면 디스크 저장도 다시 한다 |
| opensre 포크 Actions | GitHub 쪽에서 막힘. 지원팀이 풀 수 없다고 답함 | 6단계부터 crewAI 포크를 쓴다. opensre 기록은 그대로 둔다 |
| 디스크 이미지 묶음 | MCP 이미지를 다시 빌드하면 디스크 묶음은 이전 이미지로 남음 | 다시 빌드할 때마다 저장 스크립트를 다시 실행한다(sudo). 6단계 이미지는 재부팅 전에 다시 저장했고, 러너·프록시 유닛과 함께 재부팅 복원을 확인했다(6단계 기록 9절) |

## 남은 결정

지금 정할 것은 없다. 통합 MCP 앞단은 보류다.

- [x] codeinside 레포: Munsik-Park/codeinside, 공개로 정함
- [x] 뒤에 붙일 도구: ast-grep, Serena, Joern
- [x] Joern MCP: codebadger(패치 2개, Joern 4.0.680)로 정함 (단계 5)
- [x] Joern 메모리와 노드: 워커 heap 4G, 질의 예산 80G, 생성 컨테이너 8G, 노드 3 고정으로 정함 (단계 5)
- [x] 그래프 저장과 보관: codebadger 캐시와 커밋 상태, main 최근 20개와 열린 PR head로 정함 (단계 6)
- [ ] 통합 MCP 앞단: AI가 도구 선택을 헷갈릴 때 (보류)

## 출처

- [Joern README — JDK 21 요구](https://github.com/joernio/joern)
- [Joern 서버 모드 — 격리 없음, basic auth](https://docs.joern.io/server/)
- [Joern 설치 — 메모리, -Xmx, importCpg](https://docs.joern.io/installation/)
- [ast-grep 공식 MCP — 도구 4개, 실험 단계](https://mcpservers.org/en/servers/ast-grep/ast-grep-mcp)
- [Serena — 앱 GPL-3.0, SolidLSP MIT](https://github.com/oraios/serena)
- [codebadger(Joern MCP) — GPL-3.0, Docker·Postgres·Redis](https://github.com/Lekssays/codebadger)
- [3단계 측정 기록](measurements/2026-11-11-baseline/README.md)
- [4단계 비교 기록 — ast-grep 재현성, Serena·Joern 비교](measurements/2026-11-12-serena-joern/README.md)
- [Serena 설정 — 도구 인터페이스와 REPL](https://github.com/oraios/serena/blob/v2.1.0/docs/02-usage/050_configuration.md)
- [5단계 기록 — codebadger 설치, Q1~Q5 비교, 메모리·NUMA 고정](measurements/2026-11-12-joern-mcp/README.md)
- [codebadger 보안 문서 — Docker 소켓, 전용 호스트 권장](https://github.com/Lekssays/codebadger/blob/v0.7.0-beta/docs/security.md)
- [6단계 기록 — opensre에서 막힌 경위, crewAI 포크, 러너·프록시·워크플로, 보관 정리](measurements/2026-11-12-pr-analysis/README.md)
- [crewAI 기준값 — 제외 규칙, Q1~Q5, Serena·Joern 비교](measurements/2026-11-12-crewai-baseline/README.md)
- [Munsik-Park/crewAI 포크](https://github.com/Munsik-Park/crewAI)
- [Intel Xeon E7-4820 v4 사양](https://www.intel.com/content/www/us/en/products/sku/93814/intel-xeon-processor-e74820-v4-25m-cache-2-00-ghz/specifications.html)
- [포크 해제 — 이슈·PR 소실](https://docs.github.com/en/pull-requests/how-tos/work-with-forks/detaching-a-fork)
