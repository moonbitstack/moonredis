// Small builders that turn the MoonBit values a typed command takes into the bulk-string
// argument bytes redis expects. A command is an array of these; the codec frames them.

///|
/// A string argument, UTF-8 encoded.
pub fn arg_string(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
/// An `Int` argument as its decimal text.
pub fn arg_int(n : Int32) -> Bytes {
  @utf8.encode(n.to_string())
}

///|
/// An `Int64` argument as its decimal text.
pub fn arg_int64(n : Int64) -> Bytes {
  @utf8.encode(n.to_string())
}

///|
/// A `Double` argument as its decimal text.
pub fn arg_double(d : Double) -> Bytes {
  @utf8.encode(d.to_string())
}

///|
/// A binary-safe argument, passed through unchanged.
pub fn arg_bytes(b : Bytes) -> Bytes {
  b
}

///|
/// Append an optional argument only when it is present, in a `when Some` arm.
pub fn push_some(builder : Array[Bytes], token : Bytes, value : Bytes?) -> Unit {
  match value {
    Some(v) => {
      builder.push(token)
      builder.push(v)
    }
    None => ()
  }
}
