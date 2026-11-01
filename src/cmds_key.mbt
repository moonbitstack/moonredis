// The key commands, named as in redis-py. These operate on keys regardless of the value
// type they hold; the type-specific families live in their own files. Each method builds
// the argument array, sends it, and decodes the reply into the MoonBit type redis-py
// returns.

///|
/// `DEL key...`: delete the given keys, returning how many existed.
pub async fn Client::del(
  self : Client,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"DEL"]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}

///|
/// `UNLINK key...`: delete the given keys asynchronously, returning how many existed.
pub async fn Client::unlink(
  self : Client,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"UNLINK"]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}

///|
/// `EXISTS key...`: the number of the given keys that exist.
pub async fn Client::exists(
  self : Client,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"EXISTS"]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}

///|
/// `EXPIRE key secs`: set a `secs`-second expiry on `key`. `false` if the key is absent.
pub async fn Client::expire(
  self : Client,
  key : String,
  seconds : Int64,
) -> Bool raise RedisError {
  expect_bool(self.command([b"EXPIRE", arg_string(key), arg_int64(seconds)]))
}

///|
/// `PEXPIRE key ms`: set a `ms`-millisecond expiry on `key`. `false` if the key is absent.
pub async fn Client::pexpire(
  self : Client,
  key : String,
  milliseconds : Int64,
) -> Bool raise RedisError {
  expect_bool(
    self.command([b"PEXPIRE", arg_string(key), arg_int64(milliseconds)]),
  )
}

///|
/// `EXPIREAT key ts`: expire `key` at the given Unix second. `false` if the key is absent.
pub async fn Client::expireat(
  self : Client,
  key : String,
  timestamp : Int64,
) -> Bool raise RedisError {
  expect_bool(
    self.command([b"EXPIREAT", arg_string(key), arg_int64(timestamp)]),
  )
}

///|
/// `PEXPIREAT key ts`: expire `key` at the given Unix millisecond. `false` if absent.
pub async fn Client::pexpireat(
  self : Client,
  key : String,
  milliseconds_timestamp : Int64,
) -> Bool raise RedisError {
  expect_bool(
    self.command([
      b"PEXPIREAT",
      arg_string(key),
      arg_int64(milliseconds_timestamp),
    ]),
  )
}

///|
/// `PERSIST key`: remove `key`'s expiry. `true` if a TTL was removed.
pub async fn Client::persist(
  self : Client,
  key : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"PERSIST", arg_string(key)]))
}

///|
/// `TTL key`: `key`'s remaining time to live in seconds: `-2` if absent, `-1` if no
/// expiry, otherwise the seconds left.
pub async fn Client::ttl(self : Client, key : String) -> Int64 raise RedisError {
  expect_int64(self.command([b"TTL", arg_string(key)]))
}

///|
/// `PTTL key`: `key`'s remaining time to live in milliseconds.
pub async fn Client::pttl(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"PTTL", arg_string(key)]))
}

///|
/// `TYPE key`: the type stored at `key` (`string`, `list`, `set`, ...), or `none`.
pub async fn Client::type_(
  self : Client,
  key : String,
) -> String raise RedisError {
  expect_string_value(self.command([b"TYPE", arg_string(key)]))
}

///|
/// `RENAME key newkey`: rename `key` to `newkey`, replacing `newkey` if present.
pub async fn Client::rename(
  self : Client,
  key : String,
  newkey : String,
) -> Unit raise RedisError {
  status_ok(self.command([b"RENAME", arg_string(key), arg_string(newkey)]))
}

///|
/// `RENAMENX key newkey`: rename `key` to `newkey` only if `newkey` is absent.
/// `true` if renamed.
pub async fn Client::renamenx(
  self : Client,
  key : String,
  newkey : String,
) -> Bool raise RedisError {
  expect_bool(self.command([b"RENAMENX", arg_string(key), arg_string(newkey)]))
}

///|
/// `RANDOMKEY`: a random key from the database, or `None` when the database is empty.
pub async fn Client::randomkey(self : Client) -> String? raise RedisError {
  expect_string(self.command([b"RANDOMKEY"]))
}

///|
/// `TOUCH key...`: the number of the given keys that exist (like `EXISTS` but does not
/// alter the LRU/LFU, and accepts multiple keys).
pub async fn Client::touch(
  self : Client,
  keys : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"TOUCH"]
  for k in keys {
    args.push(arg_string(k))
  }
  expect_int64(self.command(args))
}

///|
/// `MOVE key db`: move `key` to another logical database. `true` if moved.
pub async fn Client::move_(
  self : Client,
  key : String,
  db : Int32,
) -> Bool raise RedisError {
  expect_bool(self.command([b"MOVE", arg_string(key), arg_int(db)]))
}

///|
/// `COPY source destination [DB n] [REPLACE]`: copy `source` to `destination`.
/// `true` if copied.
pub async fn Client::copy(
  self : Client,
  source : String,
  destination : String,
  db? : Int32,
  replace? : Bool,
) -> Bool raise RedisError {
  let args : Array[Bytes] = [
    b"COPY",
    arg_string(source),
    arg_string(destination),
  ]
  push_some(args, b"DB", db.map(arg_int))
  if replace.unwrap_or(false) {
    args.push(b"REPLACE")
  }
  expect_bool(self.command(args))
}

///|
/// `KEYS pattern`: every key matching `pattern`. Use `scan` in production.
pub async fn Client::keys(
  self : Client,
  pattern : String,
) -> Array[String] raise RedisError {
  let items = expect_array(self.command([b"KEYS", arg_string(pattern)]))
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}

///|
/// `SCAN cursor [MATCH pattern] [COUNT n] [TYPE kind]`: an incremental key scan. Returns
/// the next cursor (the empty string when the scan is done) and the keys found this call.
pub async fn Client::scan(
  self : Client,
  cursor : String,
  pattern? : String,
  count? : Int32,
  kind? : String,
) -> (String, Array[String]) raise RedisError {
  let args : Array[Bytes] = [b"SCAN", arg_string(cursor)]
  push_some(args, b"MATCH", pattern.map(arg_string))
  push_some(args, b"COUNT", count.map(arg_int))
  push_some(args, b"TYPE", kind.map(arg_string))
  let arr = expect_array(self.command(args))
  guard arr.length() >= 2 else { raise Protocol("unexpected SCAN reply") }
  let next = @utf8.decode_lossy(expect_bytes(arr[0]).unwrap())
  let keys_val = expect_array(arr[1])
  let keys = keys_val.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
  (next, keys)
}

///|
/// `OBJECT ENCODING key` / `OBJECT REFCOUNT key` / `OBJECT IDLETIME key`: inspect a key's
/// internal encoding, reference count, or idle time.
pub async fn Client::object_encoding(
  self : Client,
  key : String,
) -> String raise RedisError {
  expect_string_value(self.command([b"OBJECT", b"ENCODING", arg_string(key)]))
}

///|
pub async fn Client::object_refcount(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"OBJECT", b"REFCOUNT", arg_string(key)]))
}

///|
pub async fn Client::object_idletime(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"OBJECT", b"IDLETIME", arg_string(key)]))
}

///|
/// `DUMP key`: serialise `key`'s value to a binary dump, or `None` if the key is absent.
pub async fn Client::dump(
  self : Client,
  key : String,
) -> Bytes? raise RedisError {
  expect_bytes(self.command([b"DUMP", arg_string(key)]))
}

///|
/// `RESTORE key ttl serialized [REPLACE] [ABSTTL]`: restore a `DUMP` value at `key`
/// with a `ttl`-millisecond expiry (0 = no expiry).
pub async fn Client::restore(
  self : Client,
  key : String,
  ttl : Int64,
  serialized : Bytes,
  replace? : Bool,
  absttl? : Bool,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [
    b"RESTORE",
    arg_string(key),
    arg_int64(ttl),
    serialized,
  ]
  if replace.unwrap_or(false) {
    args.push(b"REPLACE")
  }
  if absttl.unwrap_or(false) {
    args.push(b"ABSTTL")
  }
  status_ok(self.command(args))
}
