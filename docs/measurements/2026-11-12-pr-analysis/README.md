# 2026-11-12 PR 자동 분석 (단계 6)

[docs/plan.md](../../plan.md) 단계 6의 원본 기록이다. 시험 대상은 opensre에서 crewAI 포크로 바꿨다(1, 2절). plan.md와 architecture.md는 고치지 않았다.

## 결과 요약

| 끝내는 기준 / 할 일 | 결과 | 근거 |
| --- | --- | --- |
| 시험 PR 하나로 그 SHA의 그래프가 저장되고 MCP로 질의된다 | crewAI PR #1 head `848d15d`에서 워크플로가 그래프를 만들고(요청부터 ready까지 91초), 커밋 상태에 `codebase_hash=c8a03dcf21488d21`을 남기고, Q1~Q5를 MCP로 물었다(29, 18, 64, 6, 1,634건으로 기준값과 같음). 작업자 쪽에서도 resolver로 그 그래프를 골라 SSH 터널로 Q1을 물었다(29건) | 6절, [raw/crewai-pr1-run2.log](raw/crewai-pr1-run2.log), [raw/worker-resolve-q1.log](raw/worker-resolve-q1.log) |
| 업스트림 워크플로 끄기 | opensre: 13개 모두 `disabled_manually`. crewAI: Actions를 켜기 전에 19개를 `.github/workflows-upstream/`으로 옮겼다. 업스트림 워크플로 run은 두 포크 모두 0 | 1절, 3절 |
| 분석 러너 | crewAI에 레포 단위 ephemeral 러너(라벨 `joern`, 노드 3, 메모리 2g, 전용 uid 994)가 등록돼 작업을 받는다 | 4절 |
| 러너에서 codebadger 연결 | 프록시 컨테이너로 MCP 4242에만 닿는다. 질의 워커, Postgres, Redis, 호스트 루프백 포트에는 닿지 않는다 | 5절, [raw/probe-network.log](raw/probe-network.log) |
| SHA와 그래프 대응 | 커밋 상태 `codeinside/joern-cpg`의 설명에 `codebase_hash`를 남긴다 | 7절 |
| 조상 그래프 대체 | 시험 PR #2(head `5014f84`, 부모 `848d15d`)의 그래프가 만들어지는 동안 resolver가 부모 그래프를 고르고 바뀐 파일을 돌려줬다. success 뒤에는 자기 그래프를 골랐다 | 7절, [raw/ancestor-fallback.log](raw/ancestor-fallback.log) |
| 보관 개수 | main first-parent 최근 20개와 열린 PR head의 그래프만 남기고, ready 뒤 소스 폴더를 지운다. crewAI PR #3에서 닫힌 PR #2 그래프와 남은 소스 폴더 3개(각 623MB)가 지워진 것을 확인했다. joern 러너가 하나라는 전제 위에서만 맞다 | 7절, 8절 |
| main 푸시 | PR #1 병합 커밋 `898f7e6`에서 그래프와 커밋 상태가 남고 Q1~Q5가 질의됐다 | 8절 |
| 재부팅 복원 | librechat 러너 5개, joern 러너, 프록시, codebadger 스택이 다시 떴다. 기준 그래프 `fafd8959bb1b7ee0`이 남아 있어 Q1이 29건으로 나왔다 | 9절, [raw/reboot-restore.log](raw/reboot-restore.log) |

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

### 전용 uid

- 처음에는 러너 컨테이너가 이미지의 `runner`(uid 1000)로 돌았다. 호스트에서 uid 1000은 작업자 로그인 계정이다. 공개 레포 PR 코드가 이 uid로 돌고, 러너가 만든 파일도 호스트에서 이 계정 소유가 됐다.
- 바꾼 방법: 호스트에 로그인할 수 없는 시스템 계정 `codeinside-runner`(uid 994, gid 984)를 만들고, 같은 uid/gid의 사용자 `jrunner`를 더한 이미지 `codeinside-joern-runner:latest`를 쓴다. `/actions-runner` 전체를 chown하면 674MB 레이어가 생기므로 폴더 자체와 `_diag`, `_work`만 새 uid 소유로 둔다. 더해진 레이어는 0B다.
- 첫 설치에서 net 유닛이 `ERROR: mkdir /home/codeinside-ci: permission denied`로 실패했다. 서비스 계정에 홈 폴더가 없어 `docker build`가 `~/.docker`를 만들지 못했다. 같은 조건을 재현한 뒤, 두 유닛에 `StateDirectory=codeinside-joern-ci`와 `DOCKER_CONFIG=/var/lib/codeinside-joern-ci/docker`를 넣어 고쳤다.
- 적용 뒤 확인: 러너 컨테이너 `Config.User=994:984`, 컨테이너 안 `run.sh`가 uid 994로 돈다. CI 소스 폴더는 `994:984` 소유다. 이 러너가 PR #1, #2 작업을 받았다.

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

### 끝내는 기준 시험

제외 규칙을 고친 뒤 워크플로의 codeinside 고정 커밋을 올리고 `--queries config/queries/crewai.json`을 더해 PR #1에 푸시했다(`synchronize`).

| 시각(UTC) | run `43140448522`, head `848d15d` |
| --- | --- |
| 02:18:34 | 커밋 상태 pending |
| 02:18:38 | 소스 풀기 |
| 02:18:53 | `generate_cpg` → `codebase_hash=c8a03dcf21488d21`, generating |
| 02:20:09 | ready(요청부터 91초) |
| 02:20:10 | 커밋 상태 success, 설명 `codebase_hash=c8a03dcf21488d21` |
| 02:20:10~20 | STATS(파일 984, 메서드 36,950, 호출 254,956), Q1 29, Q2 18, Q3 64, Q4 6, Q5 1,634 |

- 그래프 규모와 Q1~Q5 결과 수는 기준 커밋과 같다. PR #1은 워크플로 파일만 더했으므로 Python 그래프는 같고, 파일 내용 해시는 달라 `codebase_hash`는 다르다.
- 작업자 쪽: SSH 터널(로컬 14242 → Xeon 루프백 4242)로 `resolve_graph.py --mcp-url`을 돌리자 `exact: true`, `codebase_hash=c8a03dcf21488d21`, `codebadger_status: ready`였다. 같은 해시로 Q1을 묻자 29건(Joern 안 0.36ms, 왕복 0.21초)이었다([raw/worker-resolve-q1.log](raw/worker-resolve-q1.log)).

## 7. SHA와 그래프 대응, 보관, 조상 그래프 대체

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

시험: PR #1 브랜치 위에 `lib/crewai/src/crewai/llms/base_llm.py` 주석 한 줄을 더한 PR #2(head `5014f84`, base `codeinside/joern-cpg`)를 열고, 5초마다 resolver를 돌렸다([raw/ancestor-fallback.log](raw/ancestor-fallback.log), [raw/crewai-pr2-run.log](raw/crewai-pr2-run.log)).

| 시각(UTC) | 요청 SHA의 커밋 상태 | 고른 그래프 | 거리 | `codebase_hash` | 바뀐 파일 |
| --- | --- | --- | --- | --- | --- |
| 02:21:37~02:22:00(5회) | 없음 | `848d15d`(부모) | 1 | `c8a03dcf21488d21` | `base_llm.py` |
| 02:22:06~02:23:34(16회) | pending | `848d15d`(부모) | 1 | `c8a03dcf21488d21` | `base_llm.py` |
| 02:23:39 | success | `5014f84`(자기) | 0 | `a64d93d2b98745b7` | 없음 |

- PR #2 run은 02:22:20에 `generate_cpg`를 부르고 02:23:36에 ready, 커밋 상태 success를 남겼다. Q1~Q5도 MCP로 물었다.
- PR #2는 시험용이라 병합하지 않는다.

### 보관 개수

| 항목 | 값 | 근거 |
| --- | --- | --- |
| 그래프 하나의 디스크 | `cpg.bin` 18MB(crewAI 기준 커밋) | [crewAI 기준값](../2026-11-12-crewai-baseline/README.md) |
| CI 소스 폴더 | SHA 하나에 623MB | 같은 기록 |
| 동시에 올라와 있을 수 있는 그래프 | 16개(예산 80G / 예약 5G). 넘으면 codebadger가 LRU로 잠재운다(디스크에는 남음) | 5단계 기록, `joern_server_manager.py` |
| 루트 LV 여유 | 313G | `df` |

처음 제안은 아래 두 가지였고, 사용자 결정에 따라 그대로 구현했다(후속 PR, 8절).
- main 최근 20개와 열린 PR의 head SHA를 남기고 나머지는 `remove_cpg`(`delete_files: true`)로 지운다. 지우기 전에 같은 `codebase_hash`를 쓰는 남길 SHA가 없는지 확인한다.
- CI 소스 폴더는 그래프가 ready가 되면 지운다. codebadger는 적재 뒤 자기 쪽 소스 사본을 지웠고, 잠든 그래프는 `cpg.bin`에서 다시 올린다. 그러면 SHA 하나에 디스크 약 18MB만 남는다.

## 8. 후속: main 푸시와 보관 정리

codeinside PR #9와 crewAI PR #1을 병합한 뒤 진행했다.

### main 푸시

PR #1 병합으로 생긴 main 머지 커밋 `898f7e6`(부모 `b4654c1`, `848d15d`)에서 분석 워크플로가 `push` 이벤트로 돌았다(run `43143851170`, [raw/crewai-main-push-run.log](raw/crewai-main-push-run.log)).

| 시각(UTC) | 단계 |
| --- | --- |
| 02:48:12 | 커밋 상태 pending |
| 02:48:21 | `generate_cpg` → `codebase_hash=c8a03dcf21488d21`, 상태 `loading` |
| 02:49:21 | ready(요청부터 66초) |
| 02:49:22 | 커밋 상태 success |
| 02:49:25~31 | Q1~Q5 29, 18, 64, 6, 1,634건 |

- 머지 커밋은 PR #1 head와 파일 내용이 같아 같은 `codebase_hash`를 받았다. codebadger는 그래프를 새로 만들지 않았다. 잠들어 있던 그 그래프를 다시 적재했다(`loading` → ready 60초).
- 업스트림 워크플로는 이 푸시에서도 돌지 않았다. 등록된 워크플로는 분석 워크플로 하나다.

### 보관 정리 구현

| 파일 | 바뀐 것 |
| --- | --- |
| [scripts/ci/joern_cpg_job.py](../../../scripts/ci/joern_cpg_job.py) | 그래프가 ready(또는 실패)가 되면 풀어 둔 소스 폴더를 지운다. 만든 그래프를 CI 소스 폴더의 색인 `.cpg-index.jsonl`에 한 줄(레포, SHA, `codebase_hash`, 상태) 더한다 |
| [scripts/ci/prune_cpgs.py](../../../scripts/ci/prune_cpgs.py) | 새 파일. 남길 SHA를 정하고, 색인에 있는 나머지 그래프와 남은 소스 폴더를 지운다 |
| crewAI `.github/workflows/codeinside-joern-cpg.yml`(PR #3) | 고정 커밋을 올리고, 작업 뒤 `prune_cpgs.py --keep-main 20` 단계(`if: success() \|\| failure()`)와 권한 `pull-requests: read`를 더했다 |

- 남기는 SHA: main first-parent 최근 20개 커밋과 열린 PR의 head. main을 머지 커밋으로만 바꾸면 first-parent 커밋 하나가 푸시 하나다. 지금은 main first-parent 20개 가운데 그래프가 있는 것이 `898f7e6` 하나이고, 나머지는 포크 전 업스트림 커밋이다.
- SHA와 `codebase_hash`의 대응은 커밋 상태에서 읽는다(GraphQL 한 번). 남길 SHA 하나라도 가리키는 `codebase_hash`는 지우지 않는다.
- 지우는 범위는 색인에 있는 그래프뿐이다. 수동으로 만든 기준값 그래프(crewAI `fafd8959bb1b7ee0`, opensre `a5b31c170fa23d65`)는 색인에 없어 건드리지 않는다.
- 정리 단계는 joern 러너가 하나라는 전제를 둔다. 아래에 따로 적었다.

### 전제: joern 러너 하나

정리 단계는 CI 소스 폴더의 `<레포 이름>-*`, `.<레포 이름>-*` 폴더를 모두 지우고, 색인 파일을 읽은 뒤 통째로 다시 쓴다. 이 동작은 정리 단계가 도는 동안 같은 폴더에 소스를 풀거나 색인에 줄을 더하는 작업이 없어야 맞다.

- 지금 맞는 이유: 분석 러너는 supervisor 하나가 띄우는 컨테이너 하나(`codeinside-joern-runner`)뿐이다. ephemeral 러너라 한 번에 작업 하나만 받는다. 그래서 작업 스크립트와 정리 단계가 같은 작업 안에서 차례로 돌고, 다른 작업은 그사이에 끼어들지 않는다.
- 워크플로 `concurrency` 그룹은 SHA별이라 서로 다른 SHA의 작업을 줄 세우지 않는다. 지금 작업이 차례로 도는 것은 러너가 하나라서다.
- 러너를 늘리면 깨지는 것:
  - 다른 작업이 풀고 있는 소스 폴더를 정리 단계가 지울 수 있다.
  - 정리 단계가 색인을 다시 쓰는 사이에 다른 작업이 더한 줄이 사라질 수 있다. 그러면 그 그래프는 다음 정리에서 지울 대상으로 잡히지 않는다.
- 결정: 러너를 늘릴 때 소스 폴더와 색인 정리를 다시 설계한다. 그전까지 joern 라벨 러너는 하나로 둔다.
- 이 구현 전에 CI가 만든 그래프 2개(SHA 3개)는 러너 uid로 색인에 직접 채워 넣었다(`recorded_at: backfill`).

### 시험 (crewAI PR #3)

로컬 dry-run으로 남길 것과 지울 것을 먼저 확인한 뒤 PR #3을 열었다(run `43144342647`, [raw/crewai-pr3-retention.log](raw/crewai-pr3-retention.log)).

| 시각(UTC) | 단계 | 결과 |
| --- | --- | --- |
| 02:53:01~02:54:16 | 그래프 생성(head `196e530`) | `codebase_hash=846aec8c348118be`, 91초 |
| 02:54:19 | 작업 스크립트 | 자기 소스 폴더 `crewAI-196e530…` 삭제 |
| 02:54:30 | 남길 그래프 | `c8a03dcf21488d21`(main `898f7e6`), `846aec8c348118be`(열린 PR #3 head) |
| 02:54:30 | `remove_cpg` | `a64d93d2b98745b7`(닫힌 PR #2) 삭제, 17.18MB |
| 02:54:32~36 | 남은 소스 폴더 | `crewAI-5014f84…`, `crewAI-848d15d…`, `crewAI-898f7e6…` 삭제(각 623MB) |

정리 뒤 Xeon 상태:
- CI 소스 폴더: 색인 파일 하나, 8.0K
- codebadger 그래프: `846aec8c…`, `c8a03dcf…`, `fafd8959…`(기준값), `a5b31c17…`(opensre 기준값)
- 색인: `c8a03dcf…`를 가리키는 SHA 2개(`848d15d`, `898f7e6`)와 `846aec8c…` 하나

### main 푸시에서의 정리 (PR #3 머지)

PR #3 머지 커밋 `3457928`에서 run `43144979879`가 돌았다([raw/crewai-main-push-retention.log](raw/crewai-main-push-retention.log)).

| 시각(UTC) | 단계 | 결과 |
| --- | --- | --- |
| 02:58:41 | `generate_cpg` | `codebase_hash=846aec8c348118be`, 바로 ready. 머지 커밋이 PR #3 head와 파일 내용이 같다 |
| 02:58:44 | 작업 스크립트 | 자기 소스 폴더 삭제 |
| 02:58:50 | 정리 단계 | 남길 그래프 `846aec8c…`(main `3457928`), `c8a03dcf…`(main `898f7e6`). 열린 PR 0개, 지운 그래프 없음 |

### 기준값 소스 폴더

2번 측정에 쓴 crewAI 기준 커밋 소스 `/opt/codebadger/playground/codebases/crewAI-71d68117`(623MB)은 사용자 결정으로 지웠다. CI 폴더 밖이라 정리 단계의 대상이 아니었다. 기준 그래프 `fafd8959bb1b7ee0`(`cpg.bin` 18,009,135 B)은 남겼다. 잠든 그래프는 `cpg.bin`에서 다시 올리므로 질의에는 소스가 필요 없다. 같은 그래프를 다시 만들려면 기준 커밋을 다시 풀어야 한다.

## 9. 재부팅 복원 확인

사용자가 Xeon을 재부팅했다(부팅 04:54:30 UTC). 이미지 묶음 `codebadger-images.tar`의 mtime은 04:42:46 UTC로, 재부팅 전에 다시 저장됐다. 05:00~05:04 UTC에 확인했다([raw/reboot-restore.log](raw/reboot-restore.log)).

### 유닛과 컨테이너

| 대상 | 결과 |
| --- | --- |
| librechat 러너 5개 | `librechat-ci-runner@1~5` active(running), 컨테이너 `librechat-ci-runner-1~5`가 04:57:20에 떴다. 다섯 컨테이너 ID가 모두 `connev-llm/librechat`에 `online`(라벨 `librechat-ci-wide`)으로 등록돼 있다 |
| codebadger 이미지 복원 | `codebadger-image-restore` 04:56:34~04:58:24. 이미지 4개를 묶음에서 올렸다 |
| codebadger 스택 | `codebadger-stack` 04:58:58 완료. joern-server, mcp, postgres(healthy), redis(healthy) 컨테이너가 떠 있다 |
| MCP 이미지 | `codebadger-mcp:latest` = `766f3227db26`([crewAI 기준값](../2026-11-12-crewai-baseline/README.md) 1절의 새 이미지). 컨테이너 안 `config.yaml`에 crewAI 제외 규칙 2줄이 있다 |
| joern 러너 이미지·네트워크·프록시 | `codeinside-joern-ci-net` 04:59:01 완료. 러너 이미지를 다시 만들었고(uid 994, gid 984) 네트워크 `codeinside-joern-ci`와 `codeinside-mcp-proxy`가 떴다 |
| joern 러너 | `codeinside-joern-runner` active(running), 대상 `Munsik-Park/crewAI`. 컨테이너 `77287098115d`가 `codeinside-joern-77287098115d`로 `online`(라벨 `joern`) |

- 복원 순서는 이미지 복원 → 스택 → joern 러너 네트워크·프록시 → supervisor였다.
- 재부팅 전 등록이 `offline`으로 남아 있다: crewAI에 `codeinside-joern-b2c5dc9d4cea` 하나, librechat에 `librechat-ci-wide` 5개. 재부팅으로 ephemeral 컨테이너가 작업 없이 사라져 supervisor가 지우지 못한 등록이다. 작업 배정에는 영향이 없고, 지우지 않았다.
- librechat에 `online`인 `librechat-ci-fast` 등록 3개는 Xeon 컨테이너가 아니다. Xeon supervisor의 추가 라벨은 `librechat-ci-wide`다.
- 실패 유닛은 `systemd-networkd-wait-online.service` 하나다. 직전 부팅(07-20~11-12)에서도 같은 메시지로 실패했고, 위 유닛들은 모두 떴다.
- `codeinside-joern-runner.service`의 Description은 아직 `Munsik-Park/opensre`다(레포의 [config/joern-ci/systemd/codeinside-joern-runner.service](../../../config/joern-ci/systemd/codeinside-joern-runner.service) 1행 주석과 Description). 실제 대상은 `runner.conf`의 `JOERN_CI_REPO=Munsik-Park/crewAI`이고 supervisor 로그도 crewAI를 가리킨다.

### 기준 그래프 Q1

작업자 쪽에서 SSH 터널(로컬 14242 → Xeon 루프백 4242)로 crewAI 기준 그래프 `fafd8959bb1b7ee0`에 물었다. 질의는 [config/queries/crewai.json](../../../config/queries/crewai.json)의 Q1이고, 래퍼는 [raw/worker-resolve-q1.log](raw/worker-resolve-q1.log)와 같다.

| 시각(UTC) | 결과 |
| --- | --- |
| 05:01:48 | `get_cpg_status` → `loading`. codebadger 메타데이터와 `cpg.bin`이 재부팅 뒤에도 남아 있어, 이 호출로 잠든 그래프의 적재가 시작됐다 |
| 05:02:50 | ready(첫 호출부터 약 62초) |
| 05:02:52 | Q1 29건(Joern 안 19.95ms, 왕복 0.23초). 앞 세 항목도 6절 결과와 같다 |
| 05:03:08 | 그래프 규모(작업 스크립트의 STATS 질의): 파일 984, 메서드 36,950, 호출 254,956, overlay 6개. 기준값과 같다 |

- Q1 Joern 시간이 6절(0.36ms)보다 긴 것은 적재 직후 첫 질의라서로 보이지만, 나눠 재지 않았다.

## 확인 안 됨

- opensre Actions가 막힌 정확한 원인(GitHub 쪽 조치)
- 정리 단계에서 실패한 그래프(`state: failure`)를 지우는 경로. 이번 시험에는 실패한 그래프가 없었다
- main first-parent 20개를 넘는 푸시가 쌓였을 때의 동작(지금은 main 그래프가 하나다)
- 재부팅 뒤 joern 러너가 실제 작업을 받는지. 등록이 `online`인 것까지만 봤고 워크플로 run은 돌리지 않았다. 재부팅 뒤 프록시의 닿는 곳·막힌 곳(5절)도 다시 재지 않았다
- 재부팅 뒤 CI 그래프(`846aec8c…`, `c8a03dcf…`)의 상태. 상태 조회가 적재를 시작시켜 묻지 않았다
- 러너 컨테이너가 외부 네트워크로 나가는 범위. librechat 러너와 달리 egress 허용 목록을 걸지 않았다

## 원본 파일

| 파일 | 내용 |
| --- | --- |
| `raw/opensre-workflows-{before,after}.tsv` | opensre 워크플로 상태 |
| `raw/opensre-fork-pr-approval.log` | opensre fork PR 승인 정책 변경 |
| `raw/crewai-fork-setup.log` | crewAI 포크 직후 상태, 워크플로 목록, 이동 기록 |
| `raw/probe-network.log` | 러너·프록시 컨테이너 설정과 닿는 곳·막힌 곳 |
| `raw/pretest-job-dry-run.log` | 작업 스크립트 사전 시험 |
| `raw/crewai-pr1-run.log`, `raw/crewai-pr1-codebadger.log` | crewAI PR #1 첫 run(적재 실패) 작업 로그와 codebadger 로그 |
| `raw/crewai-pr1-run2.log` | crewAI PR #1 두 번째 run(끝내는 기준) 작업 로그와 커밋 상태 |
| `raw/worker-resolve-q1.log` | 작업자 쪽 resolver 결과와 SSH 터널로 물은 Q1 |
| `raw/crewai-pr2-run.log`, `raw/ancestor-fallback.log` | 시험 PR #2 run과 그동안의 resolver 결과 |
| `raw/crewai-main-push-run.log` | main 푸시 run 작업 로그와 커밋 상태 |
| `raw/crewai-pr3-retention.log` | PR #3 run의 작업·정리 단계 출력과 정리 뒤 Xeon 상태 |
| `raw/crewai-main-push-retention.log` | PR #3 머지 뒤 main 푸시 run의 작업·정리 단계 출력과 정리 뒤 Xeon 상태 |
| `raw/reboot-restore.log` | 재부팅 뒤 유닛·컨테이너·이미지 상태, 부팅 로그, 러너 등록, 기준 그래프 Q1 |
| `scripts/probe-network.sh` | 위 확인에 쓴 스크립트 |
