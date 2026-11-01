// The string commands, named as in redis-py. Keys and values are text here; binary-safe
// access goes through `Client::command`, which frames raw bytes. Each method builds the
// argument array, sends it, and decodes the reply into the type redis-py returns.

///|
/// `SET key value [EX secs] [PX ms] [NX|XX] [KEEPTTL]`: store `value` at `key`. Returns
/// `false` when `nx`/`xx` leaves the key unchanged, `true` otherwise.
pub async fn Client::set(
  self : Client,
  key : String,
  value : String,
  ex? : Int64,
  px? : Int64,
  nx? : Bool,
  xx? : Bool,
  keepttl? : Bool,
) -> Bool raise RedisError {
  let args : Array[Bytes] = [b"SET", arg_string(key), arg_string(value)]
  push_some(args, b"EX", ex.map(arg_int64))
  push_some(args, b"PX", px.map(arg_int64))
  if nx.unwrap_or(false) {
    args.push(b"NX")
  }
  if xx.unwrap_or(false) {
    args.push(b"XX")
  }
  if keepttl.unwrap_or(false) {
    args.push(b"KEEPTTL")
  }
  match self.command(args) {
    @resp.SimpleString(_) | @resp.BulkString(_) => true
    @resp.Null => false
    other => raise Protocol("unexpected SET reply: " + @resp.resp_kind(other))
  }
}

///|
/// `SET key value GET`: store `value` and return the value `key` held before, or `None`
/// if it had none.
pub async fn Client::set_get(
  self : Client,
  key : String,
  value : String,
) -> Bytes? raise RedisError {
  let reply = self.command([b"SET", arg_string(key), arg_string(value), b"GET"])
  expect_bytes(reply)
}

///|
/// `SETNX key value`: store `value` only if `key` is absent. `true` if stored.
pub async fn Client::setnx(
  self : Client,
  key : String,
  value : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"SETNX", arg_string(key), arg_string(value)]))
}

///|
/// `SETEX key secs value`: store `value` at `key` with a `secs`-second expiry.
pub async fn Client::setex(
  self : Client,
  key : String,
  seconds : Int64,
  value : String,
) -> Unit raise RedisError {
  status_ok(
    self.command([
      b"SETEX",
      arg_string(key),
      arg_int64(seconds),
      arg_string(value),
    ]),
  )
}

///|
/// `PSETEX key ms value`: store `value` at `key` with a `ms`-millisecond expiry.
pub async fn Client::psetex(
  self : Client,
  key : String,
  milliseconds : Int64,
  value : String,
) -> Unit raise RedisError {
  status_ok(
    self.command([
      b"PSETEX",
      arg_string(key),
      arg_int64(milliseconds),
      arg_string(value),
    ]),
  )
}

///|
/// `GET key`: the value at `key`, or `None` if absent or expired.
pub async fn Client::get(
  self : Client,
  key : String,
) -> Bytes? raise RedisError {
  expect_bytes(self.command([b"GET", arg_string(key)]))
}

///|
/// `MGET key...`: the value at each key, `None` where a key is absent, in the same order.
pub async fn Client::mget(
  self : Client,
  keys : Array[String],
) -> Array[Bytes?] raise RedisError {
  let args : Array[Bytes] = [b"MGET"]
  for k in keys {
    args.push(arg_string(k))
  }
  let items = expect_array(self.command(args))
  items.map(x => expect_bytes(x))
}

///|
/// `MSET key value...`: store every pair atomically.
pub async fn Client::mset(
  self : Client,
  pairs : Array[(String, String)],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"MSET"]
  for (k, v) in pairs {
    args.push(arg_string(k))
    args.push(arg_string(v))
  }
  status_ok(self.command(args))
}

///|
/// `APPEND key value`: append `value` to `key`, returning the new length in bytes.
pub async fn Client::append(
  self : Client,
  key : String,
  value : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"APPEND", arg_string(key), arg_string(value)]))
}

///|
/// `STRLEN key`: the length of `key`'s value in bytes.
pub async fn Client::strlen(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"STRLEN", arg_string(key)]))
}

///|
/// `INCR key`: increment `key`'s integer value by 1, returning the result.
pub async fn Client::incr(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"INCR", arg_string(key)]))
}

///|
/// `INCRBY key n`: add `n` to `key`'s integer value, returning the result.
pub async fn Client::incrby(
  self : Client,
  key : String,
  n : Int64,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"INCRBY", arg_string(key), arg_int64(n)]))
}

///|
/// `DECR key`: decrement `key`'s integer value by 1, returning the result.
pub async fn Client::decr(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"DECR", arg_string(key)]))
}

///|
/// `DECRBY key n`: subtract `n` from `key`'s integer value, returning the result.
pub async fn Client::decrby(
  self : Client,
  key : String,
  n : Int64,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"DECRBY", arg_string(key), arg_int64(n)]))
}

///|
/// `GETRANGE key start end`: the substring of `key` from `start` to `end` (inclusive,
/// negative from the end).
pub async fn Client::getrange(
  self : Client,
  key : String,
  start : Int32,
  end : Int32,
) -> Bytes raise RedisError {
  expect_bytes(
    self.command([b"GETRANGE", arg_string(key), arg_int(start), arg_int(end)]),
  ).unwrap()
}

///|
/// `SETRANGE key offset value`: overwrite `key` at `offset`, returning the new length.
pub async fn Client::setrange(
  self : Client,
  key : String,
  offset : Int32,
  value : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([
      b"SETRANGE",
      arg_string(key),
      arg_int(offset),
      arg_string(value),
    ]),
  )
}

///|
/// `GETDEL key`: return `key`'s value and delete the key, or `None` if absent.
pub async fn Client::getdel(
  self : Client,
  key : String,
) -> Bytes? raise RedisError {
  expect_bytes(self.command([b"GETDEL", arg_string(key)]))
}

///|
/// `GETEX key [EX secs] [PX ms] [EXAT secs] [PXAT ms] [PERSIST]`: return `key`'s value
/// and apply or clear its expiry, or `None` if absent.
pub async fn Client::getex(
  self : Client,
  key : String,
  ex? : Int64,
  px? : Int64,
  exat? : Int64,
  pxat? : Int64,
  persist? : Bool,
) -> Bytes? raise RedisError {
  let args : Array[Bytes] = [b"GETEX", arg_string(key)]
  push_some(args, b"EX", ex.map(arg_int64))
  push_some(args, b"PX", px.map(arg_int64))
  push_some(args, b"EXAT", exat.map(arg_int64))
  push_some(args, b"PXAT", pxat.map(arg_int64))
  if persist.unwrap_or(false) {
    args.push(b"PERSIST")
  }
  expect_bytes(self.command(args))
}
