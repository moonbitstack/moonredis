#!/usr/bin/env bash
# The servers the integration tests connect to: a standalone redis on 6379, a six-node cluster
# on 7000-7005, and a master with a replica on 6390 and 6391 under a sentinel on 26379.
#
# Redis 8 carries the JSON, search, time series and probabilistic modules in the server
# itself, so the official `redis:8` image serves every one of them. The script runs the image
# when docker is there, and the local `redis-server` otherwise, so the topology is the same
# either way.
set -euo pipefail

container=moonredis-servers
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

if command -v docker >/dev/null 2>&1; then
  docker rm -f "$container" >/dev/null 2>&1 || true
  # One container with the host network: the cluster and the sentinel announce
  # `127.0.0.1:<port>`, which is exactly where the tests dial.
  docker run -d --name "$container" --network host --entrypoint sleep redis:8 infinity >/dev/null

  # `$1` is the port, the rest are the server's own arguments. The image's entrypoint is
  # what adds `--loadmodule` for the four modules it ships, so every server goes through it.
  start() {
    docker exec "$container" sh -c "mkdir -p /data/$1 && chown -R redis:redis /data/$1"
    docker exec -d "$container" /usr/local/bin/docker-entrypoint.sh redis-server \
      --port "$1" --dir "/data/$1" --save "" --appendonly no "${@:2}"
  }
  cli() {
    docker exec "$container" redis-cli "$@"
  }
else
  start() {
    mkdir -p "$dir/$1"
    redis-server --port "$1" --daemonize yes --dir "$dir/$1" --save "" --appendonly no "${@:2}"
  }
  cli() {
    redis-cli "$@"
  }
fi

start 6379
await "cli -p 6379 ping" 40

ports=(7000 7001 7002 7003 7004 7005)
for port in "${ports[@]}"; do
  start "$port" --cluster-enabled yes --cluster-config-file "nodes.conf" --cluster-node-timeout 2000
  await "cli -p $port ping" 40
done
cli --cluster create "${ports[@]/#/127.0.0.1:}" --cluster-replicas 1 --cluster-yes
for port in "${ports[@]}"; do
  await "cli -p $port cluster info | grep -q cluster_state:ok" 120
done

start 6390
await "cli -p 6390 ping" 40
start 6391 --replicaof 127.0.0.1 6390
await "cli -p 6391 info replication | grep -q master_link_status:up" 120

if command -v docker >/dev/null 2>&1; then
  docker exec "$container" sh -c "mkdir -p /data/sentinel && chown -R redis:redis /data/sentinel"
  docker exec "$container" sh -c "cat > /data/sentinel/sentinel.conf <<EOF
port 26379
dir /data/sentinel
sentinel monitor mymaster 127.0.0.1 6390 1
sentinel down-after-milliseconds mymaster 1000
sentinel failover-timeout mymaster 3000
EOF"
  docker exec -d "$container" /usr/local/bin/docker-entrypoint.sh redis-server \
    /data/sentinel/sentinel.conf --sentinel
else
  mkdir -p "$dir/sentinel"
  cat >"$dir/sentinel/sentinel.conf" <<EOF
port 26379
dir $dir/sentinel
sentinel monitor mymaster 127.0.0.1 6390 1
sentinel down-after-milliseconds mymaster 1000
sentinel failover-timeout mymaster 3000
EOF
  redis-server "$dir/sentinel/sentinel.conf" --sentinel --daemonize yes
fi
await "cli -p 26379 sentinel get-master-addr-by-name mymaster | grep -q 6390" 40

echo "redis topology is up"
