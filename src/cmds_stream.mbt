// The stream commands, named as in redis-py. A stream is an append-only log of entries,
// each an auto-id and a set of fields; these expose appending, ranging and consumer-group
// reads.

///|
/// One stream entry: its id and its field/value pairs.
pub struct StreamEntry {
  /// The entry id (`<ms-seq>`), as redis assigned or the caller supplied.
  id : String
  /// The entry's fields and values.
  fields : Array[(String, String)]
}

///|
/// The summary `XPENDING` returns for a group: how many pending, the first and last
/// pending ids, and per-consumer pending counts.
pub struct PendingSummary {
  count : Int64
  /// The oldest pending id; `None` when nothing is pending.
  min_id : String?
  /// The newest pending id; `None` when nothing is pending.
  max_id : String?
  consumers : Array[(String, Int64)]
}

///|
/// `XADD key [MAXLEN [~] n] id field value...`: append an entry, returning its id. Use
/// `id` of `*` for an auto-generated id.
pub async fn Client::xadd(
  self : Client,
  key : String,
  id : String,
  fields : Array[(String, String)],
  maxlen? : Int64,
  approx? : Bool,
) -> String raise RedisError {
  let args : Array[Bytes] = [b"XADD", arg_string(key)]
  match maxlen {
    Some(n) => {
      args.push(b"MAXLEN")
      if approx.unwrap_or(true) {
        args.push(b"~")
      }
      args.push(arg_int64(n))
    }
    None => ()
  }
  args.push(arg_string(id))
  for (f, v) in fields {
    args.push(arg_string(f))
    args.push(arg_string(v))
  }
  expect_string_value(self.command(args))
}

///|
/// `XLEN key`: the number of entries in the stream.
pub async fn Client::xlen(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"XLEN", arg_string(key)]))
}

///|
/// `XDEL key id...`: delete the given entries, returning how many were removed.
pub async fn Client::xdel(
  self : Client,
  key : String,
  ids : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"XDEL", arg_string(key)]
  for i in ids {
    args.push(arg_string(i))
  }
  expect_int64(self.command(args))
}

///|
/// `XTRIM key MAXLEN [~] n`: cap the stream at `n` entries, returning how many were
/// trimmed.
pub async fn Client::xtrim(
  self : Client,
  key : String,
  maxlen : Int64,
  approx? : Bool,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"XTRIM", arg_string(key), b"MAXLEN"]
  if approx.unwrap_or(true) {
    args.push(b"~")
  }
  args.push(arg_int64(maxlen))
  expect_int64(self.command(args))
}

///|
/// `XRANGE key start end [COUNT n]`: the entries from `start` to `end` (use `-`/`+` for
/// the ends), oldest first.
pub async fn Client::xrange(
  self : Client,
  key : String,
  start : String,
  end : String,
  count? : Int32,
) -> Array[StreamEntry] raise RedisError {
  let args : Array[Bytes] = [
    b"XRANGE",
    arg_string(key),
    arg_string(start),
    arg_string(end),
  ]
  push_some(args, b"COUNT", count.map(arg_int))
  decode_entries(self.command(args))
}

///|
/// `XREVRANGE key end start [COUNT n]`: the entries from `end` to `start`, newest first.
pub async fn Client::xrevrange(
  self : Client,
  key : String,
  end : String,
  start : String,
  count? : Int32,
) -> Array[StreamEntry] raise RedisError {
  let args : Array[Bytes] = [
    b"XREVRANGE",
    arg_string(key),
    arg_string(end),
    arg_string(start),
  ]
  push_some(args, b"COUNT", count.map(arg_int))
  decode_entries(self.command(args))
}

///|
/// `XREAD [COUNT n] [BLOCK ms] STREAMS key id...`: read new entries from one or more
/// streams. `block` of 0 reads without blocking; a positive `block` waits up to that many
/// milliseconds for the first entry. Returns, per stream, its name and the entries read,
/// or `None` when a blocking read times out.
pub async fn Client::xread(
  self : Client,
  streams : Array[(String, String)],
  count? : Int32,
  block? : Int64,
) -> Array[(String, Array[StreamEntry])]? raise RedisError {
  let args : Array[Bytes] = [b"XREAD"]
  push_some(args, b"COUNT", count.map(arg_int))
  push_some(args, b"BLOCK", block.map(arg_int64))
  args.push(b"STREAMS")
  for (k, _) in streams {
    args.push(arg_string(k))
  }
  for (_, i) in streams {
    args.push(arg_string(i))
  }
  decode_streams(self.command(args))
}

///|
/// `XACK key group id...`: acknowledge the given entries for a consumer group, returning
/// how many were newly acknowledged.
pub async fn Client::xack(
  self : Client,
  key : String,
  group : String,
  ids : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"XACK", arg_string(key), arg_string(group)]
  for i in ids {
    args.push(arg_string(i))
  }
  expect_int64(self.command(args))
}

///|
/// `XGROUP CREATE key group id [MKSTREAM]`: create a consumer group. `id` is the last
/// delivered id (`$` for new entries only, `0` for all); `mkstream` creates the stream if
/// absent.
pub async fn Client::xgroup_create(
  self : Client,
  key : String,
  group : String,
  id : String,
  mkstream? : Bool,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [
    b"XGROUP",
    b"CREATE",
    arg_string(key),
    arg_string(group),
    arg_string(id),
  ]
  if mkstream.unwrap_or(false) {
    args.push(b"MKSTREAM")
  }
  status_ok(self.command(args))
}

///|
/// `XGROUP DESTROY key group`: delete a consumer group. `true` if it existed.
pub async fn Client::xgroup_destroy(
  self : Client,
  key : String,
  group : String,
) -> Bool raise RedisError {
  expect_bool(
    self.command([b"XGROUP", b"DESTROY", arg_string(key), arg_string(group)]),
  )
}

///|
/// `XGROUP CREATECONSUMER key group consumer`: create a consumer in a group. `true` if
/// newly created.
pub async fn Client::xgroup_createconsumer(
  self : Client,
  key : String,
  group : String,
  consumer : String,
) -> Bool raise RedisError {
  expect_bool(
    self.command([
      b"XGROUP",
      b"CREATECONSUMER",
      arg_string(key),
      arg_string(group),
      arg_string(consumer),
    ]),
  )
}

///|
/// `XGROUP DELCONSUMER key group consumer`: delete a consumer, returning its pending
/// entries that are now orphaned.
pub async fn Client::xgroup_delconsumer(
  self : Client,
  key : String,
  group : String,
  consumer : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([
      b"XGROUP",
      b"DELCONSUMER",
      arg_string(key),
      arg_string(group),
      arg_string(consumer),
    ]),
  )
}

///|
/// `XREADGROUP GROUP group consumer [COUNT n] [BLOCK ms] [NOACK] STREAMS key id...`: read
/// entries for a consumer, marking them pending. `id` of `>` reads new entries; a specific
/// id reads pending ones. Returns per stream its name and entries, or `None` on a blocking
/// timeout.
pub async fn Client::xreadgroup(
  self : Client,
  group : String,
  consumer : String,
  streams : Array[(String, String)],
  count? : Int32,
  block? : Int64,
  noack? : Bool,
) -> Array[(String, Array[StreamEntry])]? raise RedisError {
  let args : Array[Bytes] = [
    b"XREADGROUP",
    b"GROUP",
    arg_string(group),
    arg_string(consumer),
  ]
  push_some(args, b"COUNT", count.map(arg_int))
  push_some(args, b"BLOCK", block.map(arg_int64))
  if noack.unwrap_or(false) {
    args.push(b"NOACK")
  }
  args.push(b"STREAMS")
  for (k, _) in streams {
    args.push(arg_string(k))
  }
  for (_, i) in streams {
    args.push(arg_string(i))
  }
  decode_streams(self.command(args))
}

///|
/// `XPENDING key group`: the pending-entry summary for a group. For the detailed entry
/// list use `xpending_extended`.
pub async fn Client::xpending(
  self : Client,
  key : String,
  group : String,
) -> PendingSummary raise RedisError {
  let arr = expect_array(
    self.command([b"XPENDING", arg_string(key), arg_string(group)]),
  )
  guard arr.length() >= 3 else { raise Protocol("unexpected XPENDING reply") }
  let count = expect_int64(arr[0])
  let min_id = expect_string(arr[1])
  let max_id = expect_string(arr[2])
  let consumers : Array[(String, Int64)] = []
  if arr.length() >= 4 {
    for item in expect_array(arr[3]) {
      guard item is @resp.Array([name, pending]) else {
        raise Protocol("unexpected XPENDING consumer")
      }
      consumers.push((expect_string_value(name), expect_number(pending)))
    }
  }
  { count, min_id, max_id, consumers, }
}

///|
/// Decode a stream reply (an array of `[name, [ [id, [f,v,...] ], ... ] ]`) into per-stream
/// entries, `None` for a null reply.
fn decode_streams(
  reply : @resp.RespValue,
) -> Array[(String, Array[StreamEntry])]? raise RedisError {
  match reply {
    @resp.Null => None
    // RESP3 keys the streams by name where RESP2 has a pair for each.
    @resp.RespMap(pairs) => {
      let out : Array[(String, Array[StreamEntry])] = []
      for pair in pairs {
        out.push((expect_string_value(pair.0), decode_entries(pair.1)))
      }
      Some(out)
    }
    @resp.Array(items) => {
      let out : Array[(String, Array[StreamEntry])] = []
      for stream in items {
        match stream {
          @resp.Array(pair) => {
            guard pair.length() >= 2 else {
              raise Protocol("unexpected stream reply")
            }
            let name = @utf8.decode_lossy(expect_bytes(pair[0]).unwrap())
            let entries = decode_entries(pair[1])
            out.push((name, entries))
          }
          _ => raise Protocol("unexpected stream reply")
        }
      }
      Some(out)
    }
    other =>
      raise Protocol("expected stream reply, got " + @resp.resp_kind(other))
  }
}

///|
/// Decode the entries of one stream (`[ [id, [f,v,...] ], ... ]`).
fn decode_entries(
  reply : @resp.RespValue,
) -> Array[StreamEntry] raise RedisError {
  let items = expect_array(reply)
  let out : Array[StreamEntry] = []
  for item in items {
    match item {
      @resp.Array(pair) => {
        guard pair.length() >= 2 else {
          raise Protocol("unexpected stream entry")
        }
        let id = @utf8.decode_lossy(expect_bytes(pair[0]).unwrap())
        let fields = match pair[1] {
          @resp.Array(fv) => decode_pairs(fv)
          // A pending entry that was deleted comes back with no fields.
          @resp.Null => []
          _ => raise Protocol("unexpected stream fields")
        }
        out.push({ id, fields, })
      }
      _ => raise Protocol("unexpected stream entry")
    }
  }
  out
}
