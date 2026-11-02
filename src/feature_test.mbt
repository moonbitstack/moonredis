// Unit tests for the pure routing pieces (CRC16/HASH_SLOT, topology), the pub/sub frame
// decoder, the pipeline, and a sample of the typed command surface driven through the
// in-memory `FakeConn` — no socket or network needed, so these run on every backend.

///|
test "crc16: CRC-16/XMODEM check value" {
  // The standard check value for "123456789" under CRC-16/XMODEM (poly 0x1021, init 0).
  assert_eq(@moonredis.crc16(b"123456789"), 0x31c3)
}

///|
test "hash_slot: known keys and hash tags" {
  // Values match `CLUSTER KEYSLOT`; a `{tag}` makes the key hash by the tag.
  assert_eq(@moonredis.hash_slot("foo"), 12182)
  assert_eq(@moonredis.hash_slot("bar"), 5061)
  assert_eq(@moonredis.hash_slot("{foo}bar"), 12182)
  assert_eq(@moonredis.hash_slot("{bar}foo"), 5061)
}

///|
test "hash_slot: same_slot for colocated keys" {
  assert_true(@moonredis.same_slot(["{user1}a", "{user1}b"]))
  assert_false(@moonredis.same_slot(["foo", "bar"]))
}

///|
test "cluster topology: node_for_slot" {
  let topo = @moonredis.ClusterTopology::new([
    @moonredis.ClusterSlot::new(0, 5460, "a:1"),
    @moonredis.ClusterSlot::new(5461, 10922, "b:2"),
  ])
  assert_eq(topo.node_for_slot(0), Some("a:1"))
  assert_eq(topo.node_for_slot(6000), Some("b:2"))
  assert_eq(topo.node_for_slot(16383), None)
}

///|
test "pubsub message: parse a message frame" {
  let v = @resp.Array([
    @resp.BulkString(b"message"),
    @resp.BulkString(b"news"),
    @resp.BulkString(b"hi"),
  ])
  match @moonredis.Message::parse(v) {
    Some(m) => {
      assert_eq(m.kind, "message")
      assert_eq(m.channel, "news")
      assert_eq(m.payload, b"hi")
    }
    None => assert_true(false)
  }
}

///|
test "pubsub message: parse a subscribe confirmation" {
  let v = @resp.Array([
    @resp.BulkString(b"subscribe"),
    @resp.BulkString(b"news"),
    @resp.Integer(1),
  ])
  match @moonredis.Message::parse(v) {
    Some(m) => {
      assert_eq(m.kind, "subscribe")
      assert_eq(m.channel, "news")
      assert_eq(m.count, 1)
    }
    None => assert_true(false)
  }
}

///|
async test "pipeline: collects replies in order" {
  let conn = @moonredis.FakeConn::new([
    @resp.SimpleString("OK"),
    @resp.SimpleString("OK"),
  ])
  let p = @moonredis.Pipeline::new(conn)
  p.add([b"SET", b"a", b"1"])
  p.add([b"SET", b"b", b"2"])
  let replies = p.execute()
  assert_eq(replies.length(), 2)
  assert_eq(replies[0], @resp.SimpleString("OK"))
}

///|
async test "hash: hgetall decodes field/value pairs" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.BulkString(b"a"),
      @resp.BulkString(b"1"),
      @resp.BulkString(b"b"),
      @resp.BulkString(b"2"),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let pairs = client.hgetall("h")
  assert_eq(pairs.length(), 2)
  assert_eq(pairs[0], ("a", "1"))
  assert_eq(pairs[1], ("b", "2"))
}

///|
async test "set: sadd returns the added count" {
  let conn = @moonredis.FakeConn::new([@resp.Integer(2)])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.sadd("s", ["a", "b"]), 2)
}

///|
async test "key: scan decodes cursor and keys" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.BulkString(b"0"),
      @resp.Array([@resp.BulkString(b"k1"), @resp.BulkString(b"k2")]),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let (next, keys) = client.scan("0")
  assert_eq(next, "0")
  assert_eq(keys.length(), 2)
  assert_eq(keys[0], "k1")
}

///|
async test "zset: zrange_scores decodes member/score pairs" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.BulkString(b"a"),
      @resp.BulkString(b"1.5"),
      @resp.BulkString(b"b"),
      @resp.BulkString(b"2"),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let pairs = client.zrange_scores("z", 0, -1)
  assert_eq(pairs.length(), 2)
  assert_eq(pairs[0].0, "a")
  assert_eq(pairs[0].1, 1.5)
}

///|
/// A connection that fails its first `remaining_failures` calls, then answers `OK`.
struct FailingConn {
  mut remaining_failures : Int32
  mut calls : Int32
}

///|
pub impl @moonredis.RedisConn for FailingConn with fn execute(
  self,
  _args : Array[Bytes],
) -> @resp.RespValue raise @moonredis.RedisError {
  self.calls = self.calls + 1
  if self.remaining_failures > 0 {
    self.remaining_failures = self.remaining_failures - 1
    raise @moonredis.Connection("transient")
  }
  @resp.SimpleString("OK")
}

///|
async test "retry: retries a transient failure then succeeds" {
  let conn : FailingConn = { remaining_failures: 2, calls: 0, }
  let retry = @moonredis.RetryConn::new(conn, @moonredis.retry_default)
  assert_eq(retry.execute([b"PING"]), @resp.SimpleString("OK"))
  assert_eq(conn.calls, 3)
}

///|
async test "a script loads once, and again when the server has forgotten it" {
  let verbs : Array[String] = []
  let forgotten = Ref(false)
  let conn = @moonredis.FakeConn::handler(args => {
    let verb = @utf8.decode_lossy(args[0][:])
    verbs.push(verb)
    match verb {
      "SCRIPT" => @resp.BulkString(b"abc")
      "EVALSHA" if forgotten.val => {
        forgotten.val = false
        @resp.Error("NOSCRIPT No matching script.")
      }
      _ => @resp.Integer(7)
    }
  })
  let client = @moonredis.Client::new(conn)
  let script = @moonredis.Script::new("return 7")
  assert_eq(script.run(client, ["k"], []), @resp.Integer(7))
  assert_eq(script.run(client, ["k"], []), @resp.Integer(7))
  assert_eq(verbs, ["SCRIPT", "EVALSHA", "EVALSHA"])
  forgotten.val = true
  assert_eq(script.run(client, ["k"], []), @resp.Integer(7))
  assert_eq(verbs[3:].to_owned(), ["EVALSHA", "SCRIPT", "EVALSHA"])
}

///|
async test "a script's own error is raised, not retried" {
  let conn = @moonredis.FakeConn::handler(args => {
    match @utf8.decode_lossy(args[0][:]) {
      "SCRIPT" => @resp.BulkString(b"abc")
      _ => @resp.Error("ERR the script failed")
    }
  })
  let script = @moonredis.Script::new("error()")
  let failed = try {
    ignore(script.run(@moonredis.Client::new(conn), [], []))
    false
  } catch {
    @moonredis.Reply(_) => true
    _ => false
  }
  assert_true(failed)
}
