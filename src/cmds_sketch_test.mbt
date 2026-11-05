// The count-min sketch, top-k and t-digest commands through the in-memory `FakeConn`:
// their numbers arrive as text under RESP2 and as doubles or integers under RESP3.

///|
async test "sketch: cms.incrby and cms.query answer counts" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Integer(6), @resp.Integer(4)]),
    @resp.Array([@resp.Integer(6), @resp.Integer(0)]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.cms_incrby("cms", [("a", 3), ("b", 2)]), [6L, 4L])
  assert_eq(conn.sent()[0], [b"CMS.INCRBY", b"cms", b"a", b"3", b"b", b"2"])
  assert_eq(client.cms_query("cms", ["a", "z"]), [6L, 0L])
}

///|
async test "sketch: cms.merge writes the sources and their weights" {
  let conn = @moonredis.FakeConn::new([@resp.SimpleString("OK")])
  let client = @moonredis.Client::new(conn)
  client.cms_merge("sum", ["a", "b"], weights=[1, 2])
  assert_eq(conn.sent()[0], [
    b"CMS.MERGE", b"sum", b"2", b"a", b"b", b"WEIGHTS", b"1", b"2",
  ])
}

///|
async test "sketch: cms.info reads width, depth and count" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.SimpleString("width"),
      @resp.Integer(100),
      @resp.SimpleString("depth"),
      @resp.Integer(5),
      @resp.SimpleString("count"),
      @resp.Integer(10),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let info = client.cms_info("cms")
  assert_eq(info.int("width"), Some(100L))
  assert_eq(info.int("count"), Some(10L))
}

///|
async test "sketch: topk.add reads an eviction per item" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.Null,
      @resp.BulkString(b"old"),
      @resp.BulkString(b"older"),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let evicted = client.topk_add("tk", ["a", "b", "c"])
  assert_eq(evicted, [None, Some("old"), Some("older")])
}

///|
async test "sketch: topk.list with counts pairs names and counts" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.BulkString(b"a"),
      @resp.Integer(16),
      @resp.BulkString(b"b"),
      @resp.Integer(4),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let listed = client.topk_list_with_count("tk")
  assert_eq(conn.sent()[0], [b"TOPK.LIST", b"tk", b"WITHCOUNT"])
  assert_eq(listed, [("a", 16L), ("b", 4L)])
}

///|
async test "sketch: topk.query reads booleans and integers" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Boolean(true), @resp.Boolean(false)]),
    @resp.Array([@resp.Integer(1), @resp.Integer(0)]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.topk_query("tk", ["a", "z"]), [true, false])
  assert_eq(client.topk_query("tk", ["a", "z"]), [true, false])
}

///|
async test "sketch: tdigest.quantile reads text and doubles" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.BulkString(b"2")]),
    @resp.Array([@resp.Double(4.0)]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.tdigest_quantile("td", [0.5]), [2.0])
  assert_eq(conn.sent()[0], [b"TDIGEST.QUANTILE", b"td", b"0.5"])
  assert_eq(client.tdigest_quantile("td", [0.9]), [4.0])
}

///|
async test "sketch: tdigest-min of an empty sketch is nan" {
  let conn = @moonredis.FakeConn::new([@resp.BulkString(b"nan")])
  let client = @moonredis.Client::new(conn)
  assert_true(client.tdigest_min("td").is_nan())
}

///|
async test "sketch: tdigest.rank and byrank answer ranks and values" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Integer(0), @resp.Integer(2)]),
    @resp.Array([@resp.BulkString(b"1"), @resp.BulkString(b"3")]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.tdigest_rank("td", [1.0, 3.0]), [0L, 2L])
  assert_eq(client.tdigest_byrank("td", [0, 2]), [1.0, 3.0])
}

///|
async test "sketch: tdigest.merge writes the compression and the override flag" {
  let conn = @moonredis.FakeConn::new([@resp.SimpleString("OK")])
  let client = @moonredis.Client::new(conn)
  client.tdigest_merge("m", ["a", "b"], compression=50, overwrite=true)
  assert_eq(conn.sent()[0], [
    b"TDIGEST.MERGE", b"m", b"2", b"a", b"b", b"COMPRESSION", b"50", b"OVERRIDE",
  ])
}

///|
async test "sketch: tdigest.info reads the flat reply" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.SimpleString("Compression"),
      @resp.Integer(100),
      @resp.SimpleString("Observations"),
      @resp.Integer(3),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let info = client.tdigest_info("td")
  assert_eq(info.int("Compression"), Some(100L))
  assert_eq(info.int("Observations"), Some(3L))
}
