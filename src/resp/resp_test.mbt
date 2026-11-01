///|
test "resp encode: command as an array of bulk strings" {
  assert_eq(@resp.resp_command(["PING"]), b"*1\r\n$4\r\nPING\r\n")
  assert_eq(
    @resp.resp_command(["SET", "k", "v"]),
    b"*3\r\n$3\r\nSET\r\n$1\r\nk\r\n$1\r\nv\r\n",
  )
  // Binary-safe arguments round-trip unchanged (a NUL byte in a value).
  assert_eq(
    @resp.resp_encode_command([b"GET", b"\x00\x01"]),
    b"*2\r\n$3\r\nGET\r\n$2\r\n\x00\x01\r\n",
  )
}

///|
test "resp decode: RESP2 simple types" {
  assert_eq(@resp.RespValue::decode(b"+OK\r\n"), @resp.SimpleString("OK"))
  assert_eq(
    @resp.RespValue::decode(b"-ERR bad request\r\n"),
    @resp.Error("ERR bad request"),
  )
  assert_eq(@resp.RespValue::decode(b":1000\r\n"), @resp.Integer(1000))
  assert_eq(@resp.RespValue::decode(b":-5\r\n"), @resp.Integer(-5))
}

///|
test "resp decode: RESP2 bulk strings and null" {
  assert_eq(
    @resp.RespValue::decode(b"$5\r\nhello\r\n"),
    @resp.BulkString(b"hello"),
  )
  assert_eq(@resp.RespValue::decode(b"$0\r\n\r\n"), @resp.BulkString(b""))
  // A bulk string may hold CRLF and binary bytes; the length governs, not a delimiter.
  assert_eq(
    @resp.RespValue::decode(b"$3\r\na\r\n\r\n"),
    @resp.BulkString(b"a\r\n"),
  )
  assert_eq(@resp.RespValue::decode(b"$-1\r\n"), @resp.Null)
}

///|
test "resp decode: RESP2 arrays, null array, empty array" {
  assert_eq(
    @resp.RespValue::decode(b"*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n"),
    @resp.Array([@resp.BulkString(b"foo"), @resp.BulkString(b"bar")]),
  )
  // A null array (`*-1`) is distinct from an empty array (`*0`).
  assert_eq(@resp.RespValue::decode(b"*-1\r\n"), @resp.Null)
  assert_eq(@resp.RespValue::decode(b"*0\r\n"), @resp.Array([]))
  // Nested: an array holding an integer and a bulk string.
  assert_eq(
    @resp.RespValue::decode(b"*2\r\n:1\r\n$2\r\nhi\r\n"),
    @resp.Array([@resp.Integer(1), @resp.BulkString(b"hi")]),
  )
}

///|
test "resp decode: RESP3 null, boolean, big number" {
  assert_eq(@resp.RespValue::decode(b"_\r\n"), @resp.Null)
  assert_eq(@resp.RespValue::decode(b"#t\r\n"), @resp.Boolean(true))
  assert_eq(@resp.RespValue::decode(b"#f\r\n"), @resp.Boolean(false))
  assert_eq(
    @resp.RespValue::decode(b"(3492890328409238509324850943850943825024385\r\n"),
    @resp.BigNumber("3492890328409238509324850943850943825024385"),
  )
}

///|
test "resp decode: RESP3 doubles including inf and nan" {
  assert_eq(@resp.RespValue::decode(b",3.14\r\n"), @resp.Double(3.14))
  assert_eq(@resp.RespValue::decode(b",10\r\n"), @resp.Double(10.0))
  assert_eq(
    @resp.RespValue::decode(b",inf\r\n"),
    @resp.Double(@double.infinity),
  )
  assert_eq(
    @resp.RespValue::decode(b",-inf\r\n"),
    @resp.Double(@double.neg_infinity),
  )
  // NaN never equals itself, so match the shape rather than compare values.
  match @resp.RespValue::decode(b",nan\r\n") {
    @resp.Double(d) => assert_eq(d != d, true)
    _ => abort("expected a double")
  }
}

///|
test "resp decode: RESP3 bulk error and verbatim string" {
  assert_eq(
    @resp.RespValue::decode(b"!21\r\nSYNTAX invalid syntax\r\n"),
    @resp.BulkError("SYNTAX invalid syntax"),
  )
  assert_eq(
    @resp.RespValue::decode(b"=15\r\ntxt:Some string\r\n"),
    @resp.VerbatimString("txt", b"Some string"),
  )
}

///|
test "resp decode: RESP3 map, set, push" {
  assert_eq(
    @resp.RespValue::decode(b"%2\r\n+key1\r\n:1\r\n+key2\r\n:2\r\n"),
    @resp.RespMap([
      (@resp.SimpleString("key1"), @resp.Integer(1)),
      (@resp.SimpleString("key2"), @resp.Integer(2)),
    ]),
  )
  assert_eq(
    @resp.RespValue::decode(b"~2\r\n+a\r\n+b\r\n"),
    @resp.RespSet([@resp.SimpleString("a"), @resp.SimpleString("b")]),
  )
  assert_eq(
    @resp.RespValue::decode(b">2\r\n$7\r\nmessage\r\n$2\r\nhi\r\n"),
    @resp.Push([@resp.BulkString(b"message"), @resp.BulkString(b"hi")]),
  )
}

///|
test "resp reader: pipelined replies decode in sequence" {
  let reader = @resp.RespReader::new(b"+A\r\n:2\r\n$1\r\nx\r\n")
  assert_eq(reader.read(), @resp.SimpleString("A"))
  assert_eq(reader.read(), @resp.Integer(2))
  assert_eq(reader.read(), @resp.BulkString(b"x"))
  assert_eq(reader.at_end(), true)
}

///|
test "resp decode: malformed frames raise" {
  // A bulk length longer than the available bytes.
  let truncated = try {
    let _ = @resp.RespValue::decode(b"$5\r\nhi\r\n")
    false
  } catch {
    _ => true
  }
  assert_eq(truncated, true)
  // A line with no terminating CRLF.
  let unterminated = try {
    let _ = @resp.RespValue::decode(b"+OK")
    false
  } catch {
    _ => true
  }
  assert_eq(unterminated, true)
  // An unknown type marker.
  let unknown = try {
    let _ = @resp.RespValue::decode(b"@nope\r\n")
    false
  } catch {
    _ => true
  }
  assert_eq(unknown, true)
  // Trailing bytes after a complete value.
  let trailing = try {
    let _ = @resp.RespValue::decode(b"+OK\r\n:1\r\n")
    false
  } catch {
    _ => true
  }
  assert_eq(trailing, true)
}

///|
test "resp encode: every value type round-trips through decode" {
  let samples : Array[@resp.RespValue] = [
    @resp.SimpleString("OK"),
    @resp.Error("ERR wrong"),
    @resp.Integer(-42),
    @resp.BulkString(b"hello\x00world"),
    @resp.Null,
    @resp.Array([@resp.Integer(1), @resp.BulkString(b"x"), @resp.Boolean(true)]),
    @resp.Boolean(false),
    @resp.Double(3.14),
    @resp.Double(10.0),
    @resp.BigNumber("12345678901234567890"),
    @resp.BulkError("SYNTAX bad"),
    @resp.VerbatimString("txt", b"verbatim body"),
    @resp.RespMap([
      (@resp.BulkString(b"a"), @resp.Integer(1)),
      (@resp.BulkString(b"b"), @resp.Integer(2)),
    ]),
    @resp.RespSet([@resp.SimpleString("s1"), @resp.SimpleString("s2")]),
    @resp.Push([@resp.BulkString(b"p"), @resp.Integer(9)]),
  ]
  for sample in samples {
    let bytes = sample.encode()
    let decoded = @resp.RespValue::decode(bytes)
    assert_eq(decoded, sample)
  }
}

///|
test "resp encode: doubles keep the special spellings" {
  assert_eq(@resp.Double(@double.infinity).encode(), b",inf\r\n")
  assert_eq(@resp.Double(@double.neg_infinity).encode(), b",-inf\r\n")
  match @resp.RespValue::decode(@resp.Double(@double.not_a_number).encode()) {
    @resp.Double(_) => ()
    _ => abort("expected a double")
  }
}

///|
test "resp reader: decode_first leaves trailing bytes for the next frame" {
  let reader = @resp.RespReader::new(b"+OK\r\n:7\r\n")
  assert_eq(reader.decode_first(), @resp.SimpleString("OK"))
  assert_eq(reader.at_end(), false)
  assert_eq(reader.decode_first(), @resp.Integer(7))
  assert_eq(reader.at_end(), true)
}
