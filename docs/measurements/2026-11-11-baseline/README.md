# 2026-11-11 기준값 측정 (단계 3)

[docs/plan.md](../../plan.md) 단계 3의 원본 기록이다. 요약 수치는 plan.md 측정·검증 표 1~3행에 옮겼다.

## 측정 조건

| 항목 | 값 |
| --- | --- |
| 대상 커밋 | Munsik-Park/opensre `a5c1acbd4b7e61e3cb57de6b84fac7031555a0a4` (main, 2026-10-20) |
| core | `core/` 폴더. Python 파일 326개, 49,927줄 |
| 전체 | 레포 루트에서 최상위 `tests/`만 제외. 326,008줄. `gateway/tests` 같은 하위 tests 폴더는 들어간다 |
| Joern | v4.0.680, OpenJDK 21.0.13 |
| 실행 계정 | `joern` 전용 계정 |
| NUMA | 노드 3에 고정(`numactl --cpunodebind=3 --membind=3`). 20스레드, 메모리 약 126GB |
| 시간과 메모리 | GNU time `-v`의 Elapsed(wall clock), Maximum resident set size |

## 실행한 명령

명령과 옵션의 출처는 아래와 같다.

| 명령, 옵션 | 출처 |
| --- | --- |
| 프런트엔드를 따로 돌리고 `importCpg`로 올리기, `-J-Xmx` | [docs.joern.io/installation](https://docs.joern.io/installation/) |
| `pysrc2cpg -o`, `--exclude` | `pysrc2cpg --help` |
| `joern --script` | `joern --help` |
| `open`, `delete`, `workspace` | Joern 콘솔 `help` ([raw/console-help.log](raw/console-help.log)) |
| `callIn`, `callOut`, `.method` | [docs.joern.io/cpgql/calls](https://docs.joern.io/cpgql/calls/) |
| `reachableByFlows` | [docs.joern.io/cpgql/data-flow-steps](https://docs.joern.io/cpgql/data-flow-steps/) |
| `JAVA_TOOL_OPTIONS` | Joern 문서에 없다. 아래 "발견 1"에서 실측으로 확인한 뒤 썼다 |

프런트엔드(그래프 생성)는 [scripts/xeon/measure-frontend.sh](../../../scripts/xeon/measure-frontend.sh)로 돌렸다. 핵심 명령은 다음과 같다.

```sh
numactl --cpunodebind=3 --membind=3 /usr/bin/time -v \
  /opt/joern/current/joern-cli/pysrc2cpg -J-Xmx<값> <입력 폴더> -o ~/cpg/<label>.bin [--exclude tests]
```

적재와 질의는 [scripts/](scripts/)의 `.sc` 파일을 아래처럼 돌렸다.

```sh
JAVA_TOOL_OPTIONS=-Xmx<값> numactl --cpunodebind=3 --membind=3 /usr/bin/time -v \
  /opt/joern/current/joern-cli/joern --script <파일.sc>
```

## 1. 그래프 생성 (pysrc2cpg)

| 대상 | -Xmx | 시간 | 최대 메모리(RSS) | 그래프 파일 | 결과 | 로그 |
| --- | --- | --- | --- | --- | --- | --- |
| core | 8G | 4.31초 | 818,772 KB (0.78GiB) | 4,783,422 B (4.6MiB) | 성공 | [core-8G](raw/core-8G.log) |
| 전체 | 8G | 11.85초 | 4,149,764 KB (3.96GiB) | 31,139,466 B (29.7MiB) | 성공 | [full-8G](raw/full-8G.log) |
| 전체 | 2G | 12.28초 | 2,574,704 KB (2.46GiB) | 31,139,466 B | 성공 | [full-2G](raw/full-2G.log) |
| 전체 | 1G | 12.95초 | 1,713,536 KB (1.63GiB) | 31,139,466 B | 성공 | [full-1G](raw/full-1G.log) |

- 프런트엔드는 JVM 하나로 돌고 `-J-Xmx`가 그대로 적용된다(`jcmd VM.flags`로 MaxHeapSize 확인).
- 1G에서도 실패하지 않아 상한을 올려 다시 돌릴 일은 없었다. RSS는 상한을 따라 커지므로 필요량이 아니라 GC가 상한까지 쓴 양으로 읽어야 한다.

### 파싱 실패: PEP 695 `type` 문

전체 기준 9개 파일에서 `Could not parse file`이 났다(core 4개). 레포에서 `type X = ...` 문(Python 3.12 PEP 695)을 쓰는 파일이 정확히 이 9개다.

- core: `agent_harness/turns/turn_snapshot.py`, `domain/memory/recall.py`, `messages/runtime_message_types.py`, `tool_framework/utils/tool_availability.py`
- 그 밖: `infrastructure/analytics/provider.py`, `infrastructure/analytics/usage_context.py`, `integrations/_relational.py`, `surfaces/interactive_shell/session/connection_checks.py`, `tools/interactive_shell/shell/output_capture.py`

파일 전체가 빠지지는 않는다. 9개 파일 모두 FILE 노드가 있고 함수도 그래프에 남아 있다([parsefail-jto-2G](raw/parsefail-jto-2G.log)). 빠지는 것은 `type` 문과 그 주변이며, 정확한 범위는 확인하지 않았다.

## 2. 그래프 적재 (importCpg)

`importCpg`는 default overlay를 자동으로 붙인다. 적재 후 overlay 목록은 `base, controlflow, typerel, callgraph, dataflowOss, pysrc2cpg-postprocessing`이며, 데이터 흐름 질의에 따로 `run.ossdataflow`를 돌릴 필요가 없었다. 그래프 규모는 파일 2,353개, 메서드 49,754개, 호출 469,749개다.

| -Xmx (`JAVA_TOOL_OPTIONS`) | importCpg | 전체 시간 | 최대 메모리(RSS) | 결과 | 로그 |
| --- | --- | --- | --- | --- | --- |
| 1G | | 58.65초 | 1,641,724 KB | `OutOfMemoryError: Java heap space` | [load-jto-1G](raw/load-jto-1G.log) |
| 2G | 46.4초 | 59.27초 | 3,770,724 KB (3.60GiB) | 성공 | [load-jto-2G](raw/load-jto-2G.log) |
| 4G | 46.1초 | 59.06초 | 4,338,128 KB (4.14GiB) | 성공 | [load-jto-4G](raw/load-jto-4G.log) |
| 8G | 45.3초 | 57.72초 | 4,799,748 KB (4.58GiB) | 성공 | [load-jto-8G](raw/load-jto-8G.log) |

- 1G 실패 후 2G로 다시 올려 workspace를 복구했다([load-restore-jto-2G](raw/load-restore-jto-2G.log), 46.0초).
- 적재한 project는 workspace에 142MB로 저장된다(`cpg.bin` 74,028,470 B와 작업 사본). 저장된 project를 `open`으로 다시 여는 데는 약 1.0~1.1초가 걸렸다.

## 3. 질의 응답 시간

대상은 이름이 레포 안에서 하나뿐인 함수로 골랐다. Python 프런트엔드는 호출을 이름으로 이어서, `get`처럼 흔한 이름은 메서드마다 호출 지점이 약 590개씩 붙는다([scripts/discover.sc](scripts/discover.sc), [scripts/discover2.sc](scripts/discover2.sc)).

| # | 질의 | 결과 수 | 2G 첫 실행 | 2G 두 번째 | 8G 첫 실행 | 8G 두 번째 |
| --- | --- | --- | --- | --- | --- | --- |
| Q1 | `record_evidence_entry`를 부르는 함수 (`callIn.method`) | 131 | 70.2ms | 0.7ms | 73.1ms | 0.7ms |
| Q2 | `maybe_raise_credit_exhausted`가 부르는 이름 (`callOut`) | 20 | 5.5ms | 0.2ms | 5.6ms | 0.2ms |
| Q3 | Q1의 호출자를 부르는 함수 (2단계) | 2 | 4.6ms | 0.6ms | 3.1ms | 1.1ms |
| Q4 | `.github/ci/git_changes.py`의 `git` 매개변수에서 `subprocess.check_output` 인자로 가는 흐름 | 4 | 1,365.2ms | 654.8ms | 1,240.4ms | 814.9ms |
| Q5 | Q1 호출자들의 매개변수에서 `record_evidence_entry` 인자로 가는 흐름 | 331 | 914.9ms | 817.6ms | 1,066.1ms | 1,144.3ms |

- 질의 스크립트: [scripts/queries.sc](scripts/queries.sc). 로그: [queries-jto-2G](raw/queries-jto-2G.log), [queries-jto-8G](raw/queries-jto-8G.log)
- 프로세스 전체 최대 메모리는 2G에서 1,920,016 KB, 8G에서 2,414,892 KB다.
- Q3 결과가 2개뿐인 이유는 분석하지 않았다.

## 4. 바뀐 파일만 반영할 수 있는가

v4.0.680에는 그런 기능이 없다. 커밋마다 그래프를 처음부터 다시 만들어야 한다.

| 확인한 곳 | 결과 |
| --- | --- |
| docs.joern.io (installation, server, quickstart, organizing-projects, shell, frontends, frontends/python, cpgql/calls, cpgql/data-flow-steps) | 부분 갱신이나 변경 파일 반영에 대한 언급 없음 |
| `pysrc2cpg --help`, `joern-parse --help`, `joern --help`, 콘솔 `help` | 해당 옵션과 명령 없음 |
| 설치본 jar | 이름에 `incremental`이 들어간 Joern 클래스 없음 |
| [joernio/joern#5757](https://github.com/joernio/joern/issues/5757) | "Does joern-parse.bat support incremental builds?"에 메인테이너가 2026-08-28 "No, it doesn't right now."로 답하고 닫음 |
| [joernio/joern#5865](https://github.com/joernio/joern/issues/5865) | javasrc2cpg 전용 `IncrementalCpgUpdater` 제안. PR을 기다린다며 닫힘. 레포 코드 검색 결과 `IncrementalCpgUpdater` 0건, 연결된 PR 없음. Python은 대상이 아님 |

실측: 작업 사본(git worktree)의 `core/domain/types/evidence.py`에 함수 하나를 덧붙이고 그래프를 다시 만들었다. 프런트엔드 12.69초, `importCpg` 47.0초가 걸렸고, 새 함수와 `record_evidence_entry` 호출 관계가 그래프에 나타났다([mod-2G](raw/mod-2G.log), [rebuild-jto-2G](raw/rebuild-jto-2G.log), [scripts/rebuild.sc](scripts/rebuild.sc)). opensre 전체 기준으로 커밋 하나에 약 1분이 든다.

## 발견 1: `joern --script`의 `-J-Xmx`는 스크립트 JVM에 닿지 않는다

`joern --script`는 JVM을 하나 더 띄워 스크립트를 실행한다. `-J-Xmx`는 바깥 JVM에만 적용되고, 스크립트를 실행하는 자식 JVM은 JVM 기본값으로 뜬다.

- 근거(소스): Joern에 들어 있는 scala-repl-pp 0.6.5의 [`ScriptRunner.exec`](https://github.com/mpollmeier/scala-repl-pp/blob/v0.6.5/core/src/main/scala/replpp/scripting/ScriptRunner.scala)는 `Process("java", args)`로 `replpp.scripting.NonForkingScriptRunner`를 띄우며, `args`에 JVM 옵션을 넣지 않는다.
- 근거(실측): `-J-Xmx4G`로 적재하는 동안 `jcmd VM.flags`의 MaxHeapSize가 바깥 JVM 4.0G, 자식 JVM 30.0G였다. `JAVA_TOOL_OPTIONS=-Xmx4G`로 주면 두 JVM 모두 4.0G였고, 두 JVM이 각각 `Picked up JAVA_TOOL_OPTIONS: -Xmx4G`를 출력했다.
- 그래서 적재와 질의 수치는 `JAVA_TOOL_OPTIONS`로 잰 값만 표에 썼다. `-J-Xmx`로 잰 첫 기록([load-jflag-4G](raw/load-jflag-4G.log), [load-jflag-16G](raw/load-jflag-16G.log), [queries-jflag-16G](raw/queries-jflag-16G.log))은 상한이 사실상 30G였던 값이라 참고로만 남긴다.
- `joern --server`(단계 5)에도 같은 문제가 있는지는 확인하지 않았다.

## 원본 파일

| 파일 | 내용 |
| --- | --- |
| `raw/core-8G.log`, `raw/full-{8G,2G,1G}.log` | 프런트엔드 실행 로그와 GNU time 출력 |
| `raw/load-jto-{1G,2G,4G,8G}.log`, `raw/load-restore-jto-2G.log` | `importCpg` 적재 |
| `raw/queries-jto-{2G,8G}.log` | 질의 응답 시간 |
| `raw/mod-2G.log`, `raw/rebuild-jto-2G.log` | 파일 하나를 바꾼 뒤 다시 만들기 |
| `raw/parsefail-jto-2G.log` | 파싱 실패 파일의 그래프 상태 |
| `raw/console-help.log` | Joern 콘솔 `help` 출력 |
| `raw/load-jflag-*.log`, `raw/queries-jflag-16G.log` | `-J-Xmx`로 잰 첫 기록(발견 1 참고) |
| `scripts/*.sc` | 위 로그를 만든 Joern 스크립트 |
