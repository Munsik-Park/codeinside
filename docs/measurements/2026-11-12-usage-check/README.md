# 2026-11-12 사용법 문서 확인

[docs/usage.md](../../usage.md) 초안(SHA-256 `aa6e55ad…a3f4`)의 명령을 위에서부터 한 번씩 그대로 돌린 기록이다. 문서대로 안 된 두 곳은 문서를 고쳤다(5절).

## 조건

| 항목 | 값 |
| --- | --- |
| 대상 커밋 | `Munsik-Park/crewAI` main HEAD `345792859393ff26e3d3ec2251ec7967d62079bb`(PR #3 머지 커밋) |
| crewAI 체크아웃 | 작업자 쪽 체크아웃. 로컬 `main`은 기준 커밋 `71d68117`에 머물러 있어, 문서 1절대로 위 SHA를 `git checkout`했다 |
| 도구 | ast-grep 0.51.2, uv 0.11.32, Serena 2.1.0, Claude Code 2.1.322, mcp 2.2.0 |
| MCP 연결 | 문서의 `MCP_URL`(SSH 터널의 로컬 포트). 터널 명령과 호스트는 적지 않는다 |
| 시각 | 06:10~06:13 UTC |

raw 파일에서 체크아웃 경로는 `$CODEINSIDE_DIR`, `$CREWAI_DIR`, 주소는 `$MCP_URL`로 바꿨다.

## 결과 요약

| 문서 절 | 명령 | 결과 | raw |
| --- | --- | --- | --- |
| 준비 | Serena 설정 두기 | 문서대로 됨. `project.yml`은 `project_name`만 `"crewAI"`로 바뀌었고, `pyrightconfig.json`에는 `extraPaths` 6개가 들어갔다 | [00](raw/00-serena-setup.log) |
| 1 | 후보 목록 | 문서대로 됨. 0.70초, `repo_dirty: false`, 후보 484개 | [01](raw/01-candidates.log) |
| 2 | `resolve_graph.py` | 문서대로 됨. `exact: true`, `codebase_hash=846aec8c348118be`, `codebadger_status: loading` | [02](raw/02-resolve-graph.log) |
| 3 | `mcp_call.py`로 Joern Q1 | **안 됨(loading 중)**. 기다린 뒤 다시 물어 29건 | [03](raw/03-joern-q1-while-loading.log), [04](raw/04-cpg-status-poll.log), [05](raw/05-joern-q1-ready.log) |
| 3 | `mcp_call.py`로 Serena 참조 | 문서대로 됨. 9개 파일, 참조 73개, 4.54초 | [06](raw/06-serena-refs.log) |
| 3 | `claude mcp add` 세 개, `claude mcp list` | **안 됨(ast-grep, serena)**. 기존 항목을 지운 뒤 다시 등록해 세 서버 모두 `Connected` | [07](raw/07-mcp-add-as-written.log), [08](raw/08-mcp-add-remove-first.log) |

## 1. 준비와 후보 목록

- `.serena/project.yml`은 템플릿과 `project_name` 줄만 다르다(`diff`로 확인).
- Serena 서버를 처음 띄울 때 `Project configuration ... was incomplete, re-saving with default values for missing fields`를 남기고 이 파일을 Serena 템플릿 전체로 다시 썼다. 다시 쓴 파일에서도 `read_only: true`, `fixed_tools` 5개, `language_servers: python`, `default_modes`는 그대로다.
- 후보 목록의 규칙별 개수는 [crewAI 기준값](../2026-11-12-crewai-baseline/README.md) 6절(기준 커밋 `71d68117`)과 같다: `py-env-read` 325, `py-except-swallow` 138, `py-global-state` 17, `py-runtime-assert` 4, `py-subprocess-shell` 0. 두 커밋 사이에 바뀐 `.py` 파일은 없다(`git diff --stat 71d68117 HEAD -- '*.py'`가 비어 있음). `repo_sha`가 달라 파일 SHA-256은 기준값과 다르다.
- `candidates.json`, `.serena/`, `pyrightconfig.json`은 crewAI 체크아웃에 커밋하지 않은 파일로 남아 있다. `repo_dirty`는 추적 파일만 보므로 `false`다.

## 2. 그래프 고르기와 Joern Q1

| 시각(UTC) | 단계 | 결과 |
| --- | --- | --- |
| 06:10:49 직전 | `resolve_graph.py` | main HEAD 자기 그래프 `846aec8c348118be`, `loading`(0.98초) |
| 06:10:49 | 문서의 Q1 명령 | `success: true`, `row_count: 1`. `data`는 Joern REPL 시작 출력(4,886자)이고 끝 줄이 `io.joern.console.Error: No projects loaded`다 |
| 06:11:06~06:11:25 | `get_cpg_status` 3회 | `loading` |
| 06:11:36 | `get_cpg_status` | `ready`(첫 Q1 호출부터 47초) |
| 06:11:36 뒤 | 같은 Q1 명령 | 29건, 왕복 0.33초(Joern 실행 0.17초). 앞 세 항목은 [6단계 기록](../2026-11-12-pr-analysis/README.md) 6절과 같다 |

- resolver가 `get_cpg_status`로 잠든 그래프의 적재를 시작시켰고, 그 직후 물은 질의는 아직 프로젝트가 없는 Joern 서버로 갔다.
- 응답이 `success: true`라서 종료 코드나 `is_error`로는 실패를 알 수 없다.
- ready 뒤에 같은 질의 문자열로 다시 물었을 때 실패한 응답이 캐시에서 나오지 않고 29건이 왔다.

## 3. Serena 참조

- 도구 목록은 읽기 도구 5개다(`find_declaration`, `find_implementations`, `find_referencing_symbols`, `find_symbol`, `get_symbols_overview`).
- `BaseLLM/_emit_call_completed_event` 참조는 9개 파일, 73개이고 그중 테스트 안이 5개다. [crewAI 기준값](../2026-11-12-crewai-baseline/README.md) 5절의 `extraPaths` 결과(73개, 테스트 안 5개)와 같다.

## 4. Claude Code 등록

작업 전 이 폴더의 local 설정:

| 서버 | 등록 상태 |
| --- | --- |
| ast-grep | 있음. 문서와 같은 명령(대상 레포 경로 없음) |
| serena | 있음. `--project`가 opensre 체크아웃(4단계 `register.sh`로 등록한 것) |
| joern | 없음 |

- 문서대로 `claude mcp add`를 돌리자 ast-grep, serena는 `MCP server ... already exists in local config`(종료 코드 1)로 실패했고 joern만 등록됐다. serena는 opensre를 가리킨 채 남았다.
- 세 이름을 `claude mcp remove --scope local`로 지운 뒤 다시 등록했다. serena의 `--project`는 crewAI 체크아웃이 됐다.
- `claude mcp list`: ast-grep, serena, joern(HTTP) 모두 `Connected`. raw에서는 이 문서와 무관한 사용자 MCP 서버 줄을 뺐다.

## 5. 문서를 고친 곳

| 위치 | 문서대로 했을 때 | 고친 것 |
| --- | --- | --- |
| 2절 `codebadger_status: loading` 행 | 바로 3절로 넘어가 질의하면 결과 대신 REPL 출력과 `No projects loaded`가 `success: true`로 온다(2절) | `ready`까지 기다린다는 문장, `loading` 중 응답의 모양, `get_cpg_status` 확인 명령을 더했다 |
| 3절 Claude Code 등록 | 같은 이름이 있으면 `claude mcp add`가 실패하고 기존 항목(opensre)이 남는다(4절) | 등록 전에 세 이름을 `claude mcp remove --scope local`로 지우는 줄과 그 이유를 더했다. `scripts/mcp/register.sh`도 같은 순서로 지운 뒤 등록한다 |
| 3절 근거 문단 | `claude mcp add --transport http`는 "기록에서 돌린 적은 없다"고 적혀 있었다 | 이 기록에서 돌려 `Connected`를 본 것으로 고쳤다 |

## 확인 안 됨

- Claude Code 세션 안에서 세 MCP 도구를 실제로 부르는 것. 이번에는 `claude mcp list`의 연결 확인까지만 했다(세션 안 호출은 [5단계 기록](../2026-11-12-joern-mcp/README.md) 5절)
- 후보 목록을 두 번 돌렸을 때 바이트 단위로 같은지. 이번에는 한 번만 돌렸다(기준 커밋에서는 6절에서 확인)
- 조상 그래프로 대신하는 경우(`exact: false`)와 그래프가 없는 경우(`graph_sha: null`). 이번 커밋은 자기 그래프가 있었다

## 원본 파일

| 파일 | 내용 |
| --- | --- |
| `raw/00-serena-setup.log` | Serena 설정 두기 명령과 종료 코드 |
| `raw/01-candidates.log` | 체크아웃, 후보 목록 명령, 출력 머리(후보는 개수만)와 파일 SHA-256 |
| `raw/02-resolve-graph.log` | `resolve_graph.py` 출력 |
| `raw/03-joern-q1-while-loading.log` | loading 중 Q1 응답 전체 |
| `raw/04-cpg-status-poll.log` | `get_cpg_status` 응답과 폴링 결과 |
| `raw/05-joern-q1-ready.log` | ready 뒤 Q1 응답 |
| `raw/06-serena-refs.log` | Serena 서버 시작 로그 일부, 도구 목록, 참조 응답 |
| `raw/07-mcp-add-as-written.log` | 문서 그대로 돌린 `claude mcp add` |
| `raw/08-mcp-add-remove-first.log` | 지운 뒤 다시 등록, `claude mcp list` |
