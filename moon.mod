name = "moonbitstack/moonredis"

version = "0.1.1"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonredis"

license = "Apache-2.0"

keywords = [ "redis", "resp", "client", "moonbit" ]

description = "A Redis client for MoonBit: RESP2 and RESP3, pipelines, transactions, pub/sub, cluster and sentinel."

source = "src"

import {
  "moonbitstack/moonsd@0.1.0",
  "moonbitstack/moonnet@0.1.8",
  "moonbitstack/moontls@0.9.11",
  "moonbitlang/async@0.22.5",
}
