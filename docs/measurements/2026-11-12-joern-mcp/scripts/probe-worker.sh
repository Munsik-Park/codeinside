#!/usr/bin/env bash
# docs/plan.md 단계 5: codebadger 질의 워커와 그래프 생성 컨테이너에 NUMA 고정과 메모리 상한이 실제로 걸렸는지 본다.
# 실행: Xeon에서 docker 그룹 계정으로. 127.0.0.1과 0.0.0.0 밖의 IP는 <IP>로 바꾼다.
set -euo pipefail
mask() { sed -E -e 's/\b127\.0\.0\.1\b/LOOPBACK4/g' -e 's/\b0\.0\.0\.0\b/ANY4/g' \
  -e 's/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/<IP>/g' -e 's/LOOPBACK4/127.0.0.1/g' -e 's/ANY4/0.0.0.0/g'; }
cg() { echo "/sys/fs/cgroup/system.slice/docker-$(docker inspect "$1" --format '{{.Id}}').scope"; }
for c in $(docker ps --filter label=codebadger.role=joern-worker --format '{{.Names}}') codebadger-joern-server; do
  echo "== $c"
  docker inspect "$c" --format 'image={{.Config.Image}} cpuset_cpus={{.HostConfig.CpusetCpus}} cpuset_mems={{.HostConfig.CpusetMems}} memory={{.HostConfig.Memory}} networks={{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
  echo "published host bind addresses: $(docker inspect "$c" --format '{{range $k,$v := .HostConfig.PortBindings}}{{range $v}}{{.HostIp}} {{end}}{{end}}' | tr ' ' '\n' | sort | uniq -c | tr '\n' ' ')"
  echo "published port count: $(docker inspect "$c" --format '{{len .HostConfig.PortBindings}}')"
  p="$(cg "$c")"
  for f in cpuset.cpus.effective cpuset.mems.effective memory.max memory.peak; do echo "cgroup $f=$(cat "$p/$f")"; done
  docker exec "$c" sh -c 'echo "JOERN_VERSION=$JOERN_VERSION"; grep -E "Cpus_allowed_list|Mems_allowed_list" /proc/1/status'
  for pid in $(docker exec "$c" jps -q 2>/dev/null); do
    cmd="$(docker exec "$c" jcmd "$pid" VM.command_line 2>/dev/null | grep -E '^java_command' || true)"
    [[ "$cmd" == *Jps* || -z "$cmd" ]] && continue
    echo "jvm pid=$pid $cmd"
    docker exec "$c" jcmd "$pid" VM.flags | tr ' ' '\n' | grep -E 'MaxHeapSize|InitialHeapSize'
    docker exec "$c" jcmd "$pid" VM.command_line | grep -E '^jvm_args' | cut -c1-160
    docker exec "$c" sh -c "grep -E 'Cpus_allowed_list|Mems_allowed_list' /proc/$pid/status" || true
  done
done 2>&1 | mask
echo "== host listening sockets for codebadger ports"
ss -ltnH | awk '{print $4}' | grep -E ':(4242|55432|56379|8080|1[34][0-9]{3})$' | sed -E 's/:[0-9]+$//' | sort | uniq -c | mask
echo "== worker containers: listening sockets inside (joern --server)"
for c in $(docker ps --filter label=codebadger.role=joern-worker --format '{{.Names}}'); do
  docker exec "$c" sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null' | awk '$4=="0A"{print $2}' | sort -u | sed "s/^/$c listen(hex) /"
done
echo "== containers on network codebadger"
docker network inspect codebadger --format '{{range .Containers}}{{.Name}} {{end}}'
