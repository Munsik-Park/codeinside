# 2026-11-12 환경 구축 문서 준비 (단계 8)

## 1. 스크립트·설정 일반화 확인

| 확인 | 결과 | raw |
| --- | --- | --- |
| `register.sh`(crewAI, `PYRIGHTCONFIG`, `JOERN_MCP_URL` 지정) 뒤 `claude mcp list` | ast-grep, serena(`--project` crewAI), joern(HTTP) 모두 `Connected` | [register.log](raw/register.log) |
| `.serena/project.yml` | `project_name: "crewAI"`. 설정 값 13개가 [사용법 확인](../2026-11-12-usage-check/README.md) 방식으로 만든 파일과 같다 | [serena-pyright-compare.log](raw/serena-pyright-compare.log) |
| `pyrightconfig.json` | 사용법 확인 때 만든 파일과 바이트 단위로 같다. `extraPaths` 6개 | 같은 파일 |
| `config/joern-ci/workflow.example.yml` | crewAI main(`76fd6d3`) 워크플로와의 차이는 머리 주석 5줄뿐이다 | [workflow-example.diff](raw/workflow-example.diff) |
