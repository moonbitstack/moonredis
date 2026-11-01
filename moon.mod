name = "moonbitstack/moonredis"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonredis"

license = "Apache-2.0"

keywords = [ "redis", "resp", "client", "moonbit" ]

description = "A Redis client for MoonBit: RESP2 and RESP3, pipelines, transactions, pub/sub, cluster and sentinel."

source = "src"

import {
  "moonbitstack/moonnet@0.1.7",
  "moonbitstack/moontls@0.9.7",
  "moonbitlang/async@0.22.5",
}
