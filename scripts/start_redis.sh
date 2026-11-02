#!/usr/bin/env bash
# The servers the integration tests connect to: a standalone redis on 6379, a six-node cluster
# on 7000-7005, and a master with a replica on 6390 and 6391 under a sentinel on 26379.
set -euo pipefail

dir=$(mktemp -d)

# Wait until `$1` holds, or fail after `$2` tries: the next step needs the server settled, and
# a topology that never came up has to stop the job here.
await() {
  for _ in $(seq 1 "$2"); do
    if eval "$1" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "timed out waiting for: $1" >&2
  return 1
}

start() {
  mkdir -p "$dir/$1"
  redis-server --port "$1" --daemonize yes --dir "$dir/$1" --save "" --appendonly no "${@:2}"
}

start 6379
await "redis-cli -p 6379 ping" 40

ports=(7000 7001 7002 7003 7004 7005)
for port in "${ports[@]}"; do
  start "$port" --cluster-enabled yes --cluster-config-file nodes.conf --cluster-node-timeout 2000
  await "redis-cli -p $port ping" 40
done
redis-cli --cluster create "${ports[@]/#/127.0.0.1:}" --cluster-replicas 1 --cluster-yes
for port in "${ports[@]}"; do
  await "redis-cli -p $port cluster info | grep -q cluster_state:ok" 120
done

start 6390
await "redis-cli -p 6390 ping" 40
start 6391 --replicaof 127.0.0.1 6390
await "redis-cli -p 6391 info replication | grep -q master_link_status:up" 120

mkdir -p "$dir/sentinel"
cat >"$dir/sentinel/sentinel.conf" <<EOF
port 26379
dir $dir/sentinel
sentinel monitor mymaster 127.0.0.1 6390 1
sentinel down-after-milliseconds mymaster 1000
sentinel failover-timeout mymaster 3000
EOF
redis-server "$dir/sentinel/sentinel.conf" --sentinel --daemonize yes
await "redis-cli -p 26379 sentinel get-master-addr-by-name mymaster | grep -q 6390" 40

echo "redis topology is up"
