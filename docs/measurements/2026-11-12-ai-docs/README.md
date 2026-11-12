# 2026-11-12 환경 구축 문서 준비 (단계 8)

## 1. 스크립트·설정 일반화 확인

| 확인 | 결과 | raw |
| --- | --- | --- |
| `register.sh`(crewAI, `PYRIGHTCONFIG`, `JOERN_MCP_URL` 지정) 뒤 `claude mcp list` | ast-grep, serena(`--project` crewAI), joern(HTTP) 모두 `Connected` | [register.log](raw/register.log) |
| `.serena/project.yml` | `project_name: "crewAI"`. 설정 값 13개가 [사용법 확인](../2026-11-12-usage-check/README.md) 방식으로 만든 파일과 같다 | [serena-pyright-compare.log](raw/serena-pyright-compare.log) |
| `pyrightconfig.json` | 사용법 확인 때 만든 파일과 바이트 단위로 같다. `extraPaths` 6개 | 같은 파일 |
| `config/joern-ci/workflow.example.yml` | crewAI main(`76fd6d3`) 워크플로와의 차이는 머리 주석 5줄뿐이다 | [workflow-example.diff](raw/workflow-example.diff) |

## 2. AI 세션 확인

`claude -p`에 README.md 읽기와 MCP 3개만 허용했다(`--strict-mcp-config`). 받은 값은 crewAI 체크아웃, main `76fd6d3`, 그래프 ID `adfc58f938d764b9`다([ai-session.log](raw/ai-session.log)).

| 질문 | 세션이 고른 도구 | 답 | 기준 |
| --- | --- | --- | --- |
| `BaseLLM._emit_call_completed_event`를 실제로 참조하는 곳 | `get_cpg_status`(ready 확인), Serena `find_referencing_symbols` | 73 | Serena 73, 같다 |
| 그 함수를 부르는 함수를 부르는 함수(정확히 두 단계 위, 중복 제외) | Joern `get_call_graph`(E040 오류), `run_cpgql_query`, Serena `find_referencing_symbols`(테스트 쪽) | 36 | Joern Q3 64, 다르다 |
| 함수 안에서 `global` 문을 쓰는 곳 | ast-grep `find_code_by_rule` | 17 | `py-global-state` 17, 같다 |

- 세션은 그래프를 조상 그래프로 판단하지 않았다.
- Q3을 `mcp_call.py`로 다시 물으면 그대로 64, 두 단계 모두에서 `<metaClassAdapter>` 메서드를 빼면 36이다. 뺀 숫자는 세션 답 36과 같다([q3-metaclassadapter.log](raw/q3-metaclassadapter.log)).
