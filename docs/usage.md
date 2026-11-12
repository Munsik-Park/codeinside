# codeinside 도구 사용법

crewAI 포크(`Munsik-Park/crewAI`)의 커밋 하나를 놓고 세 도구로 코드를 찾고 따라가는 방법이다. 명령은 4~6단계 기록에서 실제로 돌린 것이고, 그렇지 않은 것은 그 자리에 적었다. 근거는 각 절 끝에 있다.

## 무엇을 언제 쓰나

| 도구 | 이렇게 물을 때 | 도는 곳 | 주의 |
| --- | --- | --- | --- |
| ast-grep | 패턴에 맞는 곳을 레포 전체에서 넓게 찾기. 사전 스크립트가 규칙 5개로 후보 목록을 만든다 | 작업자 쪽 | 규칙은 opensre 때 만든 일반 Python 규칙이다. crewAI의 `lib/*/tests`도 후보에 들어간다 |
| Serena (Pyright) | 이 심볼을 실제로 참조하는 곳, 정의, 구현 | 작업자 쪽 | 읽기 전용이다. 편집, 셸, 메모리 도구는 꺼져 있다 |
| Joern (codebadger MCP) | 호출 관계를 몇 단계 따라가기, 데이터 흐름(어디서 들어온 값이 어디로 가나) | Xeon | 테스트 폴더는 그래프에 없다. 흔한 이름의 호출 관계는 틀린다(아래 한계) |

순서는 이렇다. 후보 목록으로 넓게 보고, 정확한 참조는 Serena에, 흐름은 Joern에 묻는다.

## 준비 (한 번)

### 설치

| 구성 | 버전 | 설치 |
| --- | --- | --- |
| ast-grep CLI | 0.51.2 | `brew install ast-grep` |
| uv | 0.11.32에서 확인 | uv 문서의 설치 방법 |
| Serena | 2.1.0 | `uv tool install -p 3.13 serena-agent==2.1.0` |
| Pyright | 1.1.403 | 따로 설치하지 않는다. Serena가 uvx로 띄운다 |
| gh | 인증된 상태 | 그래프 고르기가 `gh api graphql`로 커밋 상태를 읽는다 |
| Claude Code | 2.1.322에서 확인 | MCP를 세션에 붙일 때만 필요 |

근거: [4단계 기록](measurements/2026-11-12-serena-joern/README.md) 1절, [crewAI 기준값](measurements/2026-11-12-crewai-baseline/README.md) 측정 조건.

### 변수

아래 명령은 이 세 값을 쓴다.

```bash
export CODEINSIDE_DIR=<codeinside 체크아웃>
export CREWAI_DIR=<crewAI 포크 체크아웃>   # codeinside 폴더 밖에 둔다
export MCP_URL=http://127.0.0.1:<로컬 포트>/mcp
```

codebadger MCP는 Xeon 루프백(4242)에만 열려 있고 인증이 없다. 작업자 쪽에서는 SSH 터널로 로컬 포트에 붙인다. 터널 명령과 호스트는 커밋하지 않는 로컬 설정(`CLAUDE.local.md`)에 있다. 이 레포에는 적지 않는다.

### crewAI 체크아웃에 Serena 설정 두기

```bash
mkdir -p "$CREWAI_DIR/.serena"
sed 's/^project_name: .*/project_name: "crewAI"/' \
  "$CODEINSIDE_DIR/config/serena/project.yml" > "$CREWAI_DIR/.serena/project.yml"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("//",None); json.dump(d,open(sys.argv[2],"w"),indent=2)' \
  "$CODEINSIDE_DIR/config/serena/crewai/pyrightconfig.json" "$CREWAI_DIR/pyrightconfig.json"
```

- `pyrightconfig.json`은 `lib/*/src` 6개를 import 경로에 더한다. 없으면 패키지를 넘는 참조와 테스트 쪽 참조가 풀리지 않는다.
- 두 파일은 crewAI 쪽에 커밋하지 않는다.
- `scripts/mcp/register.sh`는 opensre용 `project_name`을 복사하고 Pyright 설정을 두지 않는다. crewAI에는 위 명령을 쓴다.

근거: [crewAI 기준값](measurements/2026-11-12-crewai-baseline/README.md) 5절, [measurements/2026-11-12-crewai-baseline/scripts/serena-refs.sh](measurements/2026-11-12-crewai-baseline/scripts/serena-refs.sh).

## 1. 후보 목록 (ast-grep)

분석할 커밋을 체크아웃한 뒤 돌린다.

```bash
cd "$CREWAI_DIR" && git checkout <SHA>
python3 "$CODEINSIDE_DIR/scripts/screen/candidates.py" "$CREWAI_DIR" -o candidates.json
```

- 출력에는 ast-grep 버전, `repo_sha`, 커밋 안 된 변경이 있는지(`repo_dirty`), 규칙별 개수, 후보(파일, 시작·끝 위치, 일치한 첫 줄)가 들어간다.
- 정렬된 JSON이라 같은 커밋에서 두 번 돌리면 바이트 단위로 같다.
- 규칙: 환경 변수 읽기, 함수 안 `global`, 테스트 밖 `assert`, `pass`뿐인 `except`, `shell=True` subprocess. 설명은 [config/ast-grep/README.md](../config/ast-grep/README.md)에 있다.

근거: [crewAI 기준값](measurements/2026-11-12-crewai-baseline/README.md) 6절.

## 2. 그 커밋의 Joern 그래프 고르기

포크의 PR이나 main 푸시마다 Xeon의 분석 워크플로가 그래프를 만들고, 커밋 상태 `codeinside/joern-cpg`에 `codebase_hash`를 적는다. 질의할 해시는 이 상태에서 고른다.

```bash
python3 "$CODEINSIDE_DIR/scripts/joern/resolve_graph.py" \
  --checkout "$CREWAI_DIR" --sha <SHA> --repo Munsik-Park/crewAI --mcp-url "$MCP_URL"
```

| 출력 | 뜻 |
| --- | --- |
| `exact: true` | 그 커밋의 그래프다 |
| `exact: false`, `changed_files` | first-parent 조상의 그래프로 대신했다. 목록의 파일은 답이 요청한 커밋과 다를 수 있다 |
| `graph_sha: null` | 조상 100개 안에 그래프가 없다. 종료 코드 2 |
| `codebadger_status: loading` | 잠든 그래프를 올리는 중이다. 재부팅 뒤 기준 그래프는 약 62초 걸렸다. 아래 명령으로 `ready`가 될 때까지 기다린 뒤 3절로 넘어간다 |

`loading`일 때 질의하면 `success: true`가 오지만, `data`에는 결과 대신 Joern REPL 시작 출력이 오고 끝에 `No projects loaded`가 붙는다. 결과가 비었다고 읽지 않도록 먼저 상태를 확인한다.

```bash
uv run --no-project -q --with mcp==2.2.0 python "$CODEINSIDE_DIR/scripts/mcp/mcp_call.py" --url "$MCP_URL" \
  --call get_cpg_status '{"codebase_hash":"<해시>"}'
```

출력 마지막 줄 `text`의 `status`가 `ready`이면 묻는다.

### 그래프가 없을 때

포크 업스트림의 옛 커밋에는 그래프가 없다. 그 커밋을 가리키는 브랜치를 `Munsik-Park/crewAI`에 올리고 PR을 열면 워크플로가 그래프를 만든다. crewAI 규모에서 요청부터 ready까지 약 91~94초였다.

- 다른 레포에서 온 PR은 워크플로가 돌지 않는다. 브랜치는 포크 안에 있어야 한다.
- 그래프는 main first-parent 최근 20개와 열린 PR head만 남는다. PR을 닫으면 다음 정리 때 지워진다.

근거: [6단계 기록](measurements/2026-11-12-pr-analysis/README.md) 6~8절.

## 3. 묻기

### 명령으로

```bash
uv run --no-project -q --with mcp==2.2.0 python "$CODEINSIDE_DIR/scripts/mcp/mcp_call.py" --url "$MCP_URL" \
  --call run_cpgql_query '{"codebase_hash":"<해시>","query":"cpg.method.fullNameExact(\"lib/crewai/src/crewai/llms/base_llm.py:<module>.BaseLLM._emit_call_completed_event\").callIn.method.fullName.dedup.l"}'
```

- 첫 줄은 도구 목록, 이어서 `--call`마다 결과가 한 줄씩 나온다. `--call`은 여러 번 줄 수 있다.
- 메서드 이름은 `<레포 기준 파일 경로>:<module>.<클래스>.<메서드>` 꼴이다.
- 질의 예시 5개(호출하는 함수, 호출되는 함수, 두 단계 호출, 데이터 흐름 2개)는 [config/queries/crewai.json](../config/queries/crewai.json)에 있다.
- `run_cpgql_query`의 인자는 `codebase_hash`, `query`, `timeout`(초), `validate`다.

Serena도 같은 스크립트로 서버를 띄워 물을 수 있다.

```bash
uv run --no-project --with mcp==2.2.0 python "$CODEINSIDE_DIR/scripts/mcp/mcp_call.py" \
  --call find_referencing_symbols '{"name_path":"BaseLLM/_emit_call_completed_event","relative_path":"lib/crewai/src/crewai/llms/base_llm.py"}' \
  -- serena start-mcp-server --context "$CODEINSIDE_DIR/config/serena/context-readonly.yml" --project "$CREWAI_DIR" \
     --agent-interface tools --enable-web-dashboard False --open-web-dashboard False
```

### Claude Code 세션에 붙여서

codeinside 폴더에서 한 번 등록한다. `--scope local`이라 절대 경로는 사용자 설정에만 남고 레포에는 들어가지 않는다. 같은 이름이 이미 있으면 `claude mcp add`는 `already exists in local config`로 실패하므로(예: 4단계에서 `register.sh`로 opensre를 붙여 둔 경우), 먼저 지운다.

```bash
cd "$CODEINSIDE_DIR"
for s in ast-grep serena joern; do claude mcp remove --scope local "$s" 2>/dev/null || true; done
claude mcp add --scope local ast-grep -- \
  uvx --from "git+https://github.com/ast-grep/ast-grep-mcp@51d5a23f025c73c02032a98748dc06942548c5e1" ast-grep-server
claude mcp add --scope local serena -- \
  serena start-mcp-server --context "$CODEINSIDE_DIR/config/serena/context-readonly.yml" --project "$CREWAI_DIR" \
    --agent-interface tools --enable-web-dashboard False --open-web-dashboard False
claude mcp add --scope local --transport http joern "$MCP_URL"
claude mcp list
```

| 서버 | 쓰는 도구 |
| --- | --- |
| ast-grep | `find_code`(`project_folder`, `language`, `pattern`) |
| serena | `get_symbols_overview`, `find_symbol`, `find_referencing_symbols`, `find_declaration`, `find_implementations` |
| joern | `run_cpgql_query`, `get_cpg_status`. 해시는 2절에서 고른 것을 세션에 알려 준다 |

근거: `scripts/mcp/register.sh`(ast-grep, serena 등록), [5단계 기록](measurements/2026-11-12-joern-mcp/README.md) 5절(세 서버를 한 세션에서 부름). 5단계에서는 joern을 세션 설정 파일(`--mcp-config`의 `"type": "http"`)로 붙였다. `claude mcp add --transport http`로 붙이는 것은 `claude mcp add --help`에 있는 방법이고, [사용법 확인 기록](measurements/2026-11-12-usage-check/README.md)에서 돌려 `claude mcp list`가 `Connected`를 보였다.

## 한계

- 흔한 이름(`close` 같은)이나 다른 곳에서 다시 내보낸 심볼은 Joern 호출 관계를 쓰지 않는다. crewAI `Memory.close`는 Joern이 이은 7곳이 모두 다른 객체의 `close()`였다. 이런 경우는 Serena에 묻는다.
- Joern 그래프에는 `tests/`, `lib/*/tests/`, `platform_catalog.py`가 빠져 있다. 테스트에서의 호출은 Serena로 본다.
- codebadger는 같은 질의 결과를 300초 동안 캐시한다. 시간을 잴 때는 질의 문자열을 바꾼다.
- 조상 그래프로 대신했으면 `changed_files`에 있는 파일의 답은 믿지 않는다.
