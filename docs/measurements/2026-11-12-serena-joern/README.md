# 2026-11-12 ast-grep, Serena 연결과 Joern 비교 (단계 4)

[docs/plan.md](../../plan.md) 단계 4의 원본 기록이다. 비교 기준은 [3단계 기록](../2026-11-11-baseline/README.md)이다. plan.md와 architecture.md는 이 PR에서 고치지 않았다.

## 결과 요약

| 끝내는 기준 | 결과 | 근거 |
| --- | --- | --- |
| 같은 SHA에서 ast-grep 후보 목록 두 번의 해시가 같다 | 같다. SHA-256 `a3d97f61acbaa0ab97e57f273ce2620fff4eb3a90e8bee1521d49fa330e25173` (두 번 모두) | [raw/astgrep-hash.log](raw/astgrep-hash.log) |
| Q1과 흔한 이름 메서드 하나를 Serena와 Joern으로 비교한 기록 | Q1은 131쌍 모두 일치. `SessionManager.close`는 1쌍만 겹침(Joern만 13, Serena만 4) | 아래 4절, [raw/compare-Q1.json](raw/compare-Q1.json), [raw/compare-C1.json](raw/compare-C1.json) |
| Serena가 읽기 도구만 켠 상태라는 근거 | MCP `tools/list`가 읽기 도구 5개만 돌려주고, 셸 실행과 파일 생성, 내용 치환 도구를 부르면 `Unknown tool`로 거부된다 | 아래 2절, [raw/serena-readonly-probe.jsonl](raw/serena-readonly-probe.jsonl) |

## 측정 조건

| 항목 | 값 |
| --- | --- |
| 대상 커밋 | Munsik-Park/opensre `a5c1acbd4b7e61e3cb57de6b84fac7031555a0a4` (3단계와 같음) |
| opensre 체크아웃 | codeinside 폴더 밖에 따로 clone했다. 기록에서는 `$OPENSRE_DIR`로 적는다 |
| 작업자 쪽 | macOS(arm64), uv 0.11.32, Claude Code 2.1.322 |
| Joern 쪽 | Xeon에 3단계에서 적재해 둔 `full.bin` 프로젝트(최상위 `tests/` 제외). Joern v4.0.680, OpenJDK 21.0.13, `joern` 전용 계정 |
| Joern 실행 | `JAVA_TOOL_OPTIONS=-Xmx2G numactl --cpunodebind=3 --membind=3 joern --script <파일.sc>`. 3단계와 같은 조건이다 |
| 로그의 경로 | 작업자 쪽 절대 경로는 [scripts/sanitize.sh](scripts/sanitize.sh)로 `$OPENSRE_DIR`, `$CODEINSIDE_DIR`, `$HOME`으로 바꿔 넣었다 |

## 1. 설치한 것과 출처

| 구성 | 버전 | 설치 방법 | 출처 |
| --- | --- | --- | --- |
| ast-grep CLI | 0.51.2 | `brew install ast-grep` | [ast-grep Quick Start "Installation"](https://ast-grep.github.io/guide/quick-start.html#installation), ast-grep-mcp README "Prerequisites" |
| ast-grep 공식 MCP (ast-grep/ast-grep-mcp) | 커밋 `51d5a23f025c73c02032a98748dc06942548c5e1` (2026-11-05, main). 태그가 없어 커밋으로 고정했다. 패키지 이름 `sg-mcp` 0.1.0, 의존성 `mcp[cli]==2.2.0` | `uvx --from git+https://github.com/ast-grep/ast-grep-mcp@<커밋> ast-grep-server` | [ast-grep-mcp README "Running with uvx"](https://github.com/ast-grep/ast-grep-mcp#running-with-uvx) |
| Serena | 2.1.0 (PyPI `serena-agent`, 2026-10-19 릴리스), Python 3.13.14 | `uv tool install -p 3.13 serena-agent==2.1.0` | [Serena docs 02-usage/010_installation.md](https://github.com/oraios/serena/blob/v2.1.0/docs/02-usage/010_installation.md) (문서는 버전 없이 `serena-agent`. 재현을 위해 버전을 붙였다) |
| Python 언어 서버 | Pyright 1.1.403 | Serena가 `uvx -p 3.13 --from pyright==1.1.403 pyright-langserver --stdio`로 띄운다 | 아래 3절 |

### Claude Code에 붙이기

[scripts/mcp/register.sh](../../../scripts/mcp/register.sh)가 `claude mcp add --scope local`로 두 서버를 등록한다. local 범위 설정은 사용자 홈의 Claude Code 설정에 저장되므로 절대 경로가 레포에 들어가지 않는다. 레포에는 자리 표시자만 쓴 [config/mcp/mcp.example.json](../../../config/mcp/mcp.example.json)을 둔다.

- Serena 등록 명령은 [Serena docs 02-usage/030_clients.md "Claude Code"](https://github.com/oraios/serena/blob/v2.1.0/docs/02-usage/030_clients.md)의 Per-Project Configuration(`serena start-mcp-server --context claude-code --project ...`)을 따르고, context를 읽기 전용 파일로 바꾸고 `--agent-interface tools`를 더했다.
- 등록 뒤 `claude mcp list`에서 두 서버 모두 `✔ Connected`였다([raw/mcp-register.log](raw/mcp-register.log)).
- ast-grep MCP를 직접 띄워 `tools/list`를 보면 `dump_syntax_tree`, `find_code`, `find_code_by_rule`, `test_match_code_rule` 4개다(README "Features"와 같다).

## 2. Serena 읽기 전용 설정과 근거

설정 파일은 [config/serena/context-readonly.yml](../../../config/serena/context-readonly.yml)(context)과 [config/serena/project.yml](../../../config/serena/project.yml)(대상 체크아웃의 `.serena/project.yml`로 복사) 두 개다. Serena 소스는 레포에 넣지 않았다.

| 설정 | 하는 일 | 문서 근거 |
| --- | --- | --- |
| `--agent-interface tools`, project.yml `agent_interface: tools` | 도구 인터페이스로 고정한다. 새로 만든 전역 설정의 기본값은 `REPL`이다 | [050_configuration.md "Agent Interfaces"](https://github.com/oraios/serena/blob/v2.1.0/docs/02-usage/050_configuration.md): REPL 인터페이스에서는 도구 집합이 고정되고 도구 포함·제외 설정이 적용되지 않는다. [070_security.md "The REPL Interface"](https://github.com/oraios/serena/blob/v2.1.0/docs/02-usage/070_security.md): 도구 인터페이스에서는 도구를 빼면 그 기능이 실제로 없어지지만, REPL에서는 API를 빼도 실행 코드가 같은 일을 할 수 있다 |
| context와 project.yml의 `fixed_tools` | 기본 도구 집합을 `get_symbols_overview`, `find_symbol`, `find_referencing_symbols`, `find_declaration`, `find_implementations` 5개로 바꾼다 | `context.template.yml`, `project.template.yml`의 `fixed_tools` 설명("replacing Serena's default set of tools"). 도구 목록은 `serena tools list --all` |
| project.yml `read_only: true` | 편집 도구를 모두 끈다 | `project.template.yml`의 `read_only` 설명("all editing tools will be disabled"). 070_security.md는 REPL에서는 이 설정도 우회될 수 있다고 적는다 |
| project.yml에 둔 이유 | mode가 선택 도구를 다시 넣어도 프로젝트 설정이 마지막에 적용된다 | 문서에는 적용 순서가 없어 소스로 확인했다: [src/serena/agent.py `_update_active_tools`](https://github.com/oraios/serena/blob/v2.1.0/src/serena/agent.py#L1289-L1307)는 mode를 먼저, 프로젝트 설정과 `read_only`를 나중에 적용한다 |

실제 실행에서 확인한 것([raw/serena-readonly-probe.jsonl](raw/serena-readonly-probe.jsonl), [raw/serena-run1.err](raw/serena-run1.err)):

- `tools/list` 결과는 `find_declaration`, `find_implementations`, `find_referencing_symbols`, `find_symbol`, `get_symbols_overview` 5개다.
- Serena 로그: `Using agent interface 'tools' (project configuration)`, `Number of exposed tools: 5`. 활성 mode는 전역 기본값이 남아 `editing, interactive, no-memories, planning`이지만 노출 도구는 5개 그대로다.
- `execute_shell_command`, `create_text_file`, `replace_content`를 직접 부르면 세 번 모두 `Unknown tool: ...`이 돌아온다. 호출 뒤 대상 체크아웃에 시험 파일이 생기지 않았고 추적 파일 변경도 없었다([raw/serena-readonly-probe.result](raw/serena-readonly-probe.result)).

## 3. Serena의 Python 언어 서버

- 문서: [01-about/020_programming-languages.md](https://github.com/oraios/serena/blob/v2.1.0/docs/01-about/020_programming-languages.md)는 Python 기본값을 Pyright(언어 키 `python`)로 적는다. 다른 선택지는 BasedPyright, ty, pyrefly, Jedi다. 050_configuration.md "Pyright (`python`)"는 기본 버전을 `1.1.403`으로 적는다.
- 실제 실행: Serena 로그에 `Starting language server process via command: ['$HOME/.local/bin/uvx', '-p', '3.13', '--from', 'pyright==1.1.403', 'pyright-langserver', '--stdio']`와 `Pyright language server 1.1.403 starting`이 찍혔다([raw/serena-run1.err](raw/serena-run1.err)).
- Pyright는 `Found 3693 source files`로 최상위 `tests/`까지 읽는다. opensre의 가상환경은 만들지 않았고, Pyright는 uvx가 띄운 Python 3.13.14를 기준으로 삼았다. 따라서 서드파티 패키지 타입은 풀리지 않은 상태다.

## 4. Serena와 Joern 비교

### 맞추는 방법

두 도구의 결과 단위가 다르므로 (파일, 함수) 쌍으로 바꿔 비교했다([scripts/compare.py](scripts/compare.py)).

- Joern: 3단계 Q1과 같은 `callIn.method.fullName.dedup`([scripts/callers.sc](scripts/callers.sc)). `파일:<module>.A.b`는 (파일, `A.b`)로 바꾼다.
- Serena: `find_referencing_symbols`는 참조 위치마다 그 위치를 감싸는 심볼을 돌려준다. `A/b`는 `A.b`로, 모듈 수준(File 종류)은 `<module>`로 바꾼다. 참조 줄을 보고 import, 호출, 그 밖으로 나누고 호출만 비교에 쓴다. Serena가 보여 주는 줄 번호는 0부터 세므로 1을 더했다.
- Joern 그래프에 최상위 `tests/`가 없으므로 Serena 결과에서도 뺐다.
- Serena는 같은 설정으로 서버를 두 번 띄워 물었고 응답 본문이 같았다(두 번 모두 SHA-256 `6d2d3e5a…`, [raw/serena-run1.jsonl](raw/serena-run1.jsonl), [raw/serena-run2.jsonl](raw/serena-run2.jsonl)).

### 흔한 이름 메서드 고르기

`close`를 골랐고, 비교 대상 정의는 `core/agent_harness/session/lifecycle.py`의 `SessionManager.close`다.

- 3단계 discover.sc처럼 레포 안 정의를 이름별로 묶었다([scripts/common-candidates.sc](scripts/common-candidates.sc), [raw/common-candidates-jto-2G.log](raw/common-candidates-jto-2G.log)). `close`는 서로 다른 클래스에 26번 정의돼 있고, 이름이 `close`인 호출 지점은 179곳이다.
- 정의별 연결 수를 보면 `close` 정의 26개가 각각 호출 지점 16~21개를 받는다([raw/common-perdef-jto-2G.log](raw/common-perdef-jto-2G.log)). 파일 핸들, httpx 클라이언트, 파이프의 `close()`가 레포 안 클래스 정의와 섞이는 전형적인 경우라 이름 기반 연결의 영향을 보기에 맞다.
- `get`(정의 12개, 이름이 `get`인 호출 지점 8,157곳)은 갈린 항목을 손으로 확인할 수 있는 규모가 아니라 뺐다. `__init__`(339개), `run`(90개)은 정의가 너무 많다.
- 그중 `SessionManager.close`는 core에 있고, 호출하는 쪽이 gateway, surfaces, infrastructure에 퍼져 있다.

### 결과

| 질의 | Joern 호출 함수 | Joern 호출 지점 | Serena 참조(전체 / tests 제외) | Serena 호출 쌍 | 양쪽 | Joern만 | Serena만 | Joern 시간 | Serena 응답 시간 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Q1 `record_evidence_entry` | 131 | 143 | 249 / 245 (호출 143, import 102) | 131 | 131 | 0 | 0 | 75.2ms | 3.50초, 3.20초 |
| C1 `SessionManager.close` | 14 | 17 | 10 / 5 (모두 호출) | 5 | 1 | 13 | 4 | 0.5ms | 1.87초, 1.84초 |

- Joern 시간은 `full.bin`을 연 뒤 질의 하나에 걸린 시간이다. 스크립트 전체는 12.05초, 최대 메모리(RSS) 1,572,284 KB였다([raw/callers-jto-2G.log](raw/callers-jto-2G.log)).
- Serena 응답 시간은 서버를 띄운 뒤 `tools/call` 하나에 걸린 시간이다(두 번 실행 값). 서버 기동 시간과, 첫 질의에 Pyright 준비 시간이 얼마나 섞였는지는 따로 재지 않았다.
- Q1 호출 지점 143곳은 ast-grep 패턴 `record_evidence_entry($$$)`로 센 수(전체 146, 최상위 `tests/` 제외 143)와도 같다.

### Q1이 모두 일치한 이유

`record_evidence_entry`는 레포 안에서 이름이 하나뿐이고, 102개 파일 모두 정의 모듈에서 바로 가져온다(`from core.domain.types.evidence import record_evidence_entry`). Joern도 이 import를 따라 정의를 찾을 수 있어서 이름 기반 연결의 약점이 드러나지 않는다.

### C1이 갈린 이유

Joern이 각 호출 지점을 어디로 이었는지 따로 뽑았다([scripts/callsite-targets.sc](scripts/callsite-targets.sc), [raw/callsite-targets-jto-2G.log](raw/callsite-targets-jto-2G.log)). `SessionManager.close`에 이어진 호출 지점 17곳 전부의 `methodFullName`과 후보 수는 [raw/joern-only-sites-jto-2G.log](raw/joern-only-sites-jto-2G.log)에 있다. 정의 파일 안의 2곳(205행, 380행)만 `methodFullName`이 `SessionManager.close`이고 후보가 1개다. 나머지 15곳은 모두 `<unknownFullName>`, 후보 76개다.

양쪽에 나온 것은 `SessionManager.rotate` 안의 `self.close(...)` 하나다.

Joern에만 나온 13개:

| 호출 함수 | 호출 지점 | 실제 대상 | 갈린 이유 |
| --- | --- | --- | --- |
| `PromptWorker._run_bound_job`, `_open_session` (gateway/core/prompt_intake/worker.py:225, 258, 318, 333) | `self._sessions.close(session)` | `UnattendedSessions.close`. 생성자에서 `sessions: UnattendedSessions \| None`로 받는다 | Joern은 수신 객체 타입을 풀지 못해 `methodFullName`이 `<unknownFullName>`이고, 이름이 `close`인 후보 76개 모두에 이었다. Joern 오탐 |
| `DiscordGatewayBackground.stop`, `SlackGatewayBackground.stop` | `self._bindings.close()`, `self._socket_client.close()` | 생성자 표기상 `BindingStore`, `SocketModeClient` | 같은 이유. Joern 오탐 |
| `infrastructure/skills_registry/client.py`의 `fetch_release`, `_post`, `list_releases` | `http.close()` | httpx 클라이언트 | 같은 이유. Joern 오탐 |
| `_run_async`(integrations/github/mcp.py, integrations/groundcover/client.py), `run_async`(integrations/mcp_client.py) | `close()` | `getattr(coro, "close", None)`로 얻은 지역 변수 | 같은 이유. Joern 오탐 |
| `_drain`(integrations/llm_cli/agent_exec.py), `_drain_pipe`(tools/interactive_shell/shell/execution.py) | `pipe.close()` | 파이프 | 같은 이유. Joern 오탐 |
| `SessionManager.close<metaClassAdapter>` | lifecycle.py:380 (`close` 정의 줄) | 없음(합성 메서드) | pysrc2cpg가 `MyClass.func(instance, ...)` 호출을 받으려고 메서드마다 만드는 어댑터다([PythonAstVisitor.scala v4.0.680 `createMetaClassAdapterMethod`](https://github.com/joernio/joern/blob/v4.0.680/joern-cli/frontends/pysrc2cpg/src/main/scala/io/joern/pysrc2cpg/PythonAstVisitor.scala)). 소스에는 없는 호출이다 |

Serena에만 나온 4개는 모두 실제 `SessionManager.close` 호출이다. Joern은 이 호출들을 다른 이름으로 이었다.

| 호출 함수 | 호출 지점 | Joern이 이은 대상 | 갈린 이유 |
| --- | --- | --- | --- |
| `UnattendedSessions.close` | infrastructure/turn_host/unattended_session.py:71 `self._manager.close(...)` | `UnattendedSessions.close` | `self._manager = manager or SessionManager()`인데 Joern은 `self`의 클래스 메서드로 이었다 |
| `_run_agent_turn` | surfaces/cli/ask/service.py:389 `manager.close(...)` | `core/agent_harness.py:<module>.SessionManager.close` | `SessionManager`를 패키지 `core.agent_harness`에서 다시 내보낸 이름으로 가져온다. Joern은 이를 존재하지 않는 파일 `core/agent_harness.py`로 풀어 실제 정의와 잇지 못했다 |
| `close_repl_session`, `close_repl_session_after_detached_worker` | surfaces/interactive_shell/runtime/session_shutdown.py:43, 72 `manager.close(...)` | `core/agent_harness.py:<module>.SessionManager.for_session.<returnValue>.close` | `manager = SessionManager.for_session(session)`. 반환 타입 표기(`-> SessionManager`)를 Pyright는 쓰고 Joern은 쓰지 않았다. 패키지 경로도 위와 같이 틀렸다 |

정리하면 C1에서 Joern 결과 14개 중 실제 호출자는 1개이고, 실제 호출자 5개 중 Joern이 찾은 것도 1개다. 이름이 흔하거나 패키지에서 다시 내보낸 심볼은 Joern의 호출 관계를 그대로 쓰면 안 된다는 3단계 판단과 맞는다.

tests 제외: Serena 결과에서 뺀 최상위 `tests/` 참조는 Q1 4건, C1 5건이다. Joern 그래프에는 이 폴더가 없다.

## 5. ast-grep Screening 규칙과 후보 목록

규칙은 [config/ast-grep/rules/](../../../config/ast-grep/rules/)에 있고 파일 첫 줄에 무엇을 거르는지 적었다.

| 규칙 | 거르는 것 | a5c1acbd 건수 |
| --- | --- | --- |
| `py-env-read` | 환경 변수를 읽는 곳(`os.environ.get`, `os.getenv`, `os.environ[...]`). 쓰기와 `del`은 뺀다 | 750 |
| `py-global-state` | 함수 안의 `global` 문 | 58 |
| `py-runtime-assert` | 테스트 밖의 `assert` 문(`python -O`에서 사라짐) | 26 |
| `py-except-swallow` | 본문이 `pass` 하나뿐인 `except` 절 | 22 |
| `py-subprocess-shell` | `shell=True`로 부르는 `subprocess` 호출 | 1 |

- 처음에는 변경 가능한 기본값 매개변수 규칙을 넣었지만 opensre에서 0건이라(grep으로도 0건) `py-global-state`로 바꿨다.
- 후보 목록 스크립트는 [scripts/screen/candidates.py](../../../scripts/screen/candidates.py)다. MCP를 거치지 않고 CLI(`ast-grep scan --json=stream`)를 직접 부른다. 출력은 규칙 이름, 레포 기준 상대 경로, 시작·끝 위치, 일치한 코드 첫 줄을 (파일, 위치, 규칙) 순으로 정렬한 JSON이다. 시각과 절대 경로는 넣지 않는다.
- 두 번 실행: 857건, 176,787 B, 두 파일의 SHA-256이 같고 `cmp`로도 같았다. 한 번에 0.4초 안팎이다([raw/astgrep-hash.log](raw/astgrep-hash.log), [raw/astgrep-candidates-run1.json](raw/astgrep-candidates-run1.json)).
- 정렬이 필요한 이유: `ast-grep scan --json=stream` 원본 출력은 실행마다 순서가 다르다. 줄 단위로 정렬해도 `metaVariables.multi`의 키 순서(`ARGS`, `secondary`)가 바뀌어 바이트가 달라지는 경우가 있었다. 파싱하면 같은 값이다. 스크립트는 이 필드를 쓰지 않는다.

## 확인 안 됨

- opensre 의존성을 설치한 가상환경을 Pyright에 주었을 때 결과가 달라지는지. 이번에는 가상환경 없이 돌렸다.
- Claude Code 세션 안에서 MCP 도구로 직접 질의한 결과. 이번 비교는 같은 서버 명령을 MCP 클라이언트 스크립트([scripts/mcp/mcp_call.py](../../../scripts/mcp/mcp_call.py))로 띄워 얻었다. 등록과 연결은 `claude mcp list`로만 확인했다.
- Serena 서버 기동 시간과 Pyright 인덱싱 시간.
- `py-except-swallow` 규칙에서 주석이 `pass` 앞에 있는 `except` 절도 걸리는데(예: config/runtime_metadata/probes.py:78), `nthChild`가 주석을 세지 않아서인지는 ast-grep 문서로 확인하지 않았다.
- Joern이 이름으로 이은 후보를 고르는 정확한 규칙. `close` 호출 179곳 중 `SessionManager.close`에 이어진 것은 17곳뿐이다.

## 원본 파일

| 파일 | 내용 |
| --- | --- |
| `raw/astgrep-candidates-run{1,2}.json`, `raw/astgrep-hash.log` | 후보 목록 두 번과 해시 |
| `raw/mcp-register.log` | `scripts/mcp/register.sh` 출력과 `claude mcp list`. ast-grep, serena 외의 MCP 서버 줄은 지웠다 |
| `raw/serena-run{1,2}.jsonl`, `raw/serena-run{1,2}.err` | Serena `tools/list`와 Q1, C1 응답, Serena 로그 |
| `raw/serena-readonly-probe.{jsonl,err,result}` | 편집·셸 도구 호출 거부 확인 |
| `raw/common-candidates-jto-2G.log`, `raw/common-perdef-jto-2G.log` | 흔한 이름 후보와 정의별 연결 수 |
| `raw/callers-jto-2G.log` | Joern Q1, C1 호출 함수와 호출 지점 |
| `raw/callsite-targets-jto-2G.log` | 갈린 호출 지점에서 Joern이 이은 대상 |
| `raw/joern-only-sites-jto-2G.log` | `SessionManager.close`에 이어진 호출 지점 17곳의 `methodFullName`과 후보 수 |
| `raw/compare-{Q1,C1}.json` | `scripts/compare.py` 출력 |
| `scripts/*.sc` | Joern 스크립트. Xeon에는 `step4-` 접두어를 붙여 joern 계정의 measure 폴더에 두었다 |
| `scripts/serena-refs.sh`, `scripts/serena-readonly-probe.sh`, `scripts/compare.py`, `scripts/sanitize.sh` | Serena 질의, 읽기 전용 확인, 비교, 경로 치환 |
