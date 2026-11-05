// The JSON commands driven through the in-memory `FakeConn`: what the typed method writes
// on the wire, and what it makes of the reply under either protocol. RESP2 answers a value
// as JSON text, RESP3 as a typed value or an array of them, so both shapes are exercised.

///|
async test "json: get sends the path and parses the document" {
  let conn = @moonredis.FakeConn::new([
    @resp.BulkString(b"{\"a\":1,\"b\":[1,2]}"),
  ])
  let client = @moonredis.Client::new(conn)
  let value = client.json_get("doc", path="$.a")
  assert_eq(conn.sent()[0], [b"JSON.GET", b"doc", b"$.a"])
  assert_eq(value.unwrap().stringify(), "{\"a\":1,\"b\":[1,2]}")
}

///|
async test "json: get without a path sends no path" {
  let conn = @moonredis.FakeConn::new([@resp.Null])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.json_get("missing"), None)
  assert_eq(conn.sent()[0], [b"JSON.GET", b"missing"])
}

///|
async test "json: get_text writes the formatting and the path in order" {
  let conn = @moonredis.FakeConn::new([@resp.BulkString(b"{\"a\":1}")])
  let client = @moonredis.Client::new(conn)
  let text = client.json_get_text(
    "doc",
    path="$.o",
    indent="  ",
    newline="\n",
    space=" ",
  )
  assert_eq(text, Some("{\"a\":1}"))
  assert_eq(conn.sent()[0], [
    b"JSON.GET", b"doc", b"INDENT", b"  ", b"NEWLINE", b"\n", b"SPACE", b" ", b"$.o",
  ])
}

///|
async test "json: set writes the document, the flags and the storage hint" {
  let conn = @moonredis.FakeConn::new([@resp.SimpleString("OK")])
  let client = @moonredis.Client::new(conn)
  let stored = client.json_set(
    "doc",
    "$",
    @json.Json::object(Map([("a", @json.Json::number(1.0))])),
    nx=true,
    fpha=@moonredis.Fp32,
  )
  assert_true(stored)
  assert_eq(conn.sent()[0], [
    b"JSON.SET", b"doc", b"$", b"{\"a\":1}", b"NX", b"FPHA", b"FP32",
  ])
}

///|
async test "json: set reports a refused write as false" {
  let conn = @moonredis.FakeConn::new([@resp.Null])
  let client = @moonredis.Client::new(conn)
  assert_false(client.json_set("doc", "$", @json.Json::null(), xx=true))
}

///|
async test "json: numincrby reads the text RESP2 sends" {
  let conn = @moonredis.FakeConn::new([
    @resp.BulkString(b"[6]"),
    @resp.BulkString(b"11"),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.json_numincrby("doc", "$.n", 5), [Some(6.0)])
  assert_eq(client.json_numincrby("doc", ".n", 5), [Some(11.0)])
  assert_eq(conn.sent()[0], [b"JSON.NUMINCRBY", b"doc", b"$.n", b"5"])
}

///|
async test "json: nummultby reads the array RESP3 sends" {
  let conn = @moonredis.FakeConn::new([@resp.Array([@resp.Integer(22)])])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.json_nummultby("doc", "$.n", 2), [Some(22.0)])
}

///|
async test "json: type wraps the single value RESP2 sends for the root" {
  let conn = @moonredis.FakeConn::new([
    @resp.BulkString(b"object"),
    @resp.Array([@resp.BulkString(b"integer")]),
    @resp.Array([@resp.Null]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.json_type("doc"), [Some("object")])
  assert_eq(client.json_type("doc", path="$.n"), [Some("integer")])
  assert_eq(client.json_type("doc", path="$.missing"), [None])
}

///|
async test "json: arrlen and strlen answer per match" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Integer(3)]),
    @resp.Integer(3),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.json_arrlen("doc", path="$.arr"), [Some(3)])
  assert_eq(client.json_strlen("doc"), [Some(3)])
}

///|
async test "json: mget keeps a missing document as none" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.BulkString(b"[1]"), @resp.Null]),
  ])
  let client = @moonredis.Client::new(conn)
  let values = client.json_mget(["a", "b"], "$.n")
  assert_eq(conn.sent()[0], [b"JSON.MGET", b"a", b"b", b"$.n"])
  assert_eq(values.length(), 2)
  assert_eq(values[0].unwrap().stringify(), "[1]")
  assert_eq(values[1], None)
}

///|
async test "json: arrpop reads a popped string as the document it holds" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.BulkString(b"\"tail\""), @resp.Null]),
  ])
  let client = @moonredis.Client::new(conn)
  let popped = client.json_arrpop("doc", "$.arr", index=-1)
  assert_eq(popped.length(), 2)
  assert_eq(popped[0].unwrap().stringify(), "\"tail\"")
  assert_eq(popped[1], None)
}

///|
async test "json: toggle reads the flags of both protocols" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Integer(0)]),
    @resp.Array([@resp.Boolean(true)]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.json_toggle("doc", "$.b"), [Some(false)])
  assert_eq(client.json_toggle("doc", "$.b"), [Some(true)])
}

///|
async test "json: objkeys lists the members of each object" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Array([@resp.BulkString(b"k"), @resp.BulkString(b"j")])]),
    @resp.Array([@resp.Null]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.json_objkeys("doc", path="$.o"), [Some(["k", "j"])])
  assert_eq(client.json_objkeys("doc", path="$.missing"), [None])
}
