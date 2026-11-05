// The two filter modules: a Bloom filter answers "definitely not, or probably yes" for the
// items it was built from, and a cuckoo filter answers the same while allowing deletes.
// Both report a member test as `1`/`0` under RESP2 and as `#t`/`#f` under RESP3, and both
// can dump themselves chunk by chunk for a backup.
// https://redis.io/docs/latest/commands/?group=bf
// https://redis.io/docs/latest/commands/?group=cf

///|
/// `BF.RESERVE key error_rate capacity [EXPANSION expansion] [NONSCALING]`: create a Bloom
/// filter sized for `capacity` items at `error_rate` false positives. A filter that grows
/// keeps its rate by adding sub-filters of `expansion` times the capacity; `nonscaling`
/// fixes it at the initial size and starts refusing items when full.
pub async fn Client::bf_reserve(
  self : Client,
  key : String,
  error_rate : Double,
  capacity : Int64,
  expansion? : Int64,
  nonscaling? : Bool,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [
    b"BF.RESERVE",
    arg_string(key),
    arg_double(error_rate),
    arg_int64(capacity),
  ]
  push_some(args, b"EXPANSION", expansion.map(arg_int64))
  if nonscaling.unwrap_or(false) {
    args.push(b"NONSCALING")
  }
  status_ok(self.command(args))
}

///|
/// `BF.ADD key item`: add an item, returning whether the filter changed — false when it
/// probably held the item already.
pub async fn Client::bf_add(
  self : Client,
  key : String,
  item : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"BF.ADD", arg_string(key), arg_string(item)]))
}

///|
/// `BF.MADD key item [item ...]`: add items, one flag each.
pub async fn Client::bf_madd(
  self : Client,
  key : String,
  items : Array[String],
) -> Array[Bool] raise RedisError {
  let args : Array[Bytes] = [b"BF.MADD", arg_string(key)]
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_bool)
}

///|
/// `BF.INSERT key [CAPACITY n] [ERROR rate] [EXPANSION n] [NOCREATE] [NONSCALING] ITEMS
/// item...`: add items, creating the filter from these parameters when it does not exist.
pub async fn Client::bf_insert(
  self : Client,
  key : String,
  items : Array[String],
  capacity? : Int64,
  error_rate? : Double,
  expansion? : Int64,
  nocreate? : Bool,
  nonscaling? : Bool,
) -> Array[Bool] raise RedisError {
  let args : Array[Bytes] = [b"BF.INSERT", arg_string(key)]
  push_some(args, b"CAPACITY", capacity.map(arg_int64))
  push_some(args, b"ERROR", error_rate.map(arg_double))
  push_some(args, b"EXPANSION", expansion.map(arg_int64))
  if nocreate.unwrap_or(false) {
    args.push(b"NOCREATE")
  }
  if nonscaling.unwrap_or(false) {
    args.push(b"NONSCALING")
  }
  args.push(b"ITEMS")
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_bool)
}

///|
/// `BF.EXISTS key item`: whether the filter probably holds the item.
pub async fn Client::bf_exists(
  self : Client,
  key : String,
  item : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"BF.EXISTS", arg_string(key), arg_string(item)]))
}

///|
/// `BF.MEXISTS key item [item ...]`: one answer per item.
pub async fn Client::bf_mexists(
  self : Client,
  key : String,
  items : Array[String],
) -> Array[Bool] raise RedisError {
  let args : Array[Bytes] = [b"BF.MEXISTS", arg_string(key)]
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_bool)
}

///|
/// `BF.SCANDUMP key iterator`: the next chunk of a serialized filter, and the iterator to
/// ask for the one after it. Iteration ends when the iterator comes back as 0.
pub async fn Client::bf_scandump(
  self : Client,
  key : String,
  iterator : Int64,
) -> (Int64, Bytes?) raise RedisError {
  let parts = expect_array(
    self.command([b"BF.SCANDUMP", arg_string(key), arg_int64(iterator)]),
  )
  guard parts.length() >= 2 else {
    raise Protocol("unexpected BF.SCANDUMP reply")
  }
  (expect_int64(parts[0]), expect_bytes(parts[1]))
}

///|
/// `BF.LOADCHUNK key iterator data`: restore one chunk of a serialized filter.
pub async fn Client::bf_loadchunk(
  self : Client,
  key : String,
  iterator : Int64,
  data : Bytes,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"BF.LOADCHUNK", arg_string(key), arg_int64(iterator), data]),
  )
}

///|
/// `BF.INFO key`: capacity, memory and item counts.
pub async fn Client::bf_info(
  self : Client,
  key : String,
) -> Info raise RedisError {
  decode_info(self.command([b"BF.INFO", arg_string(key)]))
}

///|
/// `BF.CARD key`: how many items were added, duplicates included.
pub async fn Client::bf_card(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"BF.CARD", arg_string(key)]))
}

///|
/// `CF.RESERVE key capacity [BUCKETSIZE n] [MAXITERATIONS n] [EXPANSION n]`: create a
/// cuckoo filter for `capacity` items.
pub async fn Client::cf_reserve(
  self : Client,
  key : String,
  capacity : Int64,
  bucket_size? : Int64,
  max_iterations? : Int64,
  expansion? : Int64,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [
    b"CF.RESERVE",
    arg_string(key),
    arg_int64(capacity),
  ]
  push_some(args, b"BUCKETSIZE", bucket_size.map(arg_int64))
  push_some(args, b"MAXITERATIONS", max_iterations.map(arg_int64))
  push_some(args, b"EXPANSION", expansion.map(arg_int64))
  status_ok(self.command(args))
}

///|
/// `CF.ADD key item`: add an item, returning whether it was added.
pub async fn Client::cf_add(
  self : Client,
  key : String,
  item : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"CF.ADD", arg_string(key), arg_string(item)]))
}

///|
/// `CF.ADDNX key item`: add an item only if the filter does not hold it yet.
pub async fn Client::cf_addnx(
  self : Client,
  key : String,
  item : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"CF.ADDNX", arg_string(key), arg_string(item)]))
}

///|
/// `CF.INSERT key [CAPACITY n] [NOCREATE] ITEMS item...`: add items, creating the filter
/// when it does not exist.
pub async fn Client::cf_insert(
  self : Client,
  key : String,
  items : Array[String],
  capacity? : Int64,
  nocreate? : Bool,
) -> Array[Bool] raise RedisError {
  let args : Array[Bytes] = [b"CF.INSERT", arg_string(key)]
  push_some(args, b"CAPACITY", capacity.map(arg_int64))
  if nocreate.unwrap_or(false) {
    args.push(b"NOCREATE")
  }
  args.push(b"ITEMS")
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_bool)
}

///|
/// `CF.INSERTNX key [CAPACITY n] [NOCREATE] ITEMS item...`: add the items the filter does
/// not hold yet.
pub async fn Client::cf_insertnx(
  self : Client,
  key : String,
  items : Array[String],
  capacity? : Int64,
  nocreate? : Bool,
) -> Array[Bool] raise RedisError {
  let args : Array[Bytes] = [b"CF.INSERTNX", arg_string(key)]
  push_some(args, b"CAPACITY", capacity.map(arg_int64))
  if nocreate.unwrap_or(false) {
    args.push(b"NOCREATE")
  }
  args.push(b"ITEMS")
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_bool)
}

///|
/// `CF.EXISTS key item`: whether the filter probably holds the item.
pub async fn Client::cf_exists(
  self : Client,
  key : String,
  item : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"CF.EXISTS", arg_string(key), arg_string(item)]))
}

///|
/// `CF.MEXISTS key item [item ...]`: one answer per item.
pub async fn Client::cf_mexists(
  self : Client,
  key : String,
  items : Array[String],
) -> Array[Bool] raise RedisError {
  let args : Array[Bytes] = [b"CF.MEXISTS", arg_string(key)]
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_bool)
}

///|
/// `CF.DEL key item`: remove one occurrence of an item. True if it was there.
pub async fn Client::cf_del(
  self : Client,
  key : String,
  item : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"CF.DEL", arg_string(key), arg_string(item)]))
}

///|
/// `CF.COUNT key item`: how many times the item was added.
pub async fn Client::cf_count(
  self : Client,
  key : String,
  item : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"CF.COUNT", arg_string(key), arg_string(item)]))
}

///|
/// `CF.SCANDUMP key iterator`: the next chunk of a serialized filter, and the iterator for
/// the one after it.
pub async fn Client::cf_scandump(
  self : Client,
  key : String,
  iterator : Int64,
) -> (Int64, Bytes?) raise RedisError {
  let parts = expect_array(
    self.command([b"CF.SCANDUMP", arg_string(key), arg_int64(iterator)]),
  )
  guard parts.length() >= 2 else {
    raise Protocol("unexpected CF.SCANDUMP reply")
  }
  (expect_int64(parts[0]), expect_bytes(parts[1]))
}

///|
/// `CF.LOADCHUNK key iterator data`: restore one chunk of a serialized filter.
pub async fn Client::cf_loadchunk(
  self : Client,
  key : String,
  iterator : Int64,
  data : Bytes,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"CF.LOADCHUNK", arg_string(key), arg_int64(iterator), data]),
  )
}

///|
/// `CF.INFO key`: size, buckets and item counts.
pub async fn Client::cf_info(
  self : Client,
  key : String,
) -> Info raise RedisError {
  decode_info(self.command([b"CF.INFO", arg_string(key)]))
}
