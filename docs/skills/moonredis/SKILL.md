---
name: moonredis
description: "Talk to Redis from MoonBit with moonbitstack/moonredis: RESP2 and RESP3, one async method per command named as in redis-py, pipelines and MULTI/EXEC with WATCH, pub/sub including sharded, client-side caching, connection pool and retries, TLS and ACL auth, cluster routing with MOVED/ASK, sentinel discovery, the Redis 8 modules (JSON, search and vectors, time series, Bloom, cuckoo, count-min, top-k, t-digest), and moonsd service discovery on Redis. Use when code caches, counts, queues, publishes or looks up services through Redis or Valkey."
---

# moonredis

```bash
moon add moonbitstack/moonredis
```

```moonbit
// moon.pkg
import {
  "moonbitstack/moonredis",        // Client, Pipeline, cluster and sentinel routing
  "moonbitstack/moonredis/socket", // the TCP and TLS transport, native and wasm
  "moonbitstack/moonredis/resp",   // the codec, for FakeConn replies
}
```

## Connect and run commands

```mbt native
async fn count_visit() -> Int64 raise @moonredis.RedisError {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379).with_auth(
    Some("app"),
    Some("secret"),
  )
  let client = @moonredis.Client::new(@socket.Connection::connect(options))
  client.incr("visits")
}
```

`Connection::connect` sends `HELLO` (RESP3 unless `protocol=Resp2`), `AUTH` and `SELECT` for you. Commands that collide with MoonBit keywords are `type_` and `move_`.

## Test without a server

```moonbit
async test "counts visits" {
  let fake = @moonredis.FakeConn::new([@resp.Integer(1L)])
  let client = @moonredis.Client::new(fake)
  assert_eq(client.incr("visits"), 1L)
  assert_eq(fake.sent().length(), 1)
}
```

`FakeConn::new` answers from a list; `FakeConn::handler` answers each command from a function. `sent()` is what the client wrote.

## One round trip

```moonbit
async fn transfer(conn : &@moonredis.RedisConn) -> Unit raise @moonredis.RedisError {
  let pipeline = @moonredis.Pipeline::new(conn)
  pipeline.multi()
  pipeline.add([b"DECRBY", b"alice", b"10"])
  pipeline.add([b"INCRBY", b"bob", b"10"])
  ignore(pipeline.execute())
}
```

Without `multi()` the commands are only batched, and one error reply is one entry among the others. With `WATCH` first, a key changed under you makes `execute` raise `Aborted` and nothing runs.

## Things that catch people out

- Replies come back as `Bytes`; decode with `@utf8.decode_lossy` when you know the value is text.
- `RetryConn` and `connect_retrying` send a command again after a transport failure: use them only for commands that are safe to repeat. An error reply from Redis is never retried.
- `ClusterClient` follows `MOVED` and `ASK` up to `redirect_limit` (3). Multi-key commands need their keys in one slot; `{hash tags}` put them there and `same_slot` checks.
- `moonredis/sd` gives each registry its own lock: hand it a client nothing else uses.
- The socket transport and `sd` build on native and wasm; the codec and the command surface build everywhere.
