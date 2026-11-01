// The bitmap commands, named as in redis-py. A bitmap is a sparse array of bits addressed
// by offset; these expose single-bit and range operations over them.

///|
/// `SETBIT key offset value`: set the bit at `offset` (0 or 1), returning its previous
/// value (0 or 1).
pub async fn Client::setbit(
  self : Client,
  key : String,
  offset : Int64,
  value : Int32,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([b"SETBIT", arg_string(key), arg_int64(offset), arg_int(value)]),
  )
}

///|
/// `GETBIT key offset`: the bit at `offset` (0 or 1).
pub async fn Client::getbit(
  self : Client,
  key : String,
  offset : Int64,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"GETBIT", arg_string(key), arg_int64(offset)]))
}

///|
/// `BITCOUNT key [start end]`: the number of set bits, optionally within a byte range.
pub async fn Client::bitcount(
  self : Client,
  key : String,
  start? : Int32,
  end? : Int32,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"BITCOUNT", arg_string(key)]
  match (start, end) {
    (Some(s), Some(e)) => {
      args.push(arg_int(s))
      args.push(arg_int(e))
    }
    _ => ()
  }
  expect_int64(self.command(args))
}

///|
/// `BITPOS key bit [start end]`: the first bit equal to `bit` (0 or 1), optionally within
/// a byte range. `-1` if none is found.
pub async fn Client::bitpos(
  self : Client,
  key : String,
  bit : Int32,
  start? : Int32,
  end? : Int32,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"BITPOS", arg_string(key), arg_int(bit)]
  match (start, end) {
    (Some(s), Some(e)) => {
      args.push(arg_int(s))
      args.push(arg_int(e))
    }
    _ => ()
  }
  expect_int64(self.command(args))
}

///|
/// `BITOP op dest key...`: store the bitwise `AND`/`OR`/`XOR` of the keys, or the `NOT`
/// of a single key, in `dest`, returning the result length in bytes.
pub async fn Client::bitop(
  self : Client,
  op : String,
  destination : String,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"BITOP", arg_string(op), arg_string(destination)]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}
