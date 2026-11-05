// The JSON commands. A key holds one JSON document, and a JSONPath addresses a part of it:
// `$` is the document root, `$.a.b` a member, `$..x` a recursive match. Values cross the
// wire as JSON text, so a value is a `Json` here and the raw text stays available for the
// calls where formatting or exact bytes matter.
// https://redis.io/docs/latest/commands/?group=json

///|
/// The float array storage `JSON.SET` may be told to use: `FPHA BF16`, `FP16`, `FP32` or
/// `FP64`.
#derive(Eq, Debug)
pub(all) enum Fpha {
  Bf16
  Fp16
  Fp32
  Fp64
}

///|
pub extend Fpha with Debug::{to_repr}

///|
pub extend Fpha with Eq::{not_equal, equal}

///|
/// The keyword `FPHA` takes for this storage.
pub fn Fpha::text(self : Fpha) -> String {
  match self {
    Bf16 => "BF16"
    Fp16 => "FP16"
    Fp32 => "FP32"
    Fp64 => "FP64"
  }
}

///|
/// Parse the JSON text a JSON command answers with.
fn parse_json_text(text : String) -> @json.Json raise RedisError {
  @json.parse(text[:]) catch {
    _ => raise Protocol("JSON reply is not valid JSON: " + text)
  }
}

///|
/// A JSON command's reply as a `Json`, whatever shape it arrived in: RESP2 writes a value
/// as JSON text, RESP3 as a typed value or an array of them.
fn json_reply_value(reply : @resp.RespValue) -> @json.Json raise RedisError {
  match reply {
    @resp.BulkString(b) | @resp.VerbatimString(_, b) =>
      parse_json_text(@utf8.decode_lossy(b[:]))
    @resp.SimpleString(s) => parse_json_text(s)
    @resp.Null => @json.Json::null()
    @resp.Integer(n) => @json.Json::number(n.to_double(), repr=n.to_string())
    @resp.Double(d) => @json.Json::number(d)
    @resp.Boolean(b) => @json.Json::boolean(b)
    @resp.Array(items) => @json.Json::array(items.map(json_reply_value))
    @resp.RespSet(items) => @json.Json::array(items.map(json_reply_value))
    @resp.RespMap(pairs) => {
      let fields : Map[String, @json.Json] = Map([])
      for pair in pairs {
        fields[expect_text(pair.0)] = json_reply_value(pair.1)
      }
      @json.Json::object(fields)
    }
    other =>
      raise Protocol("expected a JSON value, got " + @resp.resp_kind(other))
  }
}

///|
/// A JSON number, or `None` for a null the server wrote for a path that matched nothing.
fn json_number(value : @json.Json) -> Double? {
  match value {
    @json.Number(d, ..) => Some(d)
    _ => None
  }
}

///|
/// The items of a path-addressed reply, as numbers.
fn path_numbers(reply : @resp.RespValue) -> Array[Double?] raise RedisError {
  match reply {
    @resp.BulkString(b) | @resp.VerbatimString(_, b) => {
      let parsed = parse_json_text(@utf8.decode_lossy(b[:]))
      match parsed {
        @json.Array(items) => items.map(json_number)
        other => [json_number(other)]
      }
    }
    other => path_items(other).map(item => json_number(json_reply_value(item)))
  }
}

///|
/// The items of a path-addressed reply, as integers.
fn path_ints(reply : @resp.RespValue) -> Array[Int64?] raise RedisError {
  let out : Array[Int64?] = []
  for item in path_items(reply) {
    match item {
      @resp.Null => out.push(None)
      @resp.Integer(n) => out.push(Some(n))
      @resp.Boolean(b) => out.push(Some(if b { 1 } else { 0 }))
      other => out.push(Some(expect_int64(other)))
    }
  }
  out
}

///|
/// The items of a path-addressed reply, as booleans.
fn path_flags(reply : @resp.RespValue) -> Array[Bool?] raise RedisError {
  let out : Array[Bool?] = []
  for item in path_items(reply) {
    match item {
      @resp.Null => out.push(None)
      other => out.push(Some(expect_bool(other)))
    }
  }
  out
}

///|
/// `JSON.SET key path value [NX|XX] [FPHA type]`: store `value` at `path` in `key`.
/// Returns `false` when `nx` or `xx` leaves the key unchanged.
pub async fn Client::json_set(
  self : Client,
  key : String,
  path : String,
  value : @json.Json,
  nx? : Bool,
  xx? : Bool,
  fpha? : Fpha,
) -> Bool raise RedisError {
  let args : Array[Bytes] = [
    b"JSON.SET",
    arg_string(key),
    arg_string(path),
    arg_string(value.stringify()),
  ]
  if nx.unwrap_or(false) {
    args.push(b"NX")
  } else if xx.unwrap_or(false) {
    args.push(b"XX")
  }
  push_some(args, b"FPHA", fpha.map(f => arg_string(f.text())))
  match self.command(args) {
    @resp.SimpleString(_) => true
    @resp.Null => false
    other =>
      raise Protocol("unexpected JSON.SET reply: " + @resp.resp_kind(other))
  }
}

///|
/// `JSON.MSET key path value [key path value ...]`: set several documents at once, all or
/// none.
pub async fn Client::json_mset(
  self : Client,
  triplets : Array[(String, String, @json.Json)],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"JSON.MSET"]
  for (key, path, value) in triplets {
    args.push(arg_string(key))
    args.push(arg_string(path))
    args.push(arg_string(value.stringify()))
  }
  status_ok(self.command(args))
}

///|
/// `JSON.MERGE key path value`: merge `value` into the object at `path`, by RFC 7396: a
/// null member removes the member, an object merges recursively, anything else replaces.
pub async fn Client::json_merge(
  self : Client,
  key : String,
  path : String,
  value : @json.Json,
) -> Unit raise RedisError {
  status_ok(
    self.command([
      b"JSON.MERGE",
      arg_string(key),
      arg_string(path),
      arg_string(value.stringify()),
    ]),
  )
}

///|
/// `JSON.GET key [path]`: the document, or the part of it at `path`, or `None` when the key
/// is missing. A JSONPath that matches nothing yields an empty array, which is not `None`.
pub async fn Client::json_get(
  self : Client,
  key : String,
  path? : String,
) -> @json.Json? raise RedisError {
  let args : Array[Bytes] = [b"JSON.GET", arg_string(key)]
  push_arg(args, path.map(arg_string))
  match self.command(args) {
    @resp.Null => None
    other => Some(json_reply_value(other))
  }
}

///|
/// `JSON.GET key [INDENT i] [NEWLINE n] [SPACE s] [path]`: the reply exactly as the server
/// wrote it, formatting included.
pub async fn Client::json_get_text(
  self : Client,
  key : String,
  path? : String,
  indent? : String,
  newline? : String,
  space? : String,
) -> String? raise RedisError {
  let args : Array[Bytes] = [b"JSON.GET", arg_string(key)]
  push_some(args, b"INDENT", indent.map(arg_string))
  push_some(args, b"NEWLINE", newline.map(arg_string))
  push_some(args, b"SPACE", space.map(arg_string))
  push_arg(args, path.map(arg_string))
  match self.command(args) {
    @resp.Null => None
    other => Some(expect_text(other))
  }
}

///|
/// `JSON.MGET key [key ...] path`: the value at `path` in each key, `None` where a key has
/// nothing there.
pub async fn Client::json_mget(
  self : Client,
  keys : Array[String],
  path : String,
) -> Array[@json.Json?] raise RedisError {
  let args : Array[Bytes] = [b"JSON.MGET"]
  for key in keys {
    args.push(arg_string(key))
  }
  args.push(arg_string(path))
  let out : Array[@json.Json?] = []
  for item in expect_array(self.command(args)) {
    match item {
      @resp.Null => out.push(None)
      other => out.push(Some(json_reply_value(other)))
    }
  }
  out
}

///|
/// `JSON.DEL key [path]`: delete the document or the part at `path`, returning how many
/// values were removed.
pub async fn Client::json_del(
  self : Client,
  key : String,
  path? : String,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"JSON.DEL", arg_string(key)]
  push_arg(args, path.map(arg_string))
  expect_int64(self.command(args))
}

///|
/// `JSON.FORGET key [path]`: the older name for `JSON.DEL`.
pub async fn Client::json_forget(
  self : Client,
  key : String,
  path? : String,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"JSON.FORGET", arg_string(key)]
  push_arg(args, path.map(arg_string))
  expect_int64(self.command(args))
}

///|
/// `JSON.TYPE key [path]`: the JSON type of each value at `path` — `object`, `array`,
/// `string`, `integer`, `number`, `boolean` or `null` — `None` where nothing matched.
pub async fn Client::json_type(
  self : Client,
  key : String,
  path? : String,
) -> Array[String?] raise RedisError {
  let args : Array[Bytes] = [b"JSON.TYPE", arg_string(key)]
  push_arg(args, path.map(arg_string))
  let out : Array[String?] = []
  for item in path_items(self.command(args)) {
    match item {
      // RESP3 nests one array per path, so a path with several matches arrives one level
      // deeper than the same reply does under RESP2.
      @resp.Array(inner) =>
        for value in inner {
          match value {
            @resp.Null => out.push(None)
            other => out.push(Some(expect_text(other)))
          }
        }
      @resp.Null => out.push(None)
      other => out.push(Some(expect_text(other)))
    }
  }
  out
}

///|
/// `JSON.NUMINCRBY key path value`: add `value` to each number at `path`, returning the new
/// values.
pub async fn Client::json_numincrby(
  self : Client,
  key : String,
  path : String,
  value : Double,
) -> Array[Double?] raise RedisError {
  path_numbers(
    self.command([
      b"JSON.NUMINCRBY",
      arg_string(key),
      arg_string(path),
      arg_double(value),
    ]),
  )
}

///|
/// `JSON.NUMMULTBY key path value`: multiply each number at `path` by `value`, returning
/// the new values.
pub async fn Client::json_nummultby(
  self : Client,
  key : String,
  path : String,
  value : Double,
) -> Array[Double?] raise RedisError {
  path_numbers(
    self.command([
      b"JSON.NUMMULTBY",
      arg_string(key),
      arg_string(path),
      arg_double(value),
    ]),
  )
}

///|
/// `JSON.STRAPPEND key [path] value`: append `value`, a JSON string, to each string at
/// `path`, returning the new lengths.
pub async fn Client::json_strappend(
  self : Client,
  key : String,
  path : String,
  value : String,
) -> Array[Int64?] raise RedisError {
  path_ints(
    self.command([
      b"JSON.STRAPPEND",
      arg_string(key),
      arg_string(path),
      arg_string(@json.Json::string(value).stringify()),
    ]),
  )
}

///|
/// `JSON.STRLEN key [path]`: the length of each string at `path`.
pub async fn Client::json_strlen(
  self : Client,
  key : String,
  path? : String,
) -> Array[Int64?] raise RedisError {
  let args : Array[Bytes] = [b"JSON.STRLEN", arg_string(key)]
  push_arg(args, path.map(arg_string))
  path_ints(self.command(args))
}

///|
/// `JSON.ARRLEN key [path]`: the length of each array at `path`.
pub async fn Client::json_arrlen(
  self : Client,
  key : String,
  path? : String,
) -> Array[Int64?] raise RedisError {
  let args : Array[Bytes] = [b"JSON.ARRLEN", arg_string(key)]
  push_arg(args, path.map(arg_string))
  path_ints(self.command(args))
}

///|
/// `JSON.ARRINDEX key path value [START start] [STOP stop]`: the first position of `value`
/// in each array at `path`, `-1` when absent.
pub async fn Client::json_arrindex(
  self : Client,
  key : String,
  path : String,
  value : @json.Json,
  start? : Int64,
  stop? : Int64,
) -> Array[Int64?] raise RedisError {
  let args : Array[Bytes] = [
    b"JSON.ARRINDEX",
    arg_string(key),
    arg_string(path),
    arg_string(value.stringify()),
  ]
  push_some(args, b"START", start.map(arg_int64))
  push_some(args, b"STOP", stop.map(arg_int64))
  path_ints(self.command(args))
}

///|
/// `JSON.ARRAPPEND key path value [value ...]`: append the values to each array at `path`,
/// returning the new lengths.
pub async fn Client::json_arrappend(
  self : Client,
  key : String,
  path : String,
  values : Array[@json.Json],
) -> Array[Int64?] raise RedisError {
  let args : Array[Bytes] = [
    b"JSON.ARRAPPEND",
    arg_string(key),
    arg_string(path),
  ]
  for value in values {
    args.push(arg_string(value.stringify()))
  }
  path_ints(self.command(args))
}

///|
/// `JSON.ARRINSERT key path index value [value ...]`: insert the values at `index` in each
/// array at `path`, returning the new lengths.
pub async fn Client::json_arrinsert(
  self : Client,
  key : String,
  path : String,
  index : Int64,
  values : Array[@json.Json],
) -> Array[Int64?] raise RedisError {
  let args : Array[Bytes] = [
    b"JSON.ARRINSERT",
    arg_string(key),
    arg_string(path),
    arg_int64(index),
  ]
  for value in values {
    args.push(arg_string(value.stringify()))
  }
  path_ints(self.command(args))
}

///|
/// `JSON.ARRPOP key [path] [index]`: pop an element from each array at `path`, `index` -1
/// being the last, returning the popped values.
pub async fn Client::json_arrpop(
  self : Client,
  key : String,
  path : String,
  index? : Int64,
) -> Array[@json.Json?] raise RedisError {
  let args : Array[Bytes] = [b"JSON.ARRPOP", arg_string(key), arg_string(path)]
  push_arg(args, index.map(arg_int64))
  let out : Array[@json.Json?] = []
  for item in path_items(self.command(args)) {
    match item {
      @resp.Null => out.push(None)
      other => out.push(Some(json_reply_value(other)))
    }
  }
  out
}

///|
/// `JSON.ARRTRIM key path start stop`: trim each array at `path` to the inclusive range,
/// returning the new lengths.
pub async fn Client::json_arrtrim(
  self : Client,
  key : String,
  path : String,
  start : Int64,
  stop : Int64,
) -> Array[Int64?] raise RedisError {
  path_ints(
    self.command([
      b"JSON.ARRTRIM",
      arg_string(key),
      arg_string(path),
      arg_int64(start),
      arg_int64(stop),
    ]),
  )
}

///|
/// `JSON.OBJKEYS key [path]`: the member names of each object at `path`.
pub async fn Client::json_objkeys(
  self : Client,
  key : String,
  path? : String,
) -> Array[Array[String]?] raise RedisError {
  let args : Array[Bytes] = [b"JSON.OBJKEYS", arg_string(key)]
  push_arg(args, path.map(arg_string))
  let out : Array[Array[String]?] = []
  for item in path_items(self.command(args)) {
    match item {
      @resp.Null => out.push(None)
      other => out.push(Some(expect_text_list(other)))
    }
  }
  out
}

///|
/// `JSON.OBJLEN key [path]`: the number of members of each object at `path`.
pub async fn Client::json_objlen(
  self : Client,
  key : String,
  path? : String,
) -> Array[Int64?] raise RedisError {
  let args : Array[Bytes] = [b"JSON.OBJLEN", arg_string(key)]
  push_arg(args, path.map(arg_string))
  path_ints(self.command(args))
}

///|
/// `JSON.TOGGLE key path`: flip each boolean at `path`, returning the new values.
pub async fn Client::json_toggle(
  self : Client,
  key : String,
  path : String,
) -> Array[Bool?] raise RedisError {
  path_flags(self.command([b"JSON.TOGGLE", arg_string(key), arg_string(path)]))
}

///|
/// `JSON.CLEAR key [path]`: empty the arrays and objects at `path`, returning how many
/// values were cleared.
pub async fn Client::json_clear(
  self : Client,
  key : String,
  path? : String,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"JSON.CLEAR", arg_string(key)]
  push_arg(args, path.map(arg_string))
  expect_int64(self.command(args))
}

///|
/// `JSON.RESP key [path]`: the value as RESP itself, with `[` and `{` markers for arrays
/// and objects. It is the one JSON command whose reply is not a JSON document.
pub async fn Client::json_resp(
  self : Client,
  key : String,
  path? : String,
) -> @resp.RespValue raise RedisError {
  let args : Array[Bytes] = [b"JSON.RESP", arg_string(key)]
  push_arg(args, path.map(arg_string))
  self.command(args)
}

///|
/// `JSON.DEBUG MEMORY key [path]`: the bytes the value at `path` occupies.
pub async fn Client::json_debug_memory(
  self : Client,
  key : String,
  path? : String,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"JSON.DEBUG", b"MEMORY", arg_string(key)]
  push_arg(args, path.map(arg_string))
  expect_int64(self.command(args))
}
