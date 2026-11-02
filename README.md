# moonredis

A Redis client for MoonBit. It speaks RESP2 and RESP3, covers the command families, and
carries the pieces a real deployment needs: a connection pool, retries, TLS, ACL auth,
pipelines, transactions, pub/sub (including sharded), client-side caching, cluster routing
and sentinel discovery. The protocol and command surface build on every backend; the socket
transport runs on native and wasm.

## Install

```bash
moon add moonbitstack/moonredis
```

`moon.mod` gains `moonbitstack/moonredis`. The protocol codec is the `moonredis/resp`
package; the client, its command surface and the routing pieces are the root `moonredis`
package; the socket transport is `moonredis/socket`.

## Quick start

```moonbit
async fn main {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let conn = @socket.Connection::connect(options) catch {
    _ => return
  }
  let client = @moonredis.Client::new(conn)
  let _ = client.set("greeting", "hello")
  match client.get("greeting") {
    Some(bytes) => println(@utf8.decode_lossy(bytes[:]))
    None => println("(nil)")
  }
}
```

`Connection::connect` dials, negotiates the protocol with `HELLO`, authenticates with
`AUTH` when credentials are set, `SELECT`s the database, and turns on `CLIENT TRACKING` when
asked. A `Client` wraps any `RedisConn`; `FakeConn` is an in-memory one for tests.

## Interface

### Client and connection

| Item | Purpose |
|:--|:--|
| `Client` | The command surface: one async method per redis command, named as in redis-py. |
| `Client::new(&RedisConn)` | A client over a connection. |
| `Client::command(Array[Bytes])` | Send a raw command (binary-safe), returning the reply value. |
| `RedisConn` (open trait) | The transport contract: `execute(Array[Bytes]) -> RespValue`, and `execute_all` for several commands in one round trip, which defaults to sending them one at a time. |
| `FakeConn` | A scripted in-memory connection for tests (`new`, `handler`). |
| `RedisError` | `Reply(msg)` for a redis error, `Connection(msg)`, `Closed`, `Protocol(msg)`, and `Aborted` for a transaction a watched key changed under. |

### Configuration

| Item | Purpose |
|:--|:--|
| `ClientOptions` | Endpoint, credentials, protocol, timeouts, and the pool/retry/tracking policies. |
| `ClientOptions::at(host, port)` | Options at an address over the standard defaults. |
| `ClientOptions::with_auth(user?, password?)`, `with_db(db)` | Copies with auth or database set. |
| `client_default`, `pool_default`, `retry_default`, `tracking_default` | The market-standard presets. |
| `Protocol` | `Resp2` or `Resp3` (the default). |
| `PoolOptions` | `max_idle`, `max_active`, `min_idle`, `idle_timeout`, `health_check`. |
| `RetryOptions` | `attempts`, `base_delay`, `max_delay`, `level`, `jitter`. |
| `TrackingOptions` | `enabled`, `bcast`, `optin`, `optout`, `noloop`, `redirect`. |
| `backoff_delay(attempt, retry)` | The wait before a retry. |

### Batching and routing

| Item | Purpose |
|:--|:--|
| `Pipeline` | Queue commands (`add`) and send them in one round trip (`execute`); `multi` wraps them in `MULTI`/`EXEC`. |
| `Client::watch`, `Client::unwatch`, `Client::discard` | Transaction control. |
| `ClusterTopology` | A slot-to-node map; `node_for_slot(slot)`. |
| `ClusterSlot`, `ClusterSlot::new` | A slot range owned by a node. |
| `ClusterClient` | Routes a command to the node owning its key and follows `MOVED` and `ASK`, up to `limit` (`redirect_limit`, 3). `dial` opens nodes it was not built with. |
| `Redirect`, `redirect(msg)` | `Moved` or `Ask` with the slot and node, read from an error reply. |
| `ClusterTopology::assign(slot, node)` | Record where a slot lives. |
| `crc16(bytes)`, `hash_slot(key)`, `same_slot(keys)` | Slot hashing, honouring `{hash tags}`. |
| `decode_cluster_slots(reply)` | Parse a `CLUSTER SLOTS` reply into a `ClusterTopology`. |
| `SentinelClient` | Resolve a master address through a list of sentinels. |
| `RetryConn`, `should_retry(error, attempt, retry)` | A retrying view of any connection; `dial` opens a new one after a failure and `wait` sleeps for the backoff. |

### Pub/sub and values

| Item | Purpose |
|:--|:--|
| `Message` | A pub/sub frame: `kind`, `channel`, `payload`, `pattern`, `count`. |
| `Message::parse(value)` | Parse a RESP2 array or RESP3 push frame into a `Message`. |
| `StreamEntry` | One stream entry: `id` and `fields`. |
| `PendingSummary` | The `XPENDING` summary: `count`, `min_id`, `max_id`, `consumers`. |

### Socket transport (`moonredis/socket`, native and wasm)

| Item | Purpose |
|:--|:--|
| `Connection` | A real connection over TCP or TLS; implements `RedisConn`. |
| `Connection::connect(options)` | Dial and negotiate from `ClientOptions`. |
| `Connection::take_pushes()` | Push frames read since the last command, such as the invalidations `CLIENT TRACKING` sends. |
| `connect_retrying(options)` | A `RetryConn` that reconnects under `options.retry`. Only for commands that are safe to send twice. |
| `Pool` | Reuse idle connections (`get`, `put`, `idle_count`), bounded by `max_idle`. |
| `Subscription` | `subscribe`/`unsubscribe` and `next` for `Message` frames; `pattern` and `shard` select `PSUBSCRIBE` and `SSUBSCRIBE`. |

### Codec (`moonredis/resp`)

| Item | Purpose |
|:--|:--|
| `RespValue` | Every RESP2/RESP3 value: simple string, error, integer, bulk string, null, array, boolean, double, big number, bulk error, verbatim string, map, set, push. |
| `RespValue::decode(bytes)`, `encode()` | Decode one value (or encode it back). |
| `RespReader` | Stream a sequence of values (`read`, `at_end`, `rest`). |
| `resp_encode_command(args)`, `resp_command(args)` | Frame a command as an array of bulk strings. |
| `resp_kind(value)` | A value's type name, for diagnostics. |

The command methods also expose the small builders and decoders they use — `arg_string`,
`arg_int`, `arg_int64`, `arg_double`, `arg_bytes`, `push_some`; `expect_int64`,
`expect_bool`, `expect_bytes`, `expect_string`, `expect_string_value`, `expect_array`,
`expect_double`, `expect_map`; `status_ok` — so a caller can compose a command or decode a
reply by hand.

## Commands

One async method per command, named as in redis-py. Two helpers where MoonBit needs a name
that redis uses as a keyword: `type_` for `TYPE` and `move_` for `MOVE`.

| Family | Methods |
|:--|:--|
| String | `set`, `set_get`, `setnx`, `setex`, `psetex`, `get`, `mget`, `mset`, `append`, `strlen`, `incr`, `incrby`, `decr`, `decrby`, `getrange`, `setrange`, `getdel`, `getex` |
| Key | `del`, `unlink`, `exists`, `expire`, `pexpire`, `expireat`, `pexpireat`, `persist`, `ttl`, `pttl`, `type_`, `rename`, `renamenx`, `randomkey`, `touch`, `move_`, `copy`, `keys`, `scan`, `object_encoding`, `object_refcount`, `object_idletime`, `dump`, `restore` |
| Hash | `hset`, `hsetnx`, `hmset`, `hget`, `hmget`, `hgetall`, `hdel`, `hexists`, `hlen`, `hstrlen`, `hincrby`, `hincrbyfloat`, `hkeys`, `hvals`, `hscan`, `hrandfield` |
| List | `lpush`, `rpush`, `lpushx`, `rpushx`, `lpop`, `lpopn`, `rpop`, `rpopn`, `llen`, `lindex`, `lrange`, `lset`, `lrem`, `linsert`, `ltrim`, `rpoplpush`, `lmove`, `blpop`, `brpop`, `brpoplpush`, `blmove` |
| Set | `sadd`, `srem`, `smembers`, `sismember`, `scard`, `spop`, `spopn`, `srandmember`, `srandmembern`, `sinter`, `sunion`, `sdiff`, `sinterstore`, `sunionstore`, `sdiffstore`, `smove`, `sscan` |
| Sorted set | `zadd`, `zrem`, `zscore`, `zmscore`, `zincrby`, `zcard`, `zrank`, `zrevrank`, `zrange`, `zrange_scores`, `zrevrange`, `zrevrange_scores`, `zrangebyscore`, `zrangebyscore_scores`, `zrevrangebyscore`, `zrevrangebyscore_scores`, `zcount`, `zremrangebyrank`, `zremrangebyscore`, `zpopmin`, `zpopmax`, `zunionstore`, `zinterstore`, `zscan`, `zrandmember`, `bzpopmin`, `bzpopmax` |
| Stream | `xadd`, `xlen`, `xdel`, `xtrim`, `xrange`, `xrevrange`, `xread`, `xack`, `xgroup_create`, `xgroup_destroy`, `xgroup_createconsumer`, `xgroup_delconsumer`, `xreadgroup`, `xpending` |
| HyperLogLog | `pfadd`, `pfcount`, `pfmerge` |
| Geo | `geoadd`, `geodist`, `geohash`, `geopos`, `geosearch` |
| Bitmap | `setbit`, `getbit`, `bitcount`, `bitpos`, `bitop` |
| Script / function | `Script` runs a script by digest and reloads it when the server forgets; `eval`, `evalsha`, `script_load`, `script_exists`, `script_flush`, `function_load`, `function_call`, `function_flush`, `function_delete` |
| Pub/sub | `publish`, `spublish`, `subscribe`, `unsubscribe`, `psubscribe`, `punsubscribe`, `ssubscribe`, `sunsubscribe` |
| Server / connection | `ping`, `ping_message`, `echo`, `select`, `auth`, `auth_user`, `info`, `dbsize`, `flushdb`, `flushall`, `swapdb`, `time_`, `lastsave`, `save`, `bgsave`, `bgrewriteaof`, `shutdown`, `config_get`, `config_set`, `config_rewrite`, `config_resetstat`, `client_setname`, `client_getname`, `client_id`, `client_kill`, `command_count`, `slowlog_get`, `slowlog_len`, `slowlog_reset`, `replicaof`, `replicaof_noone` |

## Pipelines and transactions

```moonbit
let pipeline = @moonredis.Pipeline::new(conn)
pipeline.add([b"SET", b"a", b"1"])
pipeline.add([b"INCR", b"a"])
let replies = pipeline.execute()   // [OK, 2]
```

Call `pipeline.multi()` before `execute` to wrap the queued commands in `MULTI`/`EXEC`, so
redis runs them atomically. `Client::watch`/`unwatch`/`discard` are available for optimistic
locking around a transaction: when a watched key changes first, `execute` raises `Aborted` and
nothing ran. An error reply inside a plain pipeline is one reply among the others.

## Pub/sub

```moonbit
let sub = @socket.Subscription::subscribe(conn, ["news"])
let _ = publisher.publish("news", "hello")
match sub.next() {
  Some(message) => println(message.channel + ": " + @utf8.decode_lossy(message.payload[:]))
  None => ()
}
```

`ssubscribe`/`spublish` are the sharded forms, routed to one cluster shard.

## Cluster and sentinel

`ClusterClient` routes each command to the node owning the key's slot (from
`hash_slot`/`crc16`, honouring `{hash tags}`) and follows a `MOVED`/`ASK` redirect once.
`ClusterTopology` comes from `decode_cluster_slots`, and `same_slot` checks that a multi-key
command's keys colocate. `SentinelClient` resolves a master address by asking sentinels in
turn.

## Service discovery

`moonredis/sd` implements the `moonsd` contract on Redis. An endpoint is a key that expires, so an instance that stops renewing leaves by itself. Redis reports expiry only on a best-effort channel, so a watcher reads the service again every `poll` milliseconds.

```moonbit
let registry = @sd.Registry::new(client)
group.spawn_bg(() => @moonsd.hold(registry, "greeter", @moonsd.Endpoint::new("10.0.0.1", 12000)))
let endpoints = registry.resolve("greeter")
```

`Registry::new` takes `prefix`, default `moonsd`, and `poll`, default 1000. Any number of tasks may share one registry. Give it a client of its own: its lock orders its own commands, not those of anything else on that connection. A service's keys share a hash tag, so they stay in one cluster slot.

## Pool and retries

`@socket.Pool` reuses idle connections up to `PoolOptions.max_idle`. `RetryConn` retries a
transport failure up to `RetryOptions.attempts`, while a redis error reply surfaces
immediately; `backoff_delay`/`should_retry` expose the policy.

## Examples

| Example | Run |
|:--|:--|
| `01-resp` | `moon run src/examples/01-resp` — the codec, no server. |
| `02-commands` | `moon run src/examples/02-commands` — typed commands against a fake. |
| `03-connect` | `moon run src/examples/03-connect --target native` — a real connection. |
| `04-pipeline` | `moon run src/examples/04-pipeline --target native` — one round trip, and a transaction that loses a race. |
| `05-pubsub` | `moon run src/examples/05-pubsub --target native` — a pattern subscription. |
| `06-cluster` | `moon run src/examples/06-cluster --target native` — keys routed by slot. |

## Testing

The codec and command surface are tested against `FakeConn` with no network, so they run on
every backend. `src/integration` runs every command family against a real server under both
protocols, and covers transactions losing a race, redirects, a slot migrating, a failover and
a connection killed underneath. `scripts/start_redis.sh` starts what those tests connect to: a
standalone redis, a six-node cluster, and a master and replica under a sentinel. Without
servers the tests return early; with `MOONREDIS_LIVE` set, as in CI, a missing server fails
them.

## Licence

Apache-2.0.
