// The sorted-set commands, named as in redis-py. A sorted set maps members to scores and
// keeps members ordered by score; these expose rank, range and aggregation operations.

///|
/// `ZADD key [NX] [XX] [CH] score member...`: add or update members with their scores,
/// returning how many members changed (or, with `ch`, were added or updated).
pub async fn Client::zadd(
  self : Client,
  key : String,
  members : Array[(String, Double)],
  nx? : Bool,
  xx? : Bool,
  ch? : Bool,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"ZADD", arg_string(key)]
  if nx.unwrap_or(false) {
    args.push(b"NX")
  }
  if xx.unwrap_or(false) {
    args.push(b"XX")
  }
  if ch.unwrap_or(false) {
    args.push(b"CH")
  }
  for (m, s) in members {
    args.push(arg_double(s))
    args.push(arg_string(m))
  }
  expect_int64(self.command(args))
}

///|
/// `ZREM key member...`: remove the members, returning how many existed.
pub async fn Client::zrem(
  self : Client,
  key : String,
  members : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"ZREM", arg_string(key)]
  for m in members {
    args.push(arg_string(m))
  }
  expect_int64(self.command(args))
}

///|
/// `ZSCORE key member`: the score of `member`, or `None` if absent.
pub async fn Client::zscore(
  self : Client,
  key : String,
  m : String,
) -> Double? raise RedisError {
  expect_score(self.command([b"ZSCORE", arg_string(key), arg_string(m)]))
}

///|
/// `ZMSCORE key member...`: the score of each member, `None` where absent, in order.
pub async fn Client::zmscore(
  self : Client,
  key : String,
  members : Array[String],
) -> Array[Double?] raise RedisError {
  let args : Array[Bytes] = [b"ZMSCORE", arg_string(key)]
  for m in members {
    args.push(arg_string(m))
  }
  let items = expect_array(self.command(args))
  items.map(expect_score)
}

///|
/// `ZINCRBY key increment member`: add `increment` to `member`'s score, returning the new
/// score.
pub async fn Client::zincrby(
  self : Client,
  key : String,
  increment : Double,
  m : String,
) -> Double raise RedisError {
  expect_double(
    self.command([
      b"ZINCRBY",
      arg_string(key),
      arg_double(increment),
      arg_string(m),
    ]),
  )
}

///|
/// `ZCARD key`: the number of members in the sorted set.
pub async fn Client::zcard(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"ZCARD", arg_string(key)]))
}

///|
/// `ZRANK key member`: the rank (0-based, lowest score first) of `member`, or `None` if
/// absent.
pub async fn Client::zrank(
  self : Client,
  key : String,
  m : String,
) -> Int64? raise RedisError {
  expect_index(self.command([b"ZRANK", arg_string(key), arg_string(m)]))
}

///|
/// `ZREVRANK key member`: the rank (0-based, highest score first) of `member`.
pub async fn Client::zrevrank(
  self : Client,
  key : String,
  m : String,
) -> Int64? raise RedisError {
  expect_index(self.command([b"ZREVRANK", arg_string(key), arg_string(m)]))
}

///|
/// `ZRANGE key start stop`: the members from `start` to `stop` (inclusive, negative from
/// the tail), lowest score first.
pub async fn Client::zrange(
  self : Client,
  key : String,
  start : Int32,
  stop : Int32,
) -> Array[String] raise RedisError {
  let items = expect_array(
    self.command([b"ZRANGE", arg_string(key), arg_int(start), arg_int(stop)]),
  )
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `ZRANGE key start stop WITHSCORES`: the members and scores in rank order.
pub async fn Client::zrange_scores(
  self : Client,
  key : String,
  start : Int32,
  stop : Int32,
) -> Array[(String, Double)] raise RedisError {
  let items = expect_array(
    self.command([
      b"ZRANGE",
      arg_string(key),
      arg_int(start),
      arg_int(stop),
      b"WITHSCORES",
    ]),
  )
  decode_member_scores(items)
}

///|
/// `ZREVRANGE key start stop`: the members in rank order, highest score first.
pub async fn Client::zrevrange(
  self : Client,
  key : String,
  start : Int32,
  stop : Int32,
) -> Array[String] raise RedisError {
  let items = expect_array(
    self.command([b"ZREVRANGE", arg_string(key), arg_int(start), arg_int(stop)]),
  )
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `ZREVRANGE key start stop WITHSCORES`: the members and scores, highest score first.
pub async fn Client::zrevrange_scores(
  self : Client,
  key : String,
  start : Int32,
  stop : Int32,
) -> Array[(String, Double)] raise RedisError {
  let items = expect_array(
    self.command([
      b"ZREVRANGE",
      arg_string(key),
      arg_int(start),
      arg_int(stop),
      b"WITHSCORES",
    ]),
  )
  decode_member_scores(items)
}

///|
/// `ZRANGEBYSCORE key min max [LIMIT offset count]`: members with scores in `[min, max]`
/// (use `(score` to exclude a bound), lowest score first.
pub async fn Client::zrangebyscore(
  self : Client,
  key : String,
  min : String,
  max : String,
  offset? : Int32,
  count? : Int32,
) -> Array[String] raise RedisError {
  let items = expect_array(
    self.command(zrangebyscore_args(key, min, max, offset, count, false)),
  )
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `ZRANGEBYSCORE ... WITHSCORES`: the members and scores in score order.
pub async fn Client::zrangebyscore_scores(
  self : Client,
  key : String,
  min : String,
  max : String,
  offset? : Int32,
  count? : Int32,
) -> Array[(String, Double)] raise RedisError {
  let items = expect_array(
    self.command(zrangebyscore_args(key, min, max, offset, count, true)),
  )
  decode_member_scores(items)
}

///|
/// Build the `ZRANGEBYSCORE` argument array with the optional `WITHSCORES` and `LIMIT`.
fn zrangebyscore_args(
  key : String,
  min : String,
  max : String,
  offset : Int32?,
  count : Int32?,
  withscores : Bool,
) -> Array[Bytes] {
  let args : Array[Bytes] = [
    b"ZRANGEBYSCORE",
    arg_string(key),
    arg_string(min),
    arg_string(max),
  ]
  if withscores {
    args.push(b"WITHSCORES")
  }
  match (offset, count) {
    (Some(o), Some(c)) => {
      args.push(b"LIMIT")
      args.push(arg_int(o))
      args.push(arg_int(c))
    }
    _ => ()
  }
  args
}

///|
/// `ZREVRANGEBYSCORE key max min [LIMIT offset count]`: members with scores in `[min, max]`,
/// highest score first.
pub async fn Client::zrevrangebyscore(
  self : Client,
  key : String,
  max : String,
  min : String,
  offset? : Int32,
  count? : Int32,
) -> Array[String] raise RedisError {
  let items = expect_array(
    self.command(zrevrangebyscore_args(key, max, min, offset, count, false)),
  )
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `ZREVRANGEBYSCORE ... WITHSCORES`: the members and scores, highest score first.
pub async fn Client::zrevrangebyscore_scores(
  self : Client,
  key : String,
  max : String,
  min : String,
  offset? : Int32,
  count? : Int32,
) -> Array[(String, Double)] raise RedisError {
  let items = expect_array(
    self.command(zrevrangebyscore_args(key, max, min, offset, count, true)),
  )
  decode_member_scores(items)
}

///|
/// Build the `ZREVRANGEBYSCORE` argument array (note redis takes `max` before `min`).
fn zrevrangebyscore_args(
  key : String,
  max : String,
  min : String,
  offset : Int32?,
  count : Int32?,
  withscores : Bool,
) -> Array[Bytes] {
  let args : Array[Bytes] = [
    b"ZREVRANGEBYSCORE",
    arg_string(key),
    arg_string(max),
    arg_string(min),
  ]
  if withscores {
    args.push(b"WITHSCORES")
  }
  match (offset, count) {
    (Some(o), Some(c)) => {
      args.push(b"LIMIT")
      args.push(arg_int(o))
      args.push(arg_int(c))
    }
    _ => ()
  }
  args
}

///|
/// `ZCOUNT key min max`: the number of members with scores in `[min, max]`.
pub async fn Client::zcount(
  self : Client,
  key : String,
  min : String,
  max : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([b"ZCOUNT", arg_string(key), arg_string(min), arg_string(max)]),
  )
}

///|
/// `ZREMRANGEBYRANK key start stop`: remove members by rank range, returning the removed.
pub async fn Client::zremrangebyrank(
  self : Client,
  key : String,
  start : Int32,
  stop : Int32,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([
      b"ZREMRANGEBYRANK",
      arg_string(key),
      arg_int(start),
      arg_int(stop),
    ]),
  )
}

///|
/// `ZREMRANGEBYSCORE key min max`: remove members by score range, returning the removed.
pub async fn Client::zremrangebyscore(
  self : Client,
  key : String,
  min : String,
  max : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([
      b"ZREMRANGEBYSCORE",
      arg_string(key),
      arg_string(min),
      arg_string(max),
    ]),
  )
}

///|
/// `ZPOPMIN key [count]`: remove and return the lowest-scoring `count` members and their
/// scores.
pub async fn Client::zpopmin(
  self : Client,
  key : String,
  count? : Int32,
) -> Array[(String, Double)] raise RedisError {
  let args : Array[Bytes] = [b"ZPOPMIN", arg_string(key)]
  match count {
    Some(n) => args.push(arg_int(n))
    None => ()
  }
  let items = expect_array(self.command(args))
  decode_member_scores(items)
}

///|
/// `ZPOPMAX key [count]`: remove and return the highest-scoring `count` members.
pub async fn Client::zpopmax(
  self : Client,
  key : String,
  count? : Int32,
) -> Array[(String, Double)] raise RedisError {
  let args : Array[Bytes] = [b"ZPOPMAX", arg_string(key)]
  match count {
    Some(n) => args.push(arg_int(n))
    None => ()
  }
  let items = expect_array(self.command(args))
  decode_member_scores(items)
}

///|
/// `ZUNIONSTORE destination numkeys key... [WEIGHTS w...] [AGGREGATE SUM|MIN|MAX]`: store
/// the union of the sorted sets, returning how many members the result has.
pub async fn Client::zunionstore(
  self : Client,
  destination : String,
  keys : Array[String],
  weights? : Array[Double],
  aggregate? : String,
) -> Int64 raise RedisError {
  self.zstore(b"ZUNIONSTORE", destination, keys, weights, aggregate)
}

///|
/// `ZINTERSTORE destination numkeys key... [WEIGHTS w...] [AGGREGATE SUM|MIN|MAX]`: store
/// the intersection of the sorted sets, returning how many members the result has.
pub async fn Client::zinterstore(
  self : Client,
  destination : String,
  keys : Array[String],
  weights? : Array[Double],
  aggregate? : String,
) -> Int64 raise RedisError {
  self.zstore(b"ZINTERSTORE", destination, keys, weights, aggregate)
}

///|
/// Build and send a `ZUNIONSTORE`/`ZINTERSTORE` command.
async fn Client::zstore(
  self : Client,
  op : Bytes,
  destination : String,
  keys : Array[String],
  weights : Array[Double]?,
  aggregate : String?,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [
    op,
    arg_string(destination),
    arg_int(keys.length()),
  ]
  for k in keys {
    args.push(arg_string(k))
  }
  match weights {
    Some(ws) => {
      args.push(b"WEIGHTS")
      for w in ws {
        args.push(arg_double(w))
      }
    }
    None => ()
  }
  match aggregate {
    Some(a) => {
      args.push(b"AGGREGATE")
      args.push(arg_string(a))
    }
    None => ()
  }
  expect_int64(self.command(args))
}

///|
/// `ZSCAN key cursor [MATCH pattern] [COUNT n]`: an incremental sorted-set member scan.
/// Returns the next cursor and the members found this call.
pub async fn Client::zscan(
  self : Client,
  key : String,
  cursor : String,
  pattern? : String,
  count? : Int32,
) -> (String, Array[String]) raise RedisError {
  let args : Array[Bytes] = [b"ZSCAN", arg_string(key), arg_string(cursor)]
  push_some(args, b"MATCH", pattern.map(arg_string))
  push_some(args, b"COUNT", count.map(arg_int))
  let arr = expect_array(self.command(args))
  guard arr.length() >= 2 else { raise Protocol("unexpected ZSCAN reply") }
  let next = @utf8.decode_lossy(expect_bytes(arr[0]).unwrap())
  let members = expect_array(arr[1])
  (next, members.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap())))
}

///|
/// `ZRANDMEMBER key [count] [WITHSCORES]`: one or more random members, optionally with
/// scores.
pub async fn Client::zrandmember(
  self : Client,
  key : String,
  count? : Int32,
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"ZRANDMEMBER", arg_string(key)]
  match count {
    Some(n) => args.push(arg_int(n))
    None => ()
  }
  let items = expect_some(self.command(args))
  items.map(expect_string_value)
}

///|
/// `ZRANDMEMBER key count WITHSCORES`: random members with their scores. A negative `count`
/// may repeat a member.
pub async fn Client::zrandmember_scores(
  self : Client,
  key : String,
  count : Int32,
) -> Array[(String, Double)] raise RedisError {
  let args : Array[Bytes] = [
    b"ZRANDMEMBER",
    arg_string(key),
    arg_int(count),
    b"WITHSCORES",
  ]
  decode_member_scores(expect_array(self.command(args)))
}

///|
/// `BZPOPMIN key... timeout`: blocking pop of the lowest-scoring member across keys.
/// Returns `(key, member, score)`, or `None` on timeout.
pub async fn Client::bzpopmin(
  self : Client,
  keys : Array[String],
  timeout : Int32,
) -> (String, String, Double)? raise RedisError {
  let args : Array[Bytes] = [b"BZPOPMIN"]
  for k in keys {
    args.push(arg_string(k))
  }
  args.push(arg_int(timeout))
  decode_key_member_score(self.command(args))
}

///|
/// `BZPOPMAX key... timeout`: blocking pop of the highest-scoring member across keys.
pub async fn Client::bzpopmax(
  self : Client,
  keys : Array[String],
  timeout : Int32,
) -> (String, String, Double)? raise RedisError {
  let args : Array[Bytes] = [b"BZPOPMAX"]
  for k in keys {
    args.push(arg_string(k))
  }
  args.push(arg_int(timeout))
  decode_key_member_score(self.command(args))
}

///|
/// Decode an integer reply into an optional rank (`None` for a null reply).
fn expect_index(reply : @resp.RespValue) -> Int64? raise RedisError {
  match reply {
    @resp.Null => None
    other => Some(expect_int64(other))
  }
}

///|
/// Decode member/score pairs. RESP3 nests a pair for each member; RESP2, and `ZPOPMIN` with no
/// count under either, alternate them in one flat array.
fn decode_member_scores(
  items : Array[@resp.RespValue],
) -> Array[(String, Double)] raise RedisError {
  let out : Array[(String, Double)] = []
  if items is [@resp.Array(_), ..] {
    for item in items {
      guard item is @resp.Array([name, score]) else {
        raise Protocol("unexpected member/score pair")
      }
      out.push((expect_string_value(name), expect_double(score)))
    }
    return out
  }
  for i = 0; i < items.length(); i = i + 2 {
    let m = @utf8.decode_lossy(expect_bytes(items[i]).unwrap())
    let s = expect_double(items[i + 1])
    out.push((m, s))
  }
  out
}

///|
/// Decode a `[key, member, score]` reply into a tuple, `None` for a null reply.
fn decode_key_member_score(
  reply : @resp.RespValue,
) -> (String, String, Double)? raise RedisError {
  match reply {
    @resp.Null => None
    @resp.Array(items) => {
      guard items.length() == 3 else {
        raise Protocol("unexpected bzpop reply")
      }
      let key = @utf8.decode_lossy(expect_bytes(items[0]).unwrap())
      let m = @utf8.decode_lossy(expect_bytes(items[1]).unwrap())
      let score = expect_double(items[2])
      Some((key, m, score))
    }
    other =>
      raise Protocol("expected key/member/score, got " + @resp.resp_kind(other))
  }
}
