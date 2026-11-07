name = "moonbitstack/moonredis"

version = "0.1.5"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonredis"

license = "Apache-2.0"

keywords = [
  "redis",
  "client",
  "resp",
  "resp2",
  "resp3",
  "pipeline",
  "transaction",
  "pubsub",
  "pub-sub",
  "cluster",
  "redis-cluster",
  "sentinel",
  "cache",
  "key-value",
  "service-discovery",
  "json",
  "jsonpath",
  "redisjson",
  "redisearch",
  "full-text-search",
  "vector-search",
  "knn",
  "timeseries",
  "bloom-filter",
  "cuckoo-filter",
  "count-min-sketch",
  "top-k",
  "t-digest",
  "moonbit",
]

description = "A Redis client for MoonBit: RESP2 and RESP3, pipelines, transactions, pub/sub, cluster and sentinel."

source = "src"

import {
  "moonbitstack/moonsd@0.1.1",
  "moonbitstack/moonnet@0.1.11",
  "moonbitstack/moontls@0.9.15",
  "moonbitlang/async@0.22.5",
}
