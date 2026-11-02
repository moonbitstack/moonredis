// The hash commands, named as in redis-py. A hash maps field names to string values;
// these map to MoonBit `String`-keyed access over the same `Client`.

///|
/// `HSET key field value...`: set one or more fields, returning the count of fields that
/// were new.
pub async fn Client::hset(
  self : Client,
  key : String,
  fields : Array[(String, String)],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"HSET", arg_string(key)]
  for (f, v) in fields {
    args.push(arg_string(f))
    args.push(arg_string(v))
  }
  expect_int64(self.command(args))
}

///|
/// `HSETNX key field value`: set `field` only if absent. `true` if set.
pub async fn Client::hsetnx(
  self : Client,
  key : String,
  field : String,
  value : String,
) -> Bool raise RedisError {
  expect_bool(
    self.command([
      b"HSETNX",
      arg_string(key),
      arg_string(field),
      arg_string(value),
    ]),
  )
}

///|
/// `HMSET key field value...`: set several fields atomically. Deprecated in favour of
/// `HSET` but kept for parity with redis-py.
pub async fn Client::hmset(
  self : Client,
  key : String,
  fields : Array[(String, String)],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"HMSET", arg_string(key)]
  for (f, v) in fields {
    args.push(arg_string(f))
    args.push(arg_string(v))
  }
  status_ok(self.command(args))
}

///|
/// `HGET key field`: the value at `field`, or `None` if the key or field is absent.
pub async fn Client::hget(
  self : Client,
  key : String,
  field : String,
) -> Bytes? raise RedisError {
  expect_bytes(self.command([b"HGET", arg_string(key), arg_string(field)]))
}

///|
/// `HMGET key field...`: the value at each field, `None` where absent, in order.
pub async fn Client::hmget(
  self : Client,
  key : String,
  fields : Array[String],
) -> Array[Bytes?] raise RedisError {
  let args : Array[Bytes] = [b"HMGET", arg_string(key)]
  for f in fields {
    args.push(arg_string(f))
  }
  let items = expect_array(self.command(args))
  items.map(x => expect_bytes(x))
}

///|
/// `HGETALL key`: every field/value pair as an array of alternating field, value.
pub async fn Client::hgetall(
  self : Client,
  key : String,
) -> Array[(String, String)] raise RedisError {
  let items = expect_array(self.command([b"HGETALL", arg_string(key)]))
  decode_pairs(items)
}

///|
/// `HDEL key field...`: delete the given fields, returning how many existed.
pub async fn Client::hdel(
  self : Client,
  key : String,
  fields : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"HDEL", arg_string(key)]
  for f in fields {
    args.push(arg_string(f))
  }
  expect_int64(self.command(args))
}

///|
/// `HEXISTS key field`: whether `field` exists in the hash.
pub async fn Client::hexists(
  self : Client,
  key : String,
  field : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"HEXISTS", arg_string(key), arg_string(field)]))
}

///|
/// `HLEN key`: the number of fields in the hash.
pub async fn Client::hlen(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"HLEN", arg_string(key)]))
}

///|
/// `HSTRLEN key field`: the byte length of `field`'s value (0 if absent).
pub async fn Client::hstrlen(
  self : Client,
  key : String,
  field : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"HSTRLEN", arg_string(key), arg_string(field)]))
}

///|
/// `HINCRBY key field n`: add `n` to `field`'s integer value, returning the result.
pub async fn Client::hincrby(
  self : Client,
  key : String,
  field : String,
  n : Int64,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([b"HINCRBY", arg_string(key), arg_string(field), arg_int64(n)]),
  )
}

///|
/// `HINCRBYFLOAT key field f`: add `f` to `field`'s value, returning the new value.
pub async fn Client::hincrbyfloat(
  self : Client,
  key : String,
  field : String,
  f : Double,
) -> Double raise RedisError {
  expect_double(
    self.command([
      b"HINCRBYFLOAT",
      arg_string(key),
      arg_string(field),
      arg_double(f),
    ]),
  )
}

///|
/// `HKEYS key`: the field names of the hash.
pub async fn Client::hkeys(
  self : Client,
  key : String,
) -> Array[String] raise RedisError {
  let items = expect_array(self.command([b"HKEYS", arg_string(key)]))
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `HVALS key`: the values of the hash.
pub async fn Client::hvals(
  self : Client,
  key : String,
) -> Array[String] raise RedisError {
  let items = expect_array(self.command([b"HVALS", arg_string(key)]))
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `HSCAN key cursor [MATCH pattern] [COUNT n]`: an incremental hash field scan.
/// Returns the next cursor and the field/value pairs found this call.
pub async fn Client::hscan(
  self : Client,
  key : String,
  cursor : String,
  pattern? : String,
  count? : Int32,
) -> (String, Array[(String, String)]) raise RedisError {
  let args : Array[Bytes] = [b"HSCAN", arg_string(key), arg_string(cursor)]
  push_some(args, b"MATCH", pattern.map(arg_string))
  push_some(args, b"COUNT", count.map(arg_int))
  let arr = expect_array(self.command(args))
  guard arr.length() >= 2 else { raise Protocol("unexpected HSCAN reply") }
  let next = @utf8.decode_lossy(expect_bytes(arr[0]).unwrap())
  let pairs = decode_pairs(expect_array(arr[1]))
  (next, pairs)
}

///|
/// `HRANDFIELD key [count] [WITHVALUES]`: one or more random fields, optionally with
/// their values.
pub async fn Client::hrandfield(
  self : Client,
  key : String,
  count? : Int32,
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"HRANDFIELD", arg_string(key)]
  match count {
    Some(n) => args.push(arg_int(n))
    None => ()
  }
  let items = expect_some(self.command(args))
  items.map(expect_string_value)
}

///|
/// `HRANDFIELD key count WITHVALUES`: random fields with their values. A negative `count` may
/// repeat a field.
pub async fn Client::hrandfield_values(
  self : Client,
  key : String,
  count : Int32,
) -> Array[(String, String)] raise RedisError {
  let args : Array[Bytes] = [
    b"HRANDFIELD",
    arg_string(key),
    arg_int(count),
    b"WITHVALUES",
  ]
  let items = expect_array(self.command(args))
  if items is [@resp.Array(_), ..] {
    return items.map(item => {
      guard item is @resp.Array([field, value]) else {
        raise Protocol("unexpected field/value pair")
      }
      (expect_string_value(field), expect_string_value(value))
    })
  }
  decode_pairs(items)
}

///|
/// Decode a flat array of alternating field, value into field/value pairs.
fn decode_pairs(
  items : Array[@resp.RespValue],
) -> Array[(String, String)] raise RedisError {
  let out : Array[(String, String)] = []
  for i = 0; i < items.length(); i = i + 2 {
    let field = @utf8.decode_lossy(expect_bytes(items[i]).unwrap())
    let value = @utf8.decode_lossy(expect_bytes(items[i + 1]).unwrap())
    out.push((field, value))
  }
  out
}
