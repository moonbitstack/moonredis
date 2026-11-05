// The Bloom and cuckoo filter commands through the in-memory `FakeConn`: a member test is
// an integer under RESP2 and a boolean under RESP3, so both shapes are exercised.

///|
async test "filter: bf.add reads an integer and a boolean" {
  let conn = @moonredis.FakeConn::new([@resp.Integer(1), @resp.Boolean(false)])
  let client = @moonredis.Client::new(conn)
  assert_true(client.bf_add("bf", "a"))
  assert_false(client.bf_add("bf", "a"))
  assert_eq(conn.sent()[0], [b"BF.ADD", b"bf", b"a"])
}

///|
async test "filter: bf.reserve writes the growth policy" {
  let conn = @moonredis.FakeConn::new([@resp.SimpleString("OK")])
  let client = @moonredis.Client::new(conn)
  client.bf_reserve("bf", 0.01, 100, expansion=4, nonscaling=true)
  assert_eq(conn.sent()[0], [
    b"BF.RESERVE", b"bf", b"0.01", b"100", b"EXPANSION", b"4", b"NONSCALING",
  ])
}

///|
async test "filter: bf.info reads the flat reply" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.SimpleString("Capacity"),
      @resp.Integer(100),
      @resp.SimpleString("Number of items inserted"),
      @resp.Integer(3),
      @resp.SimpleString("Expansion rate"),
      @resp.Null,
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let info = client.bf_info("bf")
  assert_eq(info.int("Capacity"), Some(100L))
  assert_eq(info.int("Number of items inserted"), Some(3L))
  assert_eq(info.get("Expansion rate"), @moonredis.Missing)
}

///|
async test "filter: bf.scandump keeps the chunk binary-safe" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Integer(1), @resp.BulkString(b"\x00\xff\x10")]),
    @resp.Array([@resp.Integer(0), @resp.Null]),
  ])
  let client = @moonredis.Client::new(conn)
  let (iterator, chunk) = client.bf_scandump("bf", 0)
  assert_eq(iterator, 1L)
  assert_eq(chunk, Some(b"\x00\xff\x10"))
  let (done, last) = client.bf_scandump("bf", iterator)
  assert_eq(done, 0L)
  assert_eq(last, None)
}

///|
async test "filter: cf.insertnx reads one flag per item" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Integer(0), @resp.Integer(1)]),
    @resp.Array([@resp.Boolean(false), @resp.Boolean(true)]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.cf_insertnx("cf", ["a", "b"], capacity=100), [false, true])
  assert_eq(conn.sent()[0], [
    b"CF.INSERTNX", b"cf", b"CAPACITY", b"100", b"ITEMS", b"a", b"b",
  ])
  assert_eq(client.cf_insertnx("cf", ["a", "b"]), [false, true])
}

///|
async test "filter: cf.addnx and cf.count answer as they arrive" {
  let conn = @moonredis.FakeConn::new([
    @resp.Boolean(false),
    @resp.Integer(2),
    @resp.Boolean(true),
  ])
  let client = @moonredis.Client::new(conn)
  assert_false(client.cf_addnx("cf", "a"))
  assert_eq(client.cf_count("cf", "a"), 2L)
  assert_true(client.cf_del("cf", "a"))
}

///|
async test "filter: cf.info reads the map resp3 replies with" {
  let conn = @moonredis.FakeConn::new([
    @resp.RespMap([
      (@resp.SimpleString("Size"), @resp.Integer(184)),
      (@resp.SimpleString("Number of buckets"), @resp.Integer(64)),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let info = client.cf_info("cf")
  assert_eq(info.int("Size"), Some(184L))
  assert_eq(info.int("Number of buckets"), Some(64L))
}
