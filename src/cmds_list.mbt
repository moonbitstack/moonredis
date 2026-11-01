// The list commands, named as in redis-py. A redis list is a sequence of strings; these
// expose the head/tail push-pop and range operations as MoonBit arrays and byte values.

///|
/// `LPUSH key value...`: prepend each value, returning the new length.
pub async fn Client::lpush(
  self : Client,
  key : String,
  values : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"LPUSH", arg_string(key)]
  for v in values {
    args.push(arg_string(v))
  }
  expect_int64(self.command(args))
}

///|
/// `RPUSH key value...`: append each value, returning the new length.
pub async fn Client::rpush(
  self : Client,
  key : String,
  values : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"RPUSH", arg_string(key)]
  for v in values {
    args.push(arg_string(v))
  }
  expect_int64(self.command(args))
}

///|
/// `LPUSHX key value...`: prepend only if `key` already exists, returning the length.
pub async fn Client::lpushx(
  self : Client,
  key : String,
  values : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"LPUSHX", arg_string(key)]
  for v in values {
    args.push(arg_string(v))
  }
  expect_int64(self.command(args))
}

///|
/// `RPUSHX key value...`: append only if `key` already exists, returning the length.
pub async fn Client::rpushx(
  self : Client,
  key : String,
  values : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"RPUSHX", arg_string(key)]
  for v in values {
    args.push(arg_string(v))
  }
  expect_int64(self.command(args))
}

///|
/// `LPOP key`: remove and return the head element, or `None` when the list is empty.
pub async fn Client::lpop(
  self : Client,
  key : String,
) -> Bytes? raise RedisError {
  expect_bytes(self.command([b"LPOP", arg_string(key)]))
}

///|
/// `LPOP key count`: remove and return up to `count` head elements.
pub async fn Client::lpopn(
  self : Client,
  key : String,
  count : Int32,
) -> Array[Bytes] raise RedisError {
  let items = expect_array(
    self.command([b"LPOP", arg_string(key), arg_int(count)]),
  )
  items.map(x => expect_bytes(x).unwrap())
}

///|
/// `RPOP key`: remove and return the tail element, or `None` when the list is empty.
pub async fn Client::rpop(
  self : Client,
  key : String,
) -> Bytes? raise RedisError {
  expect_bytes(self.command([b"RPOP", arg_string(key)]))
}

///|
/// `RPOP key count`: remove and return up to `count` tail elements.
pub async fn Client::rpopn(
  self : Client,
  key : String,
  count : Int32,
) -> Array[Bytes] raise RedisError {
  let items = expect_array(
    self.command([b"RPOP", arg_string(key), arg_int(count)]),
  )
  items.map(x => expect_bytes(x).unwrap())
}

///|
/// `LLEN key`: the length of the list.
pub async fn Client::llen(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"LLEN", arg_string(key)]))
}

///|
/// `LINDEX key index`: the element at `index`, or `None` if out of range.
pub async fn Client::lindex(
  self : Client,
  key : String,
  index : Int32,
) -> Bytes? raise RedisError {
  expect_bytes(self.command([b"LINDEX", arg_string(key), arg_int(index)]))
}

///|
/// `LRANGE key start stop`: the elements from `start` to `stop` (inclusive, negative
/// from the tail).
pub async fn Client::lrange(
  self : Client,
  key : String,
  start : Int32,
  stop : Int32,
) -> Array[Bytes] raise RedisError {
  let items = expect_array(
    self.command([b"LRANGE", arg_string(key), arg_int(start), arg_int(stop)]),
  )
  items.map(x => expect_bytes(x).unwrap())
}

///|
/// `LSET key index value`: set the element at `index`. Raises `Reply` on a bad index.
pub async fn Client::lset(
  self : Client,
  key : String,
  index : Int32,
  value : String,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"LSET", arg_string(key), arg_int(index), arg_string(value)]),
  )
}

///|
/// `LREM key count value`: remove the first `count` elements equal to `value`. When
/// `count` is negative, remove from the tail; when 0, remove all. Returns the removed.
pub async fn Client::lrem(
  self : Client,
  key : String,
  count : Int32,
  value : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([b"LREM", arg_string(key), arg_int(count), arg_string(value)]),
  )
}

///|
/// `LINSERT key where pivot value`: insert `value` before (`BEFORE`) or after (`AFTER`)
/// `pivot`. Returns the new length, or `-1` when `pivot` is absent.
pub async fn Client::linsert(
  self : Client,
  key : String,
  where_ : String,
  pivot : String,
  value : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([
      b"LINSERT",
      arg_string(key),
      arg_string(where_),
      arg_string(pivot),
      arg_string(value),
    ]),
  )
}

///|
/// `LTRIM key start stop`: keep only the elements from `start` to `stop`.
pub async fn Client::ltrim(
  self : Client,
  key : String,
  start : Int32,
  stop : Int32,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"LTRIM", arg_string(key), arg_int(start), arg_int(stop)]),
  )
}

///|
/// `RPOPLPUSH source destination`: pop the tail of `source` and push it to the head of
/// `destination`, returning the element, or `None` when `source` is empty.
pub async fn Client::rpoplpush(
  self : Client,
  source : String,
  destination : String,
) -> Bytes? raise RedisError {
  expect_bytes(
    self.command([b"RPOPLPUSH", arg_string(source), arg_string(destination)]),
  )
}

///|
/// `LMOVE source destination LEFT|RIGHT LEFT|RIGHT`: pop from one end of `source` and
/// push to one end of `destination`, returning the element, or `None` when empty.
pub async fn Client::lmove(
  self : Client,
  source : String,
  destination : String,
  wherefrom : String,
  whereto : String,
) -> Bytes? raise RedisError {
  expect_bytes(
    self.command([
      b"LMOVE",
      arg_string(source),
      arg_string(destination),
      arg_string(wherefrom),
      arg_string(whereto),
    ]),
  )
}

///|
/// `BLPOP key... timeout`: blocking pop of the first available head element across the
/// given keys, waiting up to `timeout` seconds (0 = forever). Returns the key and value,
/// or `None` on timeout.
pub async fn Client::blpop(
  self : Client,
  keys : Array[String],
  timeout : Int32,
) -> (String, Bytes)? raise RedisError {
  let args : Array[Bytes] = [b"BLPOP"]
  for k in keys {
    args.push(arg_string(k))
  }
  args.push(arg_int(timeout))
  decode_key_value(self.command(args))
}

///|
/// `BRPOP key... timeout`: blocking pop of the first available tail element across the
/// given keys. Returns the key and value, or `None` on timeout.
pub async fn Client::brpop(
  self : Client,
  keys : Array[String],
  timeout : Int32,
) -> (String, Bytes)? raise RedisError {
  let args : Array[Bytes] = [b"BRPOP"]
  for k in keys {
    args.push(arg_string(k))
  }
  args.push(arg_int(timeout))
  decode_key_value(self.command(args))
}

///|
/// `BRPOPLPUSH source destination timeout`: blocking `RPOPLPUSH`.
pub async fn Client::brpoplpush(
  self : Client,
  source : String,
  destination : String,
  timeout : Int32,
) -> Bytes? raise RedisError {
  expect_bytes(
    self.command([
      b"BRPOPLPUSH",
      arg_string(source),
      arg_string(destination),
      arg_int(timeout),
    ]),
  )
}

///|
/// `BLMOVE source destination wherefrom whereto timeout`: blocking `LMOVE`.
pub async fn Client::blmove(
  self : Client,
  source : String,
  destination : String,
  wherefrom : String,
  whereto : String,
  timeout : Int32,
) -> Bytes? raise RedisError {
  expect_bytes(
    self.command([
      b"BLMOVE",
      arg_string(source),
      arg_string(destination),
      arg_string(wherefrom),
      arg_string(whereto),
      arg_int(timeout),
    ]),
  )
}

///|
/// Decode a `[key, value]` pair reply into a key/value tuple, `None` for a null reply.
fn decode_key_value(
  reply : @resp.RespValue,
) -> (String, Bytes)? raise RedisError {
  match reply {
    @resp.Null => None
    @resp.Array(items) => {
      guard items.length() == 2 else {
        raise Protocol("unexpected key/value reply")
      }
      let key = @utf8.decode_lossy(expect_bytes(items[0]).unwrap())
      let value = expect_bytes(items[1]).unwrap()
      Some((key, value))
    }
    other => raise Protocol("expected key/value, got " + @resp.resp_kind(other))
  }
}
