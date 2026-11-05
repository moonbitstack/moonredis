// Shared pieces for the commands Redis 8 serves from its built-in modules: the scalar
// values an `INFO` reply holds, and the small conversions the module replies need because
// they differ between RESP2 and RESP3 (a flag is `:1` on one wire and `#t` on the other, a
// value is a string on one and a double on the other).

///|
/// One value in a module's `INFO` reply: the four shapes those replies use. A key the
/// server did not report reads as `Missing` rather than raising, because the set of keys
/// grows between versions.
#derive(Eq, Debug)
pub(all) enum InfoValue {
  Text(String)
  Number(Double)
  Flag(Bool)
  Missing
}

///|
pub extend InfoValue with Debug::{to_repr}

///|
pub extend InfoValue with Eq::{not_equal, equal}

///|
/// The name/value pairs an `INFO` reply holds, looked up by name. Redis answers these with
/// a flat array under RESP2 and a map under RESP3; both come back as this.
pub(all) struct Info {
  items : Map[String, InfoValue]
}

///|
/// The value stored under `name`, or `Missing`.
pub fn Info::get(self : Info, name : String) -> InfoValue {
  match self.items.get(name) {
    Some(v) => v
    None => Missing
  }
}

///|
/// The value under `name` as an integer, or `None` when it is not a whole number.
pub fn Info::int(self : Info, name : String) -> Int64? {
  match self.get(name) {
    Number(d) => Some(d.to_int64())
    Text(t) => {
      let n = @string.parse_int64(t) catch { _ => return None }
      Some(n)
    }
    _ => None
  }
}

///|
/// The value under `name` as a double, accepting a number or its decimal text.
pub fn Info::double(self : Info, name : String) -> Double? {
  match self.get(name) {
    Number(d) => Some(d)
    Text(t) => {
      let d = @string.parse_double(t) catch { _ => return None }
      Some(d)
    }
    _ => None
  }
}

///|
/// The value under `name` as text.
pub fn Info::text(self : Info, name : String) -> String? {
  match self.get(name) {
    Text(t) => Some(t)
    _ => None
  }
}

///|
/// The value under `name` as a flag.
pub fn Info::flag(self : Info, name : String) -> Bool? {
  match self.get(name) {
    Flag(b) => Some(b)
    _ => None
  }
}

///|
/// A module `INFO` reply as an `Info`. The RESP3 map is read directly; the RESP2 flat
/// array is read pairwise, which is how every module writes it.
pub fn decode_info(reply : @resp.RespValue) -> Info raise RedisError {
  let items : Map[String, InfoValue] = Map([])
  match reply {
    @resp.RespMap(pairs) =>
      for pair in pairs {
        items[expect_text(pair.0)] = info_scalar(pair.1)
      }
    @resp.Array(values) => {
      guard values.length() % 2 == 0 else {
        raise Protocol("INFO reply has an odd number of items")
      }
      for at in 0..<(values.length() / 2) {
        items[expect_text(values[at * 2])] = info_scalar(values[at * 2 + 1])
      }
    }
    other =>
      raise Protocol("expected INFO reply, got " + @resp.resp_kind(other))
  }
  { items, }
}

///|
/// One value of an `INFO` reply: a scalar, a flag, or a null the server left empty.
pub fn info_scalar(reply : @resp.RespValue) -> InfoValue {
  match reply {
    @resp.Integer(n) => Number(n.to_double())
    @resp.Double(d) => Number(d)
    @resp.Boolean(b) => Flag(b)
    @resp.SimpleString(s) => Text(s)
    @resp.BulkString(b) => Text(@utf8.decode_lossy(b[:]))
    @resp.VerbatimString(_, b) => Text(@utf8.decode_lossy(b[:]))
    @resp.Null => Missing
    _ => Missing
  }
}

///|
/// A reply as text: a bulk string, a simple string, or a verbatim string. A module returns
/// numbers as text on RESP2, so a call that wants the written form goes through here.
pub fn expect_text(reply : @resp.RespValue) -> String raise RedisError {
  match reply {
    @resp.BulkString(b) => @utf8.decode_lossy(b[:])
    @resp.SimpleString(s) => s
    @resp.VerbatimString(_, b) => @utf8.decode_lossy(b[:])
    other => raise Protocol("expected text, got " + @resp.resp_kind(other))
  }
}

///|
/// A reply that is one value or an array of one, as the items of an array. JSONPath
/// commands answer with an array, the older single-path form with a bare value, and RESP3
/// adds a wrapper of its own; callers want neither detail.
pub fn path_items(reply : @resp.RespValue) -> Array[@resp.RespValue] {
  match reply {
    @resp.Array(items) => items
    @resp.Null => []
    other => [other]
  }
}

///|
/// A reply of name/value pairs: the map RESP3 sends, or the flat array RESP2 sends.
fn field_pairs(
  reply : @resp.RespValue,
) -> Array[(String, @resp.RespValue)] raise RedisError {
  match reply {
    @resp.RespMap(pairs) => {
      let out : Array[(String, @resp.RespValue)] = []
      for (key, value) in pairs {
        out.push((expect_text(key), value))
      }
      out
    }
    other => {
      let flat = expect_array(other)
      let out : Array[(String, @resp.RespValue)] = []
      guard flat.length() % 2 == 0 else {
        raise Protocol("expected name/value pairs")
      }
      for at in 0..<(flat.length() / 2) {
        out.push((expect_text(flat[at * 2]), flat[at * 2 + 1]))
      }
      out
    }
  }
}

///|
/// A list of text, from an array or the set RESP3 answers `TS.QUERYINDEX` with.
pub fn expect_text_list(
  reply : @resp.RespValue,
) -> Array[String] raise RedisError {
  expect_array(reply).map(expect_text)
}

///|
/// A numeric reply: a double, an integer, or the decimal text RESP2 writes. A module that
/// has no value to report writes `nan`, which arrives as `NaN` here.
pub fn numeric_value(reply : @resp.RespValue) -> Double {
  match reply {
    @resp.Double(d) => d
    @resp.Integer(n) => n.to_double()
    @resp.SimpleString(s) => parse_number_text(s)
    @resp.BulkString(b) => parse_number_text(@utf8.decode_lossy(b[:]))
    _ => @double.not_a_number
  }
}

///|
/// Text as a number, or `NaN` when it is not one.
fn parse_number_text(text : String) -> Double {
  @string.parse_double(text) catch {
    _ => @double.not_a_number
  }
}

///|
/// Append a positional argument that the caller may leave out, without a keyword in front
/// of it.
fn push_arg(args : Array[Bytes], value : Bytes?) -> Unit {
  match value {
    Some(v) => args.push(v)
    None => ()
  }
}
