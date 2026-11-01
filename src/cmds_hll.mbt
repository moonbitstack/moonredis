// The HyperLogLog commands, named as in redis-py: approximate cardinality of a set of
// values without storing them.

///|
/// `PFADD key value...`: register the values, returning 1 if the sketch changed.
pub async fn Client::pfadd(
  self : Client,
  key : String,
  values : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"PFADD", arg_string(key)]
  for v in values {
    args.push(arg_string(v))
  }
  expect_int64(self.command(args))
}

///|
/// `PFCOUNT key...`: the approximate cardinality of one key, or the union of several.
pub async fn Client::pfcount(
  self : Client,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"PFCOUNT"]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}

///|
/// `PFMERGE dest src...`: merge the source sketches into `dest`.
pub async fn Client::pfmerge(
  self : Client,
  destination : String,
  sources : Array[String],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"PFMERGE", arg_string(destination)]
  for s in sources {
    args.push(arg_string(s))
  }
  status_ok(self.command(args))
}
