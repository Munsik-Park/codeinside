# 도구 규칙

AI 세션용이다. 언제 어느 MCP를 쓰는지는 [README](../README.md), 환경 구축은 [setup.md](setup.md)에 있다.

## ast-grep

| 도구 | 주요 인자 |
| --- | --- |
| `find_code` | `project_folder`(체크아웃 절대 경로), `pattern`, `language`(`python`), `max_results`, `output_format`(`text`/`json`) |
| `find_code_by_rule` | `project_folder`, `yaml`(`id`, `language`, `rule` 필수) |
| `dump_syntax_tree` | `code`, `language`, `format`(`cst`/`ast`/`pattern`) |
| `test_match_code_rule` | `code`, `yaml` |

사전 후보 목록의 규칙은 [config/ast-grep/](../config/ast-grep/README.md)에 있다.

## Serena

읽기 도구 5개만 켜져 있다. `relative_path`는 체크아웃 루트 기준, `name_path`는 파일 안 심볼 경로(`BaseLLM/_emit_call_completed_event`)다.

| 도구 | 주요 인자 |
| --- | --- |
| `get_symbols_overview` | `relative_path` |
| `find_symbol` | `name_path_pattern`, `relative_path`, `depth`, `include_body` |
| `find_referencing_symbols` | `name_path`, `relative_path`(그 심볼이 있는 파일) |
| `find_declaration` | `relative_path`, `regex`(찾을 심볼을 그룹 하나로 감싼 정규식) |
| `find_implementations` | `name_path`, `relative_path`(파일만) |

## Joern

| 도구 | 주요 인자 |
| --- | --- |
| `get_cpg_status` | `codebase_hash`. 응답의 `status`가 `ready`여야 묻는다 |
| `run_cpgql_query` | `codebase_hash`, `query`(CPGQL), `timeout`(초), `validate` |

- 메서드 이름: `<레포 기준 파일 경로>:<module>.<클래스>.<메서드>`. 예: `lib/crewai/src/crewai/llms/base_llm.py:<module>.BaseLLM._emit_call_completed_event`
- `loading` 중 응답: `success: true`이고, `data`는 결과 대신 Joern REPL 시작 출력이며 끝 줄이 `io.joern.console.Error: No projects loaded`다([확인 기록](measurements/2026-11-12-usage-check/README.md) 2절).
- 같은 질의 문자열의 결과는 300초 동안 캐시된다.
- 호출 관계 결과에는 pysrc2cpg가 만드는 합성 메서드(`<metaClassAdapter>`)가 섞인다. 셀 때 뺀다([crewAI 기준값](measurements/2026-11-12-crewai-baseline/README.md) 5절).
- `get_call_graph`는 이 구성에서 E040으로 실패한다([기록](measurements/2026-11-12-ai-docs/README.md) 2절). 호출 관계는 `run_cpgql_query`로 묻는다.
- 질의 예시: [config/queries/crewai.json](../config/queries/crewai.json)(Q1 호출하는 함수, Q2 호출되는 함수, Q3 두 단계 호출, Q4와 Q5 데이터 흐름)
