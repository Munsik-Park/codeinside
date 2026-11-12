# 2026-11-12 crewAI 기준값 (단계 6, 시험 대상 변경)

6단계 시험 대상을 opensre에서 crewAI로 바꾸면서 3~5단계 기준값을 crewAI에서 다시 쟀다. 대상을 바꾼 경위는 [6단계 기록](../2026-11-12-pr-analysis/README.md)에 있다. plan.md와 architecture.md는 이 기록에서 고치지 않았다.

## 결과 요약

| 항목 | 결과 | 근거 |
| --- | --- | --- |
| 기준 커밋 그래프 | 파일 984, 메서드 36,950, 호출 254,956. `cpg.bin` 18,009,135 B | 아래 2절, [raw/build/stats.jsonl](raw/build/stats.jsonl) |
| 생성·적재 시간 | 프런트엔드 13초, 워커 기동 14초, 적재 42초. `generate_cpg` 요청부터 ready까지 94초 | 아래 2절, [raw/build/codebadger.log](raw/build/codebadger.log) |
| 최대 메모리 | 생성 컨테이너 2.15 GiB(상한 8G), 질의 워커 컨테이너 2.78 GiB(상한 5G), 워커 heap 사용 1.70 GB(상한 4G) | 아래 3절 |
| 노드 3 예산(80G)과 워커 heap 4G | 충분하다. crewAI 워커 하나의 예약은 opensre와 같은 5G다 | 아래 3절 |
| Q1~Q5 | 29, 18, 64, 6, 1,634건. 질의 안 실행 시간은 Q1~Q3 1ms 안팎(두 번째), Q4 0.6초, Q5 3.9초 | 아래 4절, [raw/queries.jsonl](raw/queries.jsonl) |
| Serena와 Joern 비교 | Q1은 실제 호출 28쌍이 모두 일치했다. Joern에만 있는 1쌍은 합성 메서드다. C1 `Memory.close`는 Joern 7쌍이 모두 오탐이고 Serena 실제 호출은 테스트 밖에 없다 | 아래 5절 |
| 모노레포 Pyright 설정 | 기본 설정에서는 `lib/*/tests`와 다른 패키지의 import가 풀리지 않는다. `extraPaths`에 `lib/*/src` 6개를 넣으면 테스트 쪽 참조가 더 잡힌다 | 아래 5절, [config/serena/crewai/pyrightconfig.json](../../../config/serena/crewai/pyrightconfig.json) |
| ast-grep 후보 목록 재현성 | 같은 커밋에서 두 번 만든 목록의 SHA-256이 같다(`f34e56b6…`) | 아래 6절, [raw/astgrep-hash.log](raw/astgrep-hash.log) |

## 측정 조건

| 항목 | 값 |
| --- | --- |
| 대상 커밋 | Munsik-Park/crewAI `71d68117e38f620dff02ec1dc358f37a1f74a740`(포크 시점 main, 업스트림 main과 같음) |
| 소스 | GitHub에서 그 SHA만 받아 `git archive`로 codebadger playground에 풀었다(623MB) |
| 그래프 제외 규칙 | 최상위 `tests/`, `lib/[^/]+/tests(?:/.*)?`, `lib/crewai-core/src/crewai_core/platform_catalog\.py`. 아래 1절 |
| codebadger | v0.7.0-beta, 패치 2개(5단계)에 제외 규칙 2줄을 더한 MCP 이미지. Joern 4.0.680 |
| 질의 워커 | heap 4G 고정, 예약 5G, cpuset `30-39,70-79`, mems 3(5단계와 같음) |
| 질의 경로 | Xeon의 분석 러너 네트워크에 붙인 일회용 컨테이너에서 MCP 프록시로 부른다([scripts/xeon/joern-ci/tcp_proxy.py](../../../scripts/xeon/joern-ci/tcp_proxy.py)). 작업 세션이 쓰는 SSH 터널은 거치지 않는다 |
| 작업자 쪽 | Serena 2.1.0(Pyright 1.1.403), ast-grep 0.51.2. crewAI 체크아웃은 codeinside 폴더 밖에 두었고 기록에서는 `$CREWAI_DIR`로 적는다 |

## 1. 그래프 제외 규칙

codebadger의 제외 규칙은 레포마다 줄 수 없고 MCP 이미지 안의 `config.yaml` 하나다. 그래서 5단계 패치([config/codebadger/codebadger-v0.7.0-beta.patch](../../../config/codebadger/codebadger-v0.7.0-beta.patch))에 두 줄을 더하고 MCP 이미지만 다시 빌드했다.

```yaml
exclusion_patterns:
  - "tests(?:/.*)?"
  - "lib/[^/]+/tests(?:/.*)?"
  - "lib/crewai-core/src/crewai_core/platform_catalog\\.py"
```

| 대상 | 기존 규칙으로 빠지는 Python 파일 | 새 규칙으로 빠지는 Python 파일 | 근거 |
| --- | --- | --- | --- |
| opensre `a5c1acbd` | 1,355 | 1,355(차이 0) | 두 커밋의 GitHub tree를 같은 정규식(전체 일치)으로 대조했다. opensre에는 `lib/`가 없다 |
| crewAI `71d68117` | 0 | 532(테스트 531, catalog 1) | 같은 방법 |

- crewAI Python은 1,515개, 22.1MB다. 테스트 폴더가 7.0MB, `platform_catalog.py` 한 파일이 7.8MB다.
- codebadger는 패턴을 `(p1)|(p2)|(p3)`로 묶어 `--exclude-regex` 하나로 넘긴다(`src/tools/core_tools.py` 1158~1188행). pysrc2cpg는 입력 폴더 기준 상대 경로에 전체 일치로 맞춘다(5단계 기록).
- 배포: [scripts/xeon/deploy-codebadger.sh](../../../scripts/xeon/deploy-codebadger.sh)에 `CB_BUILD_SERVICES`를 더해 `codebadger-mcp`만 다시 빌드하고 다시 띄웠다. Joern 이미지는 그대로다. 새 MCP 이미지 ID는 `766f3227db26`이다.
- 패치를 다시 적용하기 전과 뒤의 `git diff`는 제외 규칙 4줄(주석 2줄 포함)만 다르다.
- 이미지를 디스크에 저장한 묶음(5단계 7절)은 이전 MCP 이미지다. 묶음을 갱신하지 않으면 재부팅 뒤 예전 규칙으로 돌아간다. 갱신은 sudo가 필요해 아직 하지 않았다.

### 제외 규칙 없이 만들었을 때

6단계 첫 시험 run(crewAI PR #1, 커밋 `60ab746`)은 최상위 `tests/`만 뺀 규칙으로 돌았다([6단계 기록](../2026-11-12-pr-analysis/README.md)).

| 항목 | 제외 전(PR #1) | 제외 후(기준 커밋) |
| --- | --- | --- |
| `cpg.bin` | 60,017,975 B | 18,009,135 B |
| 프런트엔드 | 23초 | 13초 |
| 적재 | 300초 timeout으로 3번 모두 실패 | 42초 |
| 적재 중 CPU | `ForkJoinPool` 스레드 하나만 100%(htop, top -H) | 2초 간격 13회 중 7회에서 상위 6개 스레드가 모두 50% 이상 |
| 적재 중 heap | 4G 중 1.5G 사용(`jcmd GC.heap_info`) | 4G 중 최대 1.70 GB 사용 |

- 제외 전 실패 때 heap은 여유가 있었고 GC 스레드는 거의 쉬었다. 적재가 느린 원인은 메모리가 아니었다.
- 테스트 폴더와 `platform_catalog.py` 중 어느 쪽이 적재를 300초 넘게 만들었는지는 나눠 재지 않았다.

## 2. 기준 커밋 그래프

[scripts/build-baseline.sh](scripts/build-baseline.sh)로 소스를 풀고 `generate_cpg`를 부른 뒤 5초마다 상태를 봤다. 그동안 [scripts/sample-load.sh](scripts/sample-load.sh)가 메모리, 스레드, heap을 샘플링했다.

| 단계 | 시각(UTC) | 소요 |
| --- | --- | --- |
| `generate_cpg` 요청 | 23:45:32 | |
| 소스 복사(codebadger 안) | 23:45:39 → 23:45:47 | 8초 |
| 프런트엔드(pysrc2cpg) | 23:45:51 → 23:46:04 | 13초 |
| 워커 기동 | 23:46:04 → 23:46:18 | 14초 |
| 적재(`importCpg`, overlay) | 23:46:18 → 23:47:00 | 42초 |
| ready 확인 | 23:47:06 | 요청부터 94초 |

| 그래프 규모 | crewAI `71d68117` | opensre `a5c1acbd`(5단계) |
| --- | --- | --- |
| 파일 | 984 | 2,353 |
| 메서드 | 36,950 | 49,754 |
| 호출 | 254,956 | 469,749 |
| `cpg.bin` | 18.0MB | 30MB |
| overlay | `base, controlflow, typerel, callgraph, dataflowOss, pysrc2cpg-postprocessing` | 같음 |

- 적재가 끝나자 codebadger가 자기 쪽 소스 사본을 지웠다(`Reclaimed source snapshot ... (ephemeral source)`). 우리가 푼 소스 폴더(`codebases/crewAI-71d68117`)는 6단계 후속에서 지웠고, 기준 그래프는 남겼다([6단계 기록](../2026-11-12-pr-analysis/README.md) 8절).

## 3. 메모리와 CPU

| 항목 | 최댓값 | 상한 | 근거 |
| --- | --- | --- | --- |
| 생성 컨테이너 cgroup `memory.current` | 2.15 GiB(23:46:03) | 8G(`JOERN_MEM_LIMIT`) | [raw/build/sample.mem.tsv](raw/build/sample.mem.tsv) |
| 프런트엔드 JVM RSS | 1.80 GiB, 스레드 62 | heap 4G(`CPG_BUILD_HEAP_GB`) | [raw/build/sample.gen.log](raw/build/sample.gen.log) |
| 프런트엔드 CPU | 최대 965%(약 10코어) | cpuset 20개 | 같은 파일 |
| 질의 워커 cgroup `memory.current` | 2.78 GiB(23:47:04) | 5G(예약) | [raw/build/sample.mem.tsv](raw/build/sample.mem.tsv) |
| 질의 워커 heap 사용 | 1.70 GB(23:46:50, 커밋 2G) | 4G | [raw/build/sample.heap.log](raw/build/sample.heap.log) |

- 생성 컨테이너의 `memory.peak`는 컨테이너가 뜬 뒤 누적값이고, 이 커널(6.8)에서는 되돌릴 수 없다. 그래서 1초마다 `memory.current`를 읽었다. 1초 사이의 순간 최댓값은 놓쳤을 수 있다.
- 적재 중 스레드별 CPU는 [raw/build/sample.threads.log](raw/build/sample.threads.log)에 2초 간격으로 남겼다. 바쁜 스레드는 `ForkJoinPool`, `pool-3`, JIT 컴파일러(`C2`)였다.
- 판단: 워커 heap 4G와 노드 3 질의 예산 80G는 crewAI에도 충분하다. 워커 하나의 예약은 5G로 opensre와 같고, 예산 안에 16개가 동시에 들어간다. 적재 timeout(300초)도 42초라 바꿀 필요가 없다.

## 4. Q1~Q5

3단계와 같은 다섯 종류를 crewAI에서 새로 골랐다. 질의 식은 [config/queries/crewai.json](../../../config/queries/crewai.json)에 있고, 분석 워크플로가 `--queries`로 같은 파일을 읽는다.

### 고른 방법

[scripts/discover.py](scripts/discover.py)로 3단계 discover2.sc, 4단계 common-candidates.sc와 같은 기준을 MCP로 물었다([raw/discover.jsonl](raw/discover.jsonl)).

| # | 질의 | 대상 | 고른 이유 |
| --- | --- | --- | --- |
| Q1 | 함수를 부르는 함수(`callIn.method`) | `lib/crewai/src/crewai/llms/base_llm.py`의 `BaseLLM._emit_call_completed_event` | 이름이 레포 안에서 하나뿐인 함수 중 호출이 69곳으로 세 번째로 많다. 1, 2위(`TraceCollectionListener._on`, devtools `run_command`)는 호출자가 한 파일 안에 있다. 이 함수는 provider 5개 파일의 하위 클래스가 `self.`로 부른다. 그래서 상속으로 이어진 호출을 Serena와 Joern이 같게 잡는지 볼 수 있다 |
| Q2 | 함수가 부르는 이름(`callOut.name`) | 같은 파일의 `BaseLLM._apply_stop_words` | 이름이 하나뿐이고 Q1과 같은 파일에 있다. 호출 25곳, 부르는 호출 34개로 3단계 Q2(20개)와 규모가 비슷하다 |
| Q3 | Q1 호출자를 부르는 함수(2단계) | Q1과 같음 | 3단계와 같은 정의 |
| Q4 | 매개변수 → `subprocess.run` 인자 흐름 | `lib/devtools/src/crewai_devtools/cli.py`의 `run_command(cmd, cwd)` | 매개변수 두 개가 그대로 `subprocess.run(cmd, cwd=cwd, ...)`에 들어간다. 3단계 Q4(`git` 매개변수 → `check_output`)와 같은 모양이다. `subprocess` 호출 40곳 중 매개변수가 인자로 바로 들어가는 곳이다 |
| Q5 | Q1 호출자 매개변수 → Q1 인자 흐름 | Q1과 같음 | 3단계와 같은 정의. Q1의 매개변수가 9개라 흐름이 많다 |

### 결과

질의 안 `System.nanoTime`으로 잰 Joern 실행 시간(ms)이다. 괄호 안은 MCP 왕복(초)이다.

| # | 결과 수 | run1 | run2 |
| --- | --- | --- | --- |
| Q1 | 29 | 13.0 (0.20) | 0.34 (0.15) |
| Q2 | 18 | 0.24 (0.26) | 0.15 (0.12) |
| Q3 | 64 | 0.53 (0.16) | 0.54 (0.17) |
| Q4 | 6 | 1,386.2 (1.55) | 593.7 (0.72) |
| Q5 | 1,634 | 4,675.5 (4.83) | 3,892.2 (4.06) |

- Q1 호출자 29개: openai 9, anthropic 6, gemini 5, bedrock 4, azure 3, `base_llm.py` 2.
- Q2 이름 18개는 대부분 연산자(`<operator>.assignment` 등)와 `len`, `find`, `strip`, `debug`다.
- Q5는 3단계(331건)보다 다섯 배 많다. Q1 매개변수 9개가 호출 69곳의 인자로 이어져서다.
- 질의 문자열에 run 번호를 넣어 codebadger 결과 캐시를 피했다([scripts/run-queries.py](scripts/run-queries.py)). run1은 그래프 적재 직후 처음 받은 질의가 아니다. discover 질의를 먼저 받았다.

## 5. Serena와 Joern 비교

4단계와 같은 방법으로 (파일, 함수) 쌍을 맞췄다. Joern 쪽은 [scripts/callers.py](scripts/callers.py)(4단계 callers.sc와 같은 식과 출력 형식), Serena 쪽은 [scripts/serena-refs.sh](scripts/serena-refs.sh), 비교는 4단계 compare.py에 `--exclude-regex`만 더한 [scripts/compare.py](scripts/compare.py)다. Joern 그래프에서 뺀 경로는 Serena 결과에서도 같은 정규식으로 뺐다.

### 흔한 이름 메서드 고르기

`close`를 골랐다(4단계와 같은 이름). 레포 안 정의가 12개, 이름이 `close`인 호출 지점이 86곳이다. 정의마다 Joern 연결이 6~11개씩 붙는다([raw/discover.jsonl](raw/discover.jsonl)). 그중 `lib/crewai/src/crewai/memory/unified_memory.py`의 `Memory.close`(Joern 7개)를 비교 대상으로 삼았다. `Memory`를 import하는 줄이 crewai 패키지 소스에 12개 있다.

### 결과

| 질의 | Joern 호출 함수 / 지점 | Serena 참조(전체 / 제외 후) | 양쪽 | Joern만 | Serena만 | Joern 시간 | Serena 응답 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Q1, 기본 설정 | 29 / 69 | 68 / 68 | 28 | 1 | 0 | 0.3ms | 5.95초 |
| Q1, `extraPaths` | 29 / 69 | 73 / 68 | 28 | 1 | 0 | 0.3ms | 4.51초 |
| C1, 기본 설정 | 7 / 7 | 0 / 0 | 0 | 7 | 0 | 0.2ms | 1.94초 |
| C1, `extraPaths` | 7 / 7 | 3 / 0 | 0 | 7 | 0 | 0.2ms | 1.94초 |

- Q1에서 Joern에만 있는 1쌍은 `BaseLLM._emit_call_completed_event<metaClassAdapter>`다. pysrc2cpg가 메서드마다 만드는 합성 메서드로, 4단계에서도 같은 항목이 나왔다. 실제 호출은 양쪽이 모두 같다.
- C1에서 Joern이 이은 7곳은 모두 다른 객체의 `close()`다. `conn.close()`, `cursor.close()`(crewai-tools의 SingleStore, Snowflake 도구), `invoke_result.close()`, `self._async_client.close()`, `self._storage.close()`, 그리고 `close` 정의 줄의 합성 메서드다. 4단계와 같은 이름 기반 오탐이다.
- Serena가 찾은 `Memory.close` 참조 3개는 모두 `lib/crewai/tests` 안에 있다. 테스트 밖에서는 이 메서드를 부르는 곳이 없다.
- `extraPaths` 결과는 두 번 띄워 물었을 때 응답이 같았다(SHA-256 앞 12자리 `32a8c0cdeeb7`, [raw/serena-extrapaths-run1.jsonl](raw/serena-extrapaths-run1.jsonl), [raw/serena-extrapaths-run2.jsonl](raw/serena-extrapaths-run2.jsonl)).

### 모노레포에서 Serena·Pyright 설정이 달라지는 점

crewAI는 uv workspace이고 패키지 6개가 `lib/<패키지>/src/<모듈>` 아래 있다(`cli`, `crewai`, `crewai-core`, `crewai-files`, `crewai-tools`, `devtools`). Pyright 1.1.403의 절대 import 해석 순서는 다음과 같다([docs/import-resolution.md](https://github.com/microsoft/pyright/blob/1.1.403/docs/import-resolution.md)).

1. 워크스페이스 루트
2. `extraPaths`
3. 루트 바로 아래 `src`
4. 설치된 패키지
5. typeshed
6. 마지막으로 import하는 파일의 폴더와 그 상위 폴더

| 위치 | 기본 설정에서 `import crewai`가 풀리는가 | 이유 |
| --- | --- | --- |
| `lib/crewai/src/crewai/...` | 풀린다 | 6번 규칙. 상위 폴더 `lib/crewai/src`에 `crewai`가 있다 |
| `lib/crewai/tests/...` | 풀리지 않는다 | 상위 폴더(`lib/crewai/tests`, `lib/crewai`, `lib`)에 `crewai` 모듈이 없다 |
| `lib/crewai-tools/src/...` 등 다른 패키지 | 풀리지 않는다 | 같은 이유. 패키지 간 import는 기본 설정으로 이어지지 않는다 |

- 그래서 Q1의 테스트 밖 참조 68개는 두 설정이 같았고, `extraPaths`를 넣었을 때만 테스트 파일 3개의 참조 5개가 더 잡혔다. C1도 `extraPaths`에서만 테스트 참조 3개가 나왔다.
- 이번 두 대상은 호출자가 모두 `crewai` 패키지 안에 있다. 그래서 패키지 간 참조 차이는 결과에 드러나지 않았다. 패키지를 넘는 참조를 찾을 때는 `extraPaths`가 필요하다.
- 설정 파일: [config/serena/crewai/pyrightconfig.json](../../../config/serena/crewai/pyrightconfig.json). 분석 대상 체크아웃 루트에 복사해 쓴다. Serena 로그에 `Loading configuration file at $CREWAI_DIR/pyrightconfig.json`이 찍혔다. 두 설정 모두 `Found 1515 source files`다.
- 가상환경(`uv sync`)은 만들지 않았다. 4단계와 같이 서드파티 타입은 풀리지 않은 상태다.
- Serena `project.yml`은 4단계 파일에서 `project_name`만 `crewAI`로 바꿨다. 읽기 전용 설정(도구 인터페이스, `fixed_tools` 5개, `read_only`)은 같다.

## 6. ast-grep 후보 목록 재현성

4단계 규칙 5개와 [scripts/screen/candidates.py](../../../scripts/screen/candidates.py)를 그대로 썼다.

| 실행 | SHA-256 | 시간 |
| --- | --- | --- |
| run1 | `f34e56b63def1a36e295abde1895ac17fc26a1c92b663a90f3ab8cf706c75a59` | 1.39초 |
| run2 | 같음(`cmp` 일치) | 0.53초 |

| 규칙 | 건수 |
| --- | --- |
| `py-env-read` | 325 |
| `py-except-swallow` | 138 |
| `py-global-state` | 17 |
| `py-runtime-assert` | 4 |
| `py-subprocess-shell` | 0 |

- 후보 목록에는 `lib/*/tests` 경로도 들어 있다. 규칙은 4단계 그대로라 최상위 `tests/`만 따로 다루고 있다. crewAI용으로 규칙을 고칠지는 정하지 않았다.

## 확인 안 됨

- 제외 전 그래프의 적재가 오래 걸린 원인이 테스트 폴더인지 `platform_catalog.py`인지
- 제외 전 적재에서 스레드 하나만 돈 이유(어느 overlay 단계였는지)
- 1초 간격 사이의 순간 최대 메모리
- 가상환경을 주었을 때 Serena 결과가 달라지는지
- 패키지 간 참조에서 Serena 기본 설정과 `extraPaths` 결과가 실제로 어떻게 갈리는지(이번 Q1, C1에는 패키지 간 호출자가 없었다)

## 원본 파일

| 파일 | 내용 |
| --- | --- |
| `raw/build/summary.txt`, `status.log`, `generate.jsonl`, `stats.jsonl` | 기준 그래프 생성 요약, 상태 변화, 그래프 규모 |
| `raw/build/codebadger.log` | codebadger MCP 로그 중 이 그래프 줄 |
| `raw/build/sample*.{mem.tsv,threads.log,gen.log,heap.log}` | 생성 중(`sample-gen`)과 적재 중(`sample`) 메모리, 스레드, 프런트엔드 프로세스, heap |
| `raw/discover.jsonl` | 질의 후보 찾기 결과 |
| `raw/queries.jsonl` | Q1~Q5 두 번씩. run1의 Q1~Q3은 결과 목록 전체 |
| `raw/callers-joern.log` | Q1, C1의 Joern 호출자와 호출 지점 |
| `raw/serena-{default,extrapaths}-run*.{jsonl,err}` | Serena 응답과 로그(작업자 쪽 경로는 `$CREWAI_DIR`, `$HOME`으로 바꿨다) |
| `raw/compare-{Q1,C1}-{default,extrapaths}.json` | 비교 결과 |
| `raw/astgrep-candidates-run{1,2}.json`, `raw/astgrep-hash.log` | 후보 목록 두 번과 해시 |
