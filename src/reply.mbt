// The bridge from a decoded `RespValue` to the MoonBit type a typed command promises.
// Every helper raises `RedisError::Protocol` when the reply is not the shape the command
// documented, so a caller that asked for an integer gets an integer or a precise error.

///|
/// Assert a status reply (the `+OK` most write commands return). Any other shape is a
/// protocol error.
pub fn status_ok(reply : @resp.RespValue) -> Unit raise RedisError {
  match reply {
    @resp.SimpleString(_) => ()
    other => raise Protocol("expected status, got " + @resp.resp_kind(other))
  }
}

///|
/// A reply as an `Int64`: an integer value, or the `+1`/`-1` a command aliases to.
pub fn expect_int64(reply : @resp.RespValue) -> Int64 raise RedisError {
  match reply {
    @resp.Integer(n) => n
    other => raise Protocol("expected integer, got " + @resp.resp_kind(other))
  }
}

///|
/// A number redis writes as text: `TIME`, and the ports and counts of sentinel and stream
/// replies, come back as strings under both protocols.
pub fn expect_number(reply : @resp.RespValue) -> Int64 raise RedisError {
  match reply {
    @resp.Integer(n) => n
    @resp.BulkString(b) =>
      @string.parse_int64(@utf8.decode_lossy(b[:])) catch {
        _ => raise Protocol("expected a number, got bulk")
      }
    other => raise Protocol("expected a number, got " + @resp.resp_kind(other))
  }
}

///|
/// The members of a reply that is one bulk value without a count and an array with one, and
/// nothing when the key is missing.
pub fn expect_some(
  reply : @resp.RespValue,
) -> Array[@resp.RespValue] raise RedisError {
  match reply {
    @resp.BulkString(_) | @resp.SimpleString(_) => [reply]
    other => expect_array(other)
  }
}

///|
/// A reply as a `Bool`: the `1`/`0` redis uses for existence, success and comparison, or
/// the boolean RESP3 sends for the same answer.
pub fn expect_bool(reply : @resp.RespValue) -> Bool raise RedisError {
  match reply {
    @resp.Integer(n) => n != 0
    @resp.Boolean(b) => b
    other =>
      raise Protocol("expected integer 0/1, got " + @resp.resp_kind(other))
  }
}

///|
/// A reply as binary bytes, or `None` for the nil a missing key decodes to.
pub fn expect_bytes(reply : @resp.RespValue) -> Bytes? raise RedisError {
  match reply {
    @resp.BulkString(b) | @resp.VerbatimString(_, b) => Some(b)
    @resp.Null => None
    other =>
      raise Protocol("expected bulk string, got " + @resp.resp_kind(other))
  }
}

///|
/// A reply as a `String`, or `None` for nil.
pub fn expect_string(reply : @resp.RespValue) -> String? raise RedisError {
  match reply {
    @resp.BulkString(b) | @resp.VerbatimString(_, b) =>
      Some(@utf8.decode_lossy(b[:]))
    @resp.SimpleString(s) => Some(s)
    @resp.Null => None
    other => raise Protocol("expected string, got " + @resp.resp_kind(other))
  }
}

///|
/// A reply as a `String`, raising on nil (for commands that always return a value).
pub fn expect_string_value(reply : @resp.RespValue) -> String raise RedisError {
  match expect_string(reply) {
    Some(s) => s
    None => raise Protocol("expected string, got null")
  }
}

///|
/// A reply as an `Array[RespValue]`: an array, or the nil an empty result decodes to.
pub fn expect_array(
  reply : @resp.RespValue,
) -> Array[@resp.RespValue] raise RedisError {
  match reply {
    @resp.Array(items) | @resp.RespSet(items) | @resp.Push(items) => items
    // RESP3 answers HGETALL and its kin with a map where RESP2 had a flat array.
    @resp.RespMap(pairs) => {
      let out = []
      for pair in pairs {
        out.push(pair.0)
        out.push(pair.1)
      }
      out
    }
    @resp.Null => []
    other => raise Protocol("expected array, got " + @resp.resp_kind(other))
  }
}

///|
/// A reply as a `Double`: a double, the integer a score may come back as, or a parsed
/// decimal string.
pub fn expect_double(reply : @resp.RespValue) -> Double raise RedisError {
  match reply {
    @resp.Double(d) => d
    @resp.Integer(n) => n.to_double()
    @resp.SimpleString(s) =>
      @string.parse_double(s) catch {
        _ => raise Protocol("expected double, got " + s)
      }
    @resp.BulkString(b) =>
      @string.parse_double(@utf8.decode_lossy(b[:])) catch {
        _ => raise Protocol("expected double, got bulk")
      }
    other => raise Protocol("expected double, got " + @resp.resp_kind(other))
  }
}

///|
/// A score that may be missing: RESP3 sends a double, RESP2 a string, and both nil.
pub fn expect_score(reply : @resp.RespValue) -> Double? raise RedisError {
  match reply {
    @resp.Null => None
    other => Some(expect_double(other))
  }
}

///|
/// A reply as a map (RESP3 `%`) of key/value pairs.
pub fn expect_map(
  reply : @resp.RespValue,
) -> Array[(@resp.RespValue, @resp.RespValue)] raise RedisError {
  match reply {
    @resp.RespMap(pairs) => pairs
    other => raise Protocol("expected map, got " + @resp.resp_kind(other))
  }
}
