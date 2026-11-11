# 2026-11-12 PR 자동 분석 (단계 6, 진행 중)

[docs/plan.md](../../plan.md) 단계 6의 원본 기록이다. 이 기록을 쓰는 시점에 끝내는 기준("시험 PR 하나로 그 SHA의 그래프가 저장되고 MCP로 질의된다")은 아직 채우지 못했다. plan.md와 architecture.md는 고치지 않았다.

## 지금까지 결과

| 할 일 | 상태 | 근거 |
| --- | --- | --- |
| 업스트림 워크플로 끄기 | opensre: 13개 모두 `disabled_manually`. crewAI: Actions를 켜기 전에 19개를 `.github/workflows-upstream/`으로 옮겼다. 업스트림 워크플로 run은 두 포크 모두 0 | 1절, 3절 |
| 분석 러너 | crewAI에 레포 단위 ephemeral 러너 하나(라벨 `joern`, 노드 3, 메모리 2g)가 등록돼 있다. 전용 uid로 바꾸는 설치는 준비만 했다 | 4절 |
| 러너에서 codebadger 연결 | 프록시 컨테이너로 MCP 4242에만 닿는다. 질의 워커, Postgres, Redis, 호스트 루프백 포트에는 닿지 않는다 | 5절, [raw/probe-network.log](raw/probe-network.log) |
| 분석 워크플로 | crewAI PR #1에서 실제로 돌았다. 그래프 생성은 됐지만 적재가 300초 timeout으로 실패했다. 그래프 제외 규칙을 고친 뒤 기준 커밋 적재는 42초다 | 6절, [crewAI 기준값](../2026-11-12-crewai-baseline/README.md) |
| SHA와 그래프 대응, 보관, 조상 그래프 대체 | 설계와 스크립트는 있다. 시험 안 됨 | 7절 |
| 시험 PR로 그래프 저장과 MCP 질의 | 아직 | |

## 1. opensre에서 막힌 경위

### 업스트림 워크플로

| 시점 | 상태 | 근거 |
| --- | --- | --- |
| 작업 전 | 워크플로 13개 중 12개가 이미 `disabled_manually`, `CI`(ci.yml) 하나만 `active` | [raw/opensre-workflows-before.tsv](raw/opensre-workflows-before.tsv) |
| `gh workflow disable ci.yml` 뒤 | 13개 모두 `disabled_manually`. 파일은 지우지 않았다 | [raw/opensre-workflows-after.tsv](raw/opensre-workflows-after.tsv) |

- plan.md는 14개라고 적었지만 `.github/workflows/`의 나머지 한 파일은 `README.md`다.
- fork PR 승인 정책을 `first_time_contributors`에서 `all_external_contributors`로 바꿨다([raw/opensre-fork-pr-approval.log](raw/opensre-fork-pr-approval.log)).

### 러너 등록

- Xeon의 CI 러너 5개는 `connev-llm/librechat`에 레포 단위로 등록된 ephemeral 러너다(라벨 `self-hosted,librechat-ci,librechat-ci-wide/fast`). opensre에 등록된 러너는 0개였다.
- Munsik-Park은 User 계정이라 계정 단위 러너가 없다(`users/Munsik-Park/actions/runners` → 404). 그래서 opensre 레포 단위로 전용 러너를 새로 등록했다(4절).

### 워크플로가 돌지 않음

opensre PR #36(워크플로 추가)을 열었지만 run이 생기지 않았다.

| 확인 | 결과 |
| --- | --- |
| PR #36 head `e4352e8`의 check suite | `claude` 앱 하나. `github-actions` suite 없음 |
| PR #35 head(11-02, base main, 당시 `CI`가 `active`)의 check suite | 같음. CI가 켜져 있었는데도 돌지 않았다 |
| 2026-10-23 이후 run 수 | 0 |
| API로 본 Actions 설정 | `enabled: true`, `allowed_actions: all`, 레포 archived·disabled 아님 |

- 사용자 확인: 업스트림 워크플로가 잘못 실행되어 GitHub 쪽에서 이 레포의 Actions가 막혔고, 풀 수 없다.
- 그래서 시험 대상을 crewAI로 바꿨다. opensre 러너 등록은 지웠고(남은 등록 0), PR #36은 사유를 댓글로 남기고 닫았다. opensre 쪽 기록은 그대로 둔다.

## 2. 대상을 crewAI로 바꾼 이유

- opensre 포크는 Actions가 GitHub 쪽에서 막혀 워크플로를 돌릴 수 없다.
- 같은 사고를 막으려면 새 포크에서는 업스트림 워크플로가 한 번도 돌지 않아야 한다. 그래서 Actions를 켜기 전에 워크플로를 치우는 순서를 먼저 확인했다(3절).

## 3. crewAI 포크 정리

| 항목 | 값 | 근거 |
| --- | --- | --- |
| 포크 | Munsik-Park/crewAI(사용자가 만듦, 2026-11-11T18:30:26Z), 브랜치 main 하나 | [raw/crewai-fork-setup.log](raw/crewai-fork-setup.log) |
| 기준 커밋 | `71d68117e38f620dff02ec1dc358f37a1f74a740`(포크 시점 main, 업스트림 main과 같음) | 같은 파일 |
| 업스트림 워크플로 | 19개, 예약 실행 포함 4개(`build-uv-cache`, `nightly`, `stale`, `vulnerability-scan`) | 같은 파일 |
| fork PR 승인 정책 | `all_external_contributors` | 같은 파일 |

### 켜기 전에 끌 수 있는가

- GitHub 문서에서 확인한 것: "공개 레포를 포크하면 예약 워크플로는 기본으로 꺼진다"(`github/docs` `data/reusables/actions/scheduled-workflows-disabled.md`). push, pull_request 같은 다른 트리거가 Actions를 켠 직후 어떻게 되는지는 문서에서 찾지 못했다.
- 포크 직후 API 상태: `actions/workflows`의 `total_count`가 0이었다(파일은 19개). `PUT actions/workflows/tests.yml/disable`은 404였다. 워크플로가 등록되기 전이라 API로 끌 대상이 없었다.
- 그래서 Actions를 켠 뒤 API로 끄는 순서로는 "한 번도 돌지 않는다"를 보장할 수 없다고 판단했다.

### 워크플로 파일 옮기기

- Actions를 켜기 전에 `.github/workflows/*.yml` 19개를 `.github/workflows-upstream/`으로 `git mv`하고 README를 더해 main에 푸시했다(커밋 `b4654c1`, 부모는 기준 커밋). Actions는 이 폴더를 읽지 않는다.
- 푸시 뒤: run 0, 등록된 워크플로 0, `.github/workflows` 없음(404).
- 그 뒤 사용자가 Actions를 켰고, 등록된 워크플로는 분석 워크플로 하나뿐이다.
- 원칙: 이 포크의 main은 업스트림과 동기화하지 않는다. 동기화하면 업스트림의 새 워크플로가 `.github/workflows/`로 다시 들어온다. 정답 사례로 쓸 업스트림 커밋은 SHA로 가져온다. 이 원칙은 포크의 `.github/workflows-upstream/README.md`에도 적었다.

## 4. 분석 러너

librechat 러너와 같은 ephemeral 방식이다. supervisor가 작업마다 등록 토큰을 발급해 러너 컨테이너 하나를 띄우고, 컨테이너는 작업 하나를 끝내면 지워진다.

| 파일 | 하는 일 |
| --- | --- |
| [scripts/xeon/joern-ci/runner-supervisor.sh](../../../scripts/xeon/joern-ci/runner-supervisor.sh) | PAT로 레포 단위 등록 토큰을 발급하고 러너 컨테이너를 띄운다. 작업 없이 끝난 등록은 지운다 |
| [scripts/xeon/joern-ci/entrypoint.sh](../../../scripts/xeon/joern-ci/entrypoint.sh) | `config.sh --ephemeral --disableupdate --labels joern`. 러너 이름은 컨테이너 ID로 짓는다(작업 로그에 공개되므로 호스트 이름을 쓰지 않는다) |
| [scripts/xeon/joern-ci/build-runner-image.sh](../../../scripts/xeon/joern-ci/build-runner-image.sh) | librechat 러너 이미지 위에 전용 uid 사용자를 더한 이미지를 만든다 |
| [scripts/xeon/joern-ci/install.sh](../../../scripts/xeon/joern-ci/install.sh), [retarget.sh](../../../scripts/xeon/joern-ci/retarget.sh) | sudo 설치, 대상 레포 변경 |
| [config/joern-ci/](../../../config/joern-ci/) | 설정 예시와 systemd 유닛 2개 |

| 러너 컨테이너 설정 | 값 | 확인 |
| --- | --- | --- |
| cpuset / mems | `30-39,70-79` / 3 | cgroup `cpuset.cpus.effective`, `cpuset.mems.effective`([raw/probe-network.log](raw/probe-network.log)) |
| 메모리 | 2g(swap 포함) | cgroup `memory.max=2147483648` |
| CPU | 4개(`cpu.max=400000 100000`) | 같음 |
| 권한 | `--cap-drop ALL`, `no-new-privileges`, non-root | `docker inspect` |
| `ACTIONS_RESULTS_URL` | 이미지 ENV에 librechat 캐시 서버 주소가 있어 entrypoint에서 뺐다 | 러너 프로세스 환경에 없음 |

- PAT는 fine-grained, `Administration: Read and write` 하나다. 등록 토큰 발급과 러너 삭제가 administration write, 러너 조회가 read다(`github/docs` `src/github-apps/data/fpt-2022-11-28/fine-grained-pat-permissions.json`). 커밋 상태는 워크플로의 `GITHUB_TOKEN`(`statuses: write`)이 쓴다.
- PAT는 Xeon의 `/etc/codeinside-joern-ci/runner.env`(root, 600)에만 있다.
- 노드 3 메모리 계산: 질의 예산 80G + 생성 8G + runner-5 32G + 분석 러너 2G = 122G / 126G. runner-4의 노드 3 사용량은 5단계와 같이 빠져 있다.

### 전용 uid (준비만 함)

- 지금 러너 컨테이너는 이미지의 `runner`(uid 1000)로 돈다. 호스트에서 uid 1000은 작업자 로그인 계정이다. 그래서 공개 레포 PR 코드가 이 uid로 돌고, 러너가 만든 파일도 호스트에서 이 계정 소유가 된다.
- 바꾸는 방법: 호스트에 로그인할 수 없는 시스템 계정 `codeinside-runner`를 만들고, 같은 uid/gid의 사용자 `jrunner`를 더한 이미지를 쓴다. `/actions-runner` 전체를 chown하면 674MB 레이어가 생기므로 폴더 자체와 `_diag`, `_work`만 새 uid 소유로 둔다.
- 임시 uid 990으로 이미지를 만들어 봤다. 컨테이너 안 `id`가 `uid=990(jrunner)`, `/actions-runner`에 쓸 수 있었고, 더해진 레이어는 0B였다. 시험 이미지는 지웠다.
- 설치는 sudo가 필요해 아직 하지 않았다. `install.sh`를 다시 실행하면 계정, 설정 키, CI 소스 폴더 소유자, 유닛을 갱신하고 이미지를 빌드한다.

## 5. 러너에서 codebadger에 닿는 방법

선택지와 판단:

| 방법 | 러너가 닿는 곳 | 판단 |
| --- | --- | --- |
| A. 프록시 컨테이너 | MCP 4242 하나 | 채택 |
| B. 러너를 `codebadger` 네트워크에 붙임 | MCP, 인증 없는 질의 워커, Postgres, Redis | 5단계 격리 근거가 깨져 뺐다 |
| C. host 네트워크 | 호스트 루프백 전체 | 뺐다 |

```
러너 컨테이너 ── codeinside-joern-ci ── codeinside-mcp-proxy ── codebadger ── codebadger-mcp:4242
```

- 프록시: [tcp_proxy.py](../../../scripts/xeon/joern-ci/tcp_proxy.py)(asyncio, 대상 고정). 이미지는 새로 받지 않고 이미 부팅 복원 대상인 `codebadger-mcp` 이미지의 Python을 쓴다. 메모리 128m, CPU 1, 읽기 전용 루트, `nobody`, 노드 3.
- 네트워크와 프록시는 [setup-network.sh](../../../scripts/xeon/joern-ci/setup-network.sh)가 만들고, 부팅 때 `codeinside-joern-ci-net.service`가 다시 만든다(Docker data-root가 tmpfs).
- 러너 이미지에는 Python 3.10만 있고 `mcp` 패키지가 없다. 그래서 표준 라이브러리만 쓰는 MCP 클라이언트 [scripts/mcp/mcp_http.py](../../../scripts/mcp/mcp_http.py)를 만들었다.

[scripts/probe-network.sh](scripts/probe-network.sh)로 러너 네트워크의 일회용 컨테이너에서 확인한 결과([raw/probe-network.log](raw/probe-network.log)):

| 대상 | 결과 |
| --- | --- |
| 프록시 4242(MCP `initialize`) | HTTP 200, `CodeBadger Server` |
| 프록시의 다른 포트(8080) | 막힘 |
| 질의 워커 8080, codebadger-mcp 직접(주소, 이름), Postgres, Redis | 모두 막힘 |
| 호스트 게이트웨이 4242, 55432, 56379, 13371 | 모두 막힘 |
| GitHub API | 200 |

## 6. 분석 워크플로

| 위치 | 파일 |
| --- | --- |
| crewAI 포크 | `.github/workflows/codeinside-joern-cpg.yml`(PR #1, 브랜치 `codeinside/joern-cpg`) |
| codeinside | [scripts/ci/joern_cpg_job.py](../../../scripts/ci/joern_cpg_job.py) |

- 트리거: PR `opened`, `synchronize`, `reopened`, main 푸시
- 조건: `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`. 포크에서 온 PR은 돌지 않고 main 푸시는 돈다.
- 러너 `[self-hosted, joern]`, 권한 `contents: read`, `statuses: write`, `actions/checkout`은 v7.0.1 커밋으로 고정했다.
- codeinside 스크립트는 고정 커밋(`CODEINSIDE_REF`)으로 체크아웃한다.
- 작업: 그 SHA를 `git archive`로 CI 소스 폴더에 풀고 `generate_cpg`(local)를 부른다. ready가 되면 커밋 상태를 남기고, 확인 질의(그래프 규모와 `--queries`로 준 질의)를 MCP로 묻는다.
- local 소스로 부르는 이유: codebadger의 github 소스 캐시 키는 레포·브랜치 이름이다(`core_tools.py` 496~531행). 브랜치가 움직이면 다른 커밋의 그래프를 다시 쓴다. local 소스는 파일 내용 해시가 키다(`_fingerprint_local_source`).

### 사전 시험과 첫 run

| 시험 | 결과 | 근거 |
| --- | --- | --- |
| opensre main(`a5c1acbd`) dry-run(커밋 상태 호출만 출력으로 바꿈) | 내용 해시가 5단계 그래프와 같아(`a5b31c170fa23d65`) 캐시를 그대로 썼다. Q1 131건 | [raw/pretest-job-dry-run.log](raw/pretest-job-dry-run.log) |
| crewAI PR #1 run `43080344648`(head `60ab746`) | 워크플로가 실제로 돌았다. 소스 풀기, 프런트엔드(23초)까지 성공하고, 적재가 300초 timeout으로 3번 실패했다. 커밋 상태는 pending 다음 failure | [raw/crewai-pr1-run.log](raw/crewai-pr1-run.log), [raw/crewai-pr1-codebadger.log](raw/crewai-pr1-codebadger.log) |

- 원인은 그래프 크기로 봤다. 그때 규칙은 최상위 `tests/`만 뺐다. `lib/*/tests`와 생성 파일 `platform_catalog.py`(7.8MB)를 빼는 규칙을 더하자, 기준 커밋 그래프는 18MB가 됐고 적재는 42초에 끝났다([crewAI 기준값](../2026-11-12-crewai-baseline/README.md) 1절).
- 실패한 그래프는 `remove_cpg`(`delete_files: true`)로 지웠다(567MB). `delete_files` 없이 부르면 서버만 내리고 그래프는 디스크에 남는다. 그 상태에서 `get_cpg_status`를 부르면 다시 적재를 시작한다.

## 7. SHA와 그래프 대응, 보관, 조상 그래프 대체 (제안, 시험 안 됨)

### 대응 기록

- 커밋 상태 `codeinside/joern-cpg`를 쓴다. 작업 시작 때 pending, ready가 되면 success와 설명 `codebase_hash=<hash>`, 실패하면 failure와 원인을 남긴다. `target_url`은 그 run이다.
- 이유: SHA에 바로 붙고, PR 화면에 보이고, 작업자 쪽에서 gh로 읽을 수 있다. 저장소를 따로 두지 않아도 된다.
- 내용 해시라서 파일 내용이 같은 두 커밋은 같은 `codebase_hash`를 받는다(사전 시험에서 확인). 그래서 그래프를 지울 때는 그 해시를 가리키는 SHA가 더 없는지 봐야 한다.

### 조상 그래프 대체

[scripts/joern/resolve_graph.py](../../../scripts/joern/resolve_graph.py)가 질의할 그래프를 고른다.

1. 요청한 SHA부터 `git rev-list --first-parent`로 조상을 가까운 순서로 본다. PR 브랜치는 PR 커밋을 거쳐 분기점의 main 커밋으로, main은 푸시 단위 커밋으로 이어진다.
2. 커밋 상태는 GraphQL 한 번으로 묶어 읽는다. success인 첫 커밋의 `codebase_hash`를 고른다.
3. `--mcp-url`을 주면 codebadger에 그래프가 아직 있는지(`ready`, `sleeping`, `loading`) 보고, 지워졌으면 다음 조상으로 넘어간다. `get_cpg_status`는 잠든 그래프의 적재를 시작시키므로, 고른 그래프는 질의 전에 올라온다.
4. 요청한 SHA가 아닌 조상을 골랐으면 그 사이에 바뀐 파일 목록을 같이 돌려준다. 질의하는 쪽은 이 파일에 대한 답이 다를 수 있다는 것을 알고 쓴다.

### 보관 개수

| 항목 | 값 | 근거 |
| --- | --- | --- |
| 그래프 하나의 디스크 | `cpg.bin` 18MB(crewAI 기준 커밋) | [crewAI 기준값](../2026-11-12-crewai-baseline/README.md) |
| CI 소스 폴더 | SHA 하나에 623MB | 같은 기록 |
| 동시에 올라와 있을 수 있는 그래프 | 16개(예산 80G / 예약 5G). 넘으면 codebadger가 LRU로 잠재운다(디스크에는 남음) | 5단계 기록, `joern_server_manager.py` |
| 루트 LV 여유 | 313G | `df` |

제안:
- main 최근 푸시 20개와 열린 PR의 head SHA를 남기고 나머지는 `remove_cpg`(`delete_files: true`)로 지운다. 지우기 전에 같은 `codebase_hash`를 쓰는 남길 SHA가 없는지 확인한다.
- CI 소스 폴더는 그래프가 ready가 되면 지운다. codebadger는 적재 뒤 자기 쪽 소스 사본을 지웠고, 잠든 그래프는 `cpg.bin`에서 다시 올린다. 그러면 SHA 하나에 디스크 약 18MB만 남는다. 지금 작업 스크립트는 지우지 않는다.

## 확인 안 됨

- opensre Actions가 막힌 정확한 원인(GitHub 쪽 조치)
- 업스트림 워크플로 파일을 옮긴 뒤 Actions를 켠 상태에서 main 푸시가 분석 워크플로만 띄우는지(main 푸시는 아직 시험하지 않았다)
- 조상 그래프 대체, 보관 정리
- 전용 uid 이미지로 러너가 실제로 등록되고 작업을 받는지
- 러너·프록시 유닛의 재부팅 복원
- 러너 컨테이너가 외부 네트워크로 나가는 범위. librechat 러너와 달리 egress 허용 목록을 걸지 않았다

## 원본 파일

| 파일 | 내용 |
| --- | --- |
| `raw/opensre-workflows-{before,after}.tsv` | opensre 워크플로 상태 |
| `raw/opensre-fork-pr-approval.log` | opensre fork PR 승인 정책 변경 |
| `raw/crewai-fork-setup.log` | crewAI 포크 직후 상태, 워크플로 목록, 이동 기록 |
| `raw/probe-network.log` | 러너·프록시 컨테이너 설정과 닿는 곳·막힌 곳 |
| `raw/pretest-job-dry-run.log` | 작업 스크립트 사전 시험 |
| `raw/crewai-pr1-run.log`, `raw/crewai-pr1-codebadger.log` | crewAI PR #1 첫 run 작업 로그와 codebadger 로그 |
| `scripts/probe-network.sh` | 위 확인에 쓴 스크립트 |
