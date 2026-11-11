# 2026-11-12 Joern 서버와 MCP 연결 (단계 5)

[docs/plan.md](../../plan.md) 단계 5의 원본 기록이다. 비교 기준은 [3단계 기록](../2026-11-11-baseline/README.md)의 Q1~Q5다. plan.md와 architecture.md는 이 PR에서 고치지 않았다.

## 결과 요약

| 끝내는 기준 | 결과 | 근거 |
| --- | --- | --- |
| 작업 세션에서 MCP로 데이터 흐름을 물어 답을 받았다 | Claude Code 헤드리스 세션이 Joern MCP의 `run_cpgql_query`로 Q4(데이터 흐름)를 물어 흐름 4개와 각 경로를 받았다. 같은 세션에서 ast-grep MCP(146건)와 Serena MCP(103개 파일)도 불렀다 | 아래 5절, [raw/claude-session-mcp.jsonl](raw/claude-session-mcp.jsonl) |
| Q1~Q5를 3단계와 비교한 표 | Joern 4.0.680 이미지에서 Q1~Q5 결과 수와 그래프 규모가 3단계와 모두 같다. codebadger 원래 이미지(Joern 4.0.594)에서는 Q5가 332건(3단계 331건)이었다 | 아래 3절 |
| 메모리 상한과 NUMA 고정이 실제로 걸렸다는 근거 | 질의 워커: cgroup `cpuset.cpus.effective=30-39,70-79`, `cpuset.mems.effective=3`, `memory.max` 5GiB, JVM `MaxHeapSize` 4GiB. `joern --server`는 JVM 하나로 뜨고 `JAVA_TOOL_OPTIONS`도 그 JVM에 닿는다 | 아래 2절, [raw/probe-worker-joern-4.0.680.log](raw/probe-worker-joern-4.0.680.log), [raw/server-jto-probe-joern-4.0.680.log](raw/server-jto-probe-joern-4.0.680.log) |

결론: codebadger를 쓴다. 패치 두 개(워커 NUMA 고정과 heap 고정, 그래프 제외 규칙)와 Joern 4.0.680 이미지로 결과와 메모리 통제가 모두 맞았다. 그래서 `/query-sync` 래퍼는 만들지 않았다.

## 측정 조건

| 항목 | 값 |
| --- | --- |
| 대상 커밋 | Munsik-Park/opensre `a5c1acbd4b7e61e3cb57de6b84fac7031555a0a4`. Xeon의 3단계 체크아웃에서 `git archive`로 codebadger playground에 풀었다 |
| 그래프 범위 | 3단계와 같이 최상위 `tests/`만 뺐다(`--exclude-regex (tests(?:/.*)?)`) |
| codebadger | v0.7.0-beta(커밋 `1eccd4b35cc932eded4930c9f42d142c2f9ded01`, 2026-08-21 릴리스). `/health`는 버전을 `0.6.2-beta`로 보고한다 |
| Joern | codebadger Dockerfile 기본 4.0.594로 한 번, 4.0.680으로 바꿔 한 번. 둘 다 eclipse-temurin 21 이미지(JDK 21.0.13) |
| 실행 방식 | Docker Compose 전체 스택(MCP, 그래프 생성 컨테이너, Postgres 16, Redis 7). `JOERN_WORKER_MODE=pool`이라 CPG마다 질의 워커 컨테이너가 따로 뜬다 |
| Xeon Docker | Docker 29.6.2, Compose v5.3.1. CI 러너 5개와 같은 데몬을 쓴다. 러너 설정은 바꾸지 않았다 |
| 작업자 쪽 연결 | MCP는 Xeon 루프백(127.0.0.1:4242)에만 열고, 작업자 쪽에서 SSH 터널로 붙었다 |
| 질의 시간 | 질의 안의 `System.nanoTime`(Joern 안 실행 시간)과 MCP 호출 왕복 시간을 함께 잰다([scripts/queries.py](scripts/queries.py)) |

## 1. 설치

| 구성 | 내용 | 출처 |
| --- | --- | --- |
| 설치 방법 | `git clone --branch v0.7.0-beta`, `.env` 작성, `docker compose build`, `docker compose up -d` | codebadger [docs/installation.md "A. Full stack with Docker"](https://github.com/Lekssays/codebadger/blob/v0.7.0-beta/docs/installation.md) |
| 배포 스크립트 | [scripts/xeon/deploy-codebadger.sh](../../../scripts/xeon/deploy-codebadger.sh). 체크아웃을 태그로 되돌리고 패치와 compose override를 얹은 뒤 빌드한다 | |
| 패치 | [config/codebadger/codebadger-v0.7.0-beta.patch](../../../config/codebadger/codebadger-v0.7.0-beta.patch), [config/codebadger/codebadger-joern-4.0.680.patch](../../../config/codebadger/codebadger-joern-4.0.680.patch). codebadger 소스는 레포에 복사하지 않았다 | |
| compose override | [config/codebadger/docker-compose.override.yml](../../../config/codebadger/docker-compose.override.yml). Postgres 비밀번호를 `.env` 값으로 바꾸고, 패치가 읽는 환경 변수를 넘긴다 | |
| 로컬 설정 | Xeon의 `.env`(권한 600, 커밋하지 않음). 형식은 [config/codebadger/env.example](../../../config/codebadger/env.example) | |
| 이미지 크기 | `codebadger-joern-server` 5.31GB(Rust 툴체인 포함), `codebadger-mcp` 728MB, `postgres:16` 636MB, `redis:7` 168MB | `docker images` |

### 패치 내용

| 파일 | 바꾼 것 | 이유 |
| --- | --- | --- |
| `src/services/joern_server_manager.py` | 워커 `containers.run`에 `JOERN_WORKER_CPUSET_CPUS`, `JOERN_WORKER_CPUSET_MEMS`를 `cpuset_cpus`, `cpuset_mems`로 넘긴다 | 원본에는 cpuset 설정이 없어 NUMA 노드 고정을 걸 수 없다 |
| 같은 파일 `_plan_server` | `JOERN_WORKER_HEAP_GB`가 있으면 그 값으로 heap을 고정하고 예약량을 heap+1G로 둔다 | 원본은 메모리 예산이 0보다 크면 CPG 크기로 tier를 고른다. 30MB 그래프는 tier S(heap 2G, cap 3G)가 되어 4G 상한을 줄 수 없다([src/utils/recommend.py `DEFAULT_TIERS`](https://github.com/Lekssays/codebadger/blob/v0.7.0-beta/src/utils/recommend.py)). 예산은 0으로 두어도 시작할 때 호스트 RAM으로 다시 계산된다(`src/startup_tuning.py`) |
| `config.example.yaml` | `exclusion_patterns`를 최상위 `tests/` 하나로 줄였다 | 기본 규칙은 숨김 폴더, `test*`, `integration*`, `docs/`, `build*` 등을 뺀다. 그대로 두면 Q4의 `.github/ci/git_changes.py`와 opensre `integrations/`가 빠진다. MCP 이미지는 이 파일을 `config.yaml`로 복사하고, 이 설정은 환경 변수로 바꿀 수 없다(codebadger docs/configuration.md) |
| `Dockerfile`(두 번째 패치) | `JOERN_VERSION` 4.0.594 → 4.0.680 | 3단계와 버전을 맞춰 Q5 차이의 원인을 가린다 |

Joern은 `--exclude-regex`를 입력 폴더 기준 상대 경로에 맞춘다([x2cpg SourceFiles.scala v4.0.594 `isIgnoredByRegex`](https://github.com/joernio/joern/blob/v4.0.594/joern-cli/frontends/x2cpg/src/main/scala/io/joern/x2cpg/SourceFiles.scala)). 그래서 패턴을 `tests(?:/.*)?`로 썼다. 실제 실행 명령은 [raw/codebadger-mcp-joern-4.0.680.log](raw/codebadger-mcp-joern-4.0.680.log)에 있다.

### 공개 범위와 인증

| 대상 | 바인드 | 인증 | 근거 |
| --- | --- | --- | --- |
| codebadger MCP | 호스트 127.0.0.1:4242 | 없음(codebadger에 MCP 인증 기능이 없다). 작업자 쪽은 SSH 터널로 붙는다 | [raw/probe-worker-joern-4.0.680.log](raw/probe-worker-joern-4.0.680.log), `/health` 경고 |
| 그래프 생성 컨테이너 | 호스트 127.0.0.1:13371~13870 (500개) | 해당 없음 | 같은 로그 |
| Postgres, Redis | 호스트 127.0.0.1:55432, 56379 | Postgres는 `.env`의 무작위 비밀번호 | 같은 로그, compose override |
| 질의 워커(`joern --server`) | 컨테이너 안 모든 주소의 8080(`--server-host 0.0.0.0`, `/proc/net/tcp6`에서 `::`). 호스트로 공개한 포트는 0개이고 `codebadger` 브리지 네트워크에만 붙는다 | 없음. 워커가 `--server-auth-*` 없이 뜬다 | 같은 로그, [src/services/joern_server_manager.py `_start_worker_container`](https://github.com/Lekssays/codebadger/blob/v0.7.0-beta/src/services/joern_server_manager.py) |

- 호스트에서 열린 codebadger 쪽 포트 503개는 모두 127.0.0.1이다.
- `codebadger` 네트워크에 붙은 컨테이너는 codebadger 컨테이너 5개뿐이다. CI 러너 컨테이너는 이 네트워크에 없다.
- 인증 없는 워커에 닿는 경로는 같은 브리지 네트워크의 컨테이너와 Xeon 호스트 자신이다. 외부에서 닿는지는 따로 시험하지 않았다.
- `/health`는 `MCP is bound to all interfaces (MCP_HOST=0.0.0.0) and has no built-in auth`라고 경고한다. 이는 컨테이너 안 바인드를 보고 낸 경고이고, 호스트 공개는 127.0.0.1뿐이다. 로컬 소스는 `ALLOWED_SOURCE_ROOTS=/app/playground`로 playground 안으로 묶었다.

## 2. 메모리 상한과 NUMA 고정

### codebadger 질의 워커 (Joern 4.0.680)

[scripts/probe-worker.sh](scripts/probe-worker.sh)로 컨테이너 설정, cgroup 값, 컨테이너 안 JVM을 봤다([raw/probe-worker-joern-4.0.680.log](raw/probe-worker-joern-4.0.680.log)).

| 항목 | 값 |
| --- | --- |
| docker HostConfig | `CpusetCpus=30-39,70-79`, `CpusetMems=3`, `Memory=5368709120` |
| cgroup | `cpuset.cpus.effective=30-39,70-79`, `cpuset.mems.effective=3`, `memory.max=5368709120`, `memory.peak=3843874816` |
| 컨테이너 안 JVM | `io.joern.joerncli.console.ReplBridge --server` 하나. `MaxHeapSize=4294967296`, `InitialHeapSize=2147483648` |
| JVM에 넘어간 옵션 | `JAVA_OPTS=-Xmx4G -Xms2G -XX:+UseG1GC ...`(codebadger가 환경 변수로 넘긴다) |
| 프로세스 허용 범위 | `Cpus_allowed_list: 30-39,70-79`, `Mems_allowed_list: 3` |

NUMA 노드 3의 CPU는 `numactl -H` 기준 30-39, 70-79다. 4.0.594 이미지에서도 같은 값이었다([raw/probe-worker-joern-4.0.594.log](raw/probe-worker-joern-4.0.594.log)).

### 그래프 생성 컨테이너

compose 사양에는 `cpuset`(CPU)만 있고 메모리 노드 항목이 없다([compose-spec schema](https://github.com/compose-spec/compose-spec/blob/main/schema/compose-spec.json)). 그래서 override에서 CPU를 고정하고, 배포 스크립트가 `docker update --cpuset-cpus ... --cpuset-mems 3`을 한다. 결과 cgroup은 `cpuset.cpus.effective=30-39,70-79`, `cpuset.mems.effective=3`, `memory.max` 16GiB(`JOERN_MEM_LIMIT=16g`)다. 프런트엔드 heap은 codebadger가 `CPG_BUILD_HEAP_GB=4`로 `-Xmx4G`를 준다.

### `JAVA_TOOL_OPTIONS`가 `joern --server` JVM에 닿는가

3단계에서 `joern --script`는 JVM을 하나 더 띄워 `-J-Xmx`가 닿지 않았다. 서버 모드는 Xeon 호스트의 Joern 4.0.680에서 따로 쟀다([scripts/server-jto-probe.sh](scripts/server-jto-probe.sh), [raw/server-jto-probe-joern-4.0.680.log](raw/server-jto-probe-joern-4.0.680.log)).

```sh
JAVA_TOOL_OPTIONS=-Xmx4G numactl --cpunodebind=3 --membind=3 \
  joern --server --server-host 127.0.0.1 --server-port <포트> --server-auth-username ... --server-auth-password ...
```

- 뜨는 JVM은 `ReplBridge --server` 하나다. 자식 JVM은 없었다.
- `Picked up JAVA_TOOL_OPTIONS: -Xmx4G`가 한 번 찍히고 `MaxHeapSize=4294967296`이다.
- `numactl --membind`는 cpuset이 아니라 메모리 정책으로 걸린다. `/proc/<pid>/numa_maps`의 매핑 454개가 모두 `bind:3`이었다. 페이지 대부분이 N3에 있고(N3=155,636), 나머지 노드의 페이지는 공유 라이브러리로 보이지만 확인하지 않았다.
- basic auth: 인증을 붙인 `/query-sync`는 HTTP 200, 인증 없이 보내면 HTTP 401이었다.
- 서버 명령줄(`java_command`)에 인증 사용자와 비밀번호가 그대로 보인다. 로그에서는 가렸고, 시험에 쓴 인증 파일의 비밀번호는 한 번 바꿨다.

## 3. Q1~Q5 비교

질의 식은 3단계 [queries.sc](../2026-11-11-baseline/scripts/queries.sc)와 같다. codebadger의 `run_cpgql_query`는 질의를 `(<질의>).take(N).toJsonPretty`로 감싸므로, 결과 크기와 시간을 한 줄 List로 돌려받았다. 질의 문자열에 run 번호를 넣어 codebadger의 결과 캐시(`query.cache_ttl` 300초)를 피했다.

### 결과 수

| # | 질의 | 3단계 (4.0.680, `joern --script`) | codebadger + Joern 4.0.594 | codebadger + Joern 4.0.680 |
| --- | --- | --- | --- | --- |
| Q1 | `record_evidence_entry`를 부르는 함수 | 131 | 131 | 131 |
| Q2 | `maybe_raise_credit_exhausted`가 부르는 이름 | 20 | 20 | 20 |
| Q3 | Q1 호출자를 부르는 함수 | 2 | 2 | 2 |
| Q4 | `git` 매개변수 → `subprocess.check_output` 인자 흐름 | 4 | 4 | 4 |
| Q5 | Q1 호출자 매개변수 → `record_evidence_entry` 인자 흐름 | 331 | **332** | 331 |

| 그래프 규모 | 3단계 | 4.0.594 | 4.0.680 |
| --- | --- | --- | --- |
| 파일 | 2,353 | 2,353 | 2,353 |
| 메서드 | 49,754 | 58,063 | 49,754 |
| 호출 | 469,749 | 469,628 | 469,749 |
| overlay | `base, controlflow, typerel, callgraph, dataflowOss, pysrc2cpg-postprocessing` | `pysrc2cpg-postprocessing` 없음 | 3단계와 같음 |

Q5 차이는 Joern 버전 때문이다. 이미지의 Joern만 4.0.680으로 바꾸자 결과 수, 메서드·호출 수, overlay 목록이 모두 3단계와 같아졌다. 소스, 제외 규칙, codebadger 코드는 두 실행에서 같다. 4.0.594에서 늘어난 1건이 어느 흐름인지는 보지 않았다.

### 응답 시간

Joern 안 실행 시간(ms). 괄호 안은 작업자 쪽에서 잰 MCP 호출 왕복 시간(초)이다.

| # | 3단계 2G 첫 / 둘째 | 4.0.594 run1 / run2 | 4.0.680 run1 / run2 |
| --- | --- | --- | --- |
| Q1 | 70.2 / 0.7 | 32.5 (0.24) / 0.43 (0.14) | 22.2 (0.27) / 0.41 (0.14) |
| Q2 | 5.5 / 0.2 | 0.17 (0.17) / 0.14 (0.12) | 0.19 (0.19) / 0.18 (0.13) |
| Q3 | 4.6 / 0.6 | 2.6 (0.16) / 0.73 (0.13) | 2.1 (0.15) / 1.3 (0.17) |
| Q4 | 1,365.2 / 654.8 | 1,618.0 (1.82) / 891.0 (1.05) | 1,275.6 (1.43) / 717.7 (0.89) |
| Q5 | 914.9 / 817.6 | 1,500.7 (1.66) / 1,057.6 (1.24) | 1,304.5 (1.48) / 820.9 (0.99) |

- 3단계 2G는 heap 2G, codebadger는 heap 4G다.
- codebadger의 run1은 서버가 처음 받은 질의가 아니다. 4.0.680은 그래프 규모 질의를, 4.0.594는 문법 오류로 실패한 질의 10개를 먼저 받았다. 그래서 3단계의 첫 실행과 똑같은 조건은 아니다.
- MCP 왕복에는 작업자 쪽에서 Xeon까지의 SSH 터널, codebadger의 질의 검사와 결과 직렬화가 들어 있다. 호출 관계 질의(Q1~Q3)는 왕복 0.12~0.27초다.

### 그래프 생성과 적재 시간 (Joern 4.0.680)

| 단계 | 시간 | 근거 |
| --- | --- | --- |
| `generate_cpg` 요청부터 `ready`까지 | 95초(5초 간격 polling) | [raw/codebadger-summary-joern-4.0.680.txt](raw/codebadger-summary-joern-4.0.680.txt) |
| 프런트엔드(pysrc2cpg) | 약 13초(16:51:15 → 16:51:28) | [raw/codebadger-mcp-joern-4.0.680.log](raw/codebadger-mcp-joern-4.0.680.log) |
| 워커 JVM 기동 | 약 13초(→ 16:51:41) | 같은 로그 |
| 그래프 적재와 확인 | 약 61초(→ 16:52:42) | 같은 로그 |

3단계는 프런트엔드 11.85초, `importCpg` 약 46초였다.

## 4. 래퍼를 만들지 않은 이유

plan.md는 결과나 메모리 통제가 맞지 않으면 `/query-sync` 래퍼를 직접 만들기로 했다. 패치와 Joern 4.0.680 이미지로 두 조건이 모두 맞아 codebadger를 쓴다. 대신 아래는 codebadger 원본 그대로는 안 되므로 패치를 유지해야 한다.

- 워커 NUMA 고정, heap 고정, 그래프 제외 규칙, Joern 버전
- 워커 basic auth는 패치하지 않았다. 호스트로 공개하지 않는 것으로 대신했다.

## 5. Claude Code 작업 세션에서 MCP 질의

[scripts/run-session.sh](scripts/run-session.sh)로 `claude -p` 헤드리스 세션을 띄웠다. `--mcp-config`에 joern(codebadger, SSH 터널 주소), ast-grep, serena 세 서버만 넣고 `--strict-mcp-config`로 다른 MCP 설정을 끊었다. 내장 도구는 `--tools ""`로 껐다. 원본 stream-json에서 MCP 호출과 결과만 남겼다([scripts/filter-session.py](scripts/filter-session.py), [raw/claude-session-mcp.jsonl](raw/claude-session-mcp.jsonl)).

| 서버 | 상태 | 부른 도구 | 받은 답 |
| --- | --- | --- | --- |
| joern (codebadger) | connected | `run_cpgql_query`(Q4를 경로 문자열로 바꾼 식) | 흐름 4개, 각 흐름의 경로(`args@9 -> ... -> subprocess.check_output(...)@11` 등). 결과 수는 Q4와 같다 |
| ast-grep | connected | `find_code`(`record_evidence_entry($$$)`) | `Found 146 matches` |
| serena | connected | `find_referencing_symbols`(`record_evidence_entry`) | 첫 호출은 결과가 71,634자라 Claude Code가 도구 결과 한도를 넘었다며 파일로 돌렸다. 세션이 `include_kinds`/`exclude_kinds`로 나눠 다시 불렀고, 103개 파일 249개 참조를 받았다 |

- 세션: 6턴, 75.4초, 비용 $0.98, 모델 `claude-opus-5-5`.
- 4단계에서 확인하지 못한 "작업 세션 안에서 ast-grep, Serena MCP 호출"은 이 기록으로 확인했다.
- Serena 결과가 크면 한 번에 받지 못한다. 흔한 이름을 물을 때는 `include_kinds`로 나누거나 `max_answer_chars`를 줄여야 한다.

## 6. Xeon에 남는 것

| 항목 | 상태 |
| --- | --- |
| codebadger 스택 | 컨테이너 5개(`restart: unless-stopped`). opensre `a5c1acbd` 그래프 하나가 적재돼 있다 |
| 저장 공간 | containerd 저장소(`/var/lib/containerd`)가 64G tmpfs다. 4.0.680 재빌드 뒤 43G를 썼다. 빌드 전 사용량은 재지 않아 codebadger 몫은 정확히 모른다. 재부팅하면 이미지가 사라져 다시 빌드해야 한다 |
| 메모리 예산 | codebadger는 메모리 예산을 호스트 전체 RAM으로 계산한다(질의 풀 444GB, 동시 서버 상한 88). 노드 3(약 126GB)이나 CI 러너를 고려하지 않는다 |
| 인증 파일 | 서버 모드 시험에 쓴 joern 계정의 인증 파일(권한 600)이 남아 있다 |

## 확인 안 됨

- 4.0.594에서 Q5가 1건 많았던 흐름이 무엇인지, 메서드 수가 8,309개 많았던 이유
- 인증 없는 질의 워커에 Xeon 밖에서 닿지 않는지(외부에서 시험하지 않았다)
- `numa_maps`에서 N0~N2에 잡힌 페이지가 공유 라이브러리인지
- 그래프 생성 컨테이너 안 pysrc2cpg JVM의 heap을 jcmd로 재지 않았다(로그의 `-Xmx4G`만 확인)
- codebadger의 `run_cpgql_query` 검사(denylist)가 3단계 질의 말고 다른 질의를 막는지. codebadger security.md는 이 검사를 경계가 아닌 보조 장치로 본다
- `/health`가 버전을 `0.6.2-beta`로 보고하는 이유

## 원본 파일

| 파일 | 내용 |
| --- | --- |
| `raw/deploy-joern-{4.0.594,4.0.680}.log` | 배포 스크립트 출력 일부(빌드 단계, 컨테이너 기동, `/health`) |
| `raw/codebadger-mcp-joern-4.0.680.log` | codebadger MCP 로그 일부(시작 설정, 그래프 생성 명령, heap 고정, cpuset, 적재 완료) |
| `raw/codebadger-tools-list.jsonl` | codebadger MCP `tools/list` |
| `raw/codebadger-{generate,status,stats,queries}-joern-{4.0.594,4.0.680}.jsonl` | 그래프 생성 요청, 상태, 규모, Q1~Q5 응답 |
| `raw/codebadger-summary-joern-4.0.680.txt` | `run-codebadger.sh` 요약 |
| `raw/probe-worker-joern-{4.0.594,4.0.680}.log` | 워커와 생성 컨테이너의 cpuset, cgroup, JVM heap, 바인드 |
| `raw/server-jto-probe-joern-4.0.680.log` | 호스트 `joern --server`의 `JAVA_TOOL_OPTIONS`, NUMA 정책, basic auth |
| `raw/claude-session-mcp.jsonl` | Claude Code 세션의 MCP 호출과 결과(작업 환경 정보는 뺐다) |
| `scripts/` | 위 기록을 만든 스크립트. `queries.py`는 3단계 질의를 MCP 호출로 바꾼다 |
