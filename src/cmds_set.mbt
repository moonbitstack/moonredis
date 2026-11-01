// The set commands, named as in redis-py. A redis set is an unordered collection of
// unique strings; these expose membership and set-algebra operations.

///|
/// `SADD key member...`: add the members, returning how many were new.
pub async fn Client::sadd(
  self : Client,
  key : String,
  members : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"SADD", arg_string(key)]
  for m in members {
    args.push(arg_string(m))
  }
  expect_int64(self.command(args))
}

///|
/// `SREM key member...`: remove the members, returning how many existed.
pub async fn Client::srem(
  self : Client,
  key : String,
  members : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"SREM", arg_string(key)]
  for m in members {
    args.push(arg_string(m))
  }
  expect_int64(self.command(args))
}

///|
/// `SMEMBERS key`: every member of the set.
pub async fn Client::smembers(
  self : Client,
  key : String,
) -> Array[String] raise RedisError {
  let items = expect_array(self.command([b"SMEMBERS", arg_string(key)]))
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `SISMEMBER key member`: whether `member` is in the set.
pub async fn Client::sismember(
  self : Client,
  key : String,
  m : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"SISMEMBER", arg_string(key), arg_string(m)]))
}

///|
/// `SCARD key`: the number of members in the set.
pub async fn Client::scard(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"SCARD", arg_string(key)]))
}

///|
/// `SPOP key`: remove and return a random member, or `None` when the set is empty.
pub async fn Client::spop(
  self : Client,
  key : String,
) -> String? raise RedisError {
  expect_string(self.command([b"SPOP", arg_string(key)]))
}

///|
/// `SPOP key count`: remove and return up to `count` random members.
pub async fn Client::spopn(
  self : Client,
  key : String,
  count : Int32,
) -> Array[String] raise RedisError {
  let items = expect_array(
    self.command([b"SPOP", arg_string(key), arg_int(count)]),
  )
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `SRANDMEMBER key`: a random member, or `None` when the set is empty.
pub async fn Client::srandmember(
  self : Client,
  key : String,
) -> String? raise RedisError {
  expect_string(self.command([b"SRANDMEMBER", arg_string(key)]))
}

///|
/// `SRANDMEMBER key count`: `count` random members, with repeats when `count` exceeds
/// the set size.
pub async fn Client::srandmembern(
  self : Client,
  key : String,
  count : Int32,
) -> Array[String] raise RedisError {
  let items = expect_array(
    self.command([b"SRANDMEMBER", arg_string(key), arg_int(count)]),
  )
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `SINTER key...`: the members present in every given set.
pub async fn Client::sinter(
  self : Client,
  keys : Array[String],
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"SINTER"]
  for k in keys {
    args.push(arg_string(k))
  }
  let items = expect_array(self.command(args))
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `SUNION key...`: the members present in any given set.
pub async fn Client::sunion(
  self : Client,
  keys : Array[String],
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"SUNION"]
  for k in keys {
    args.push(arg_string(k))
  }
  let items = expect_array(self.command(args))
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `SDIFF key...`: the members in the first set absent from the rest.
pub async fn Client::sdiff(
  self : Client,
  keys : Array[String],
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"SDIFF"]
  for k in keys {
    args.push(arg_string(k))
  }
  let items = expect_array(self.command(args))
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `SINTERSTORE destination key...`: store the intersection of the sets in `destination`.
pub async fn Client::sinterstore(
  self : Client,
  destination : String,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"SINTERSTORE", arg_string(destination)]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}

///|
/// `SUNIONSTORE destination key...`: store the union of the sets in `destination`.
pub async fn Client::sunionstore(
  self : Client,
  destination : String,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"SUNIONSTORE", arg_string(destination)]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}

///|
/// `SDIFFSTORE destination key...`: store the difference of the sets in `destination`.
pub async fn Client::sdiffstore(
  self : Client,
  destination : String,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"SDIFFSTORE", arg_string(destination)]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}

///|
/// `SMOVE source destination member`: move `member` from `source` to `destination`.
/// `true` if moved.
pub async fn Client::smove(
  self : Client,
  source : String,
  destination : String,
  m : String,
) -> Bool raise RedisError {
  expect_bool(
    self.command([
      b"SMOVE",
      arg_string(source),
      arg_string(destination),
      arg_string(m),
    ]),
  )
}

///|
/// `SSCAN key cursor [MATCH pattern] [COUNT n]`: an incremental set member scan.
/// Returns the next cursor and the members found this call.
pub async fn Client::sscan(
  self : Client,
  key : String,
  cursor : String,
  pattern? : String,
  count? : Int32,
) -> (String, Array[String]) raise RedisError {
  let args : Array[Bytes] = [b"SSCAN", arg_string(key), arg_string(cursor)]
  push_some(args, b"MATCH", pattern.map(arg_string))
  push_some(args, b"COUNT", count.map(arg_int))
  let arr = expect_array(self.command(args))
  guard arr.length() >= 2 else { raise Protocol("unexpected SSCAN reply") }
  let next = @utf8.decode_lossy(expect_bytes(arr[0]).unwrap())
  let members = expect_array(arr[1])
  (next, members.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap())))
}
