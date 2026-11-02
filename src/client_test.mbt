// Internal tests: this file is part of `package moonredis`, so it inherits the `for "test"`
// async import and can drive the typed command surface through the in-memory `FakeConn`
// without a socket.
// Test files qualify package members with `@moonredis.` to silence the implicit-import warning.

///|
async test "client: set and get round-trip through a fake connection" {
  let replies = [@resp.SimpleString("OK"), @resp.BulkString(b"world")]
  let client = @moonredis.Client::new(@moonredis.FakeConn::new(replies))
  assert_true(client.set("hello", "world"))
  assert_eq(client.get("hello"), Some(b"world"))
}

///|
async test "client: a redis error reply becomes RedisError::Reply" {
  let client = @moonredis.Client::new(
    @moonredis.FakeConn::new([@resp.Error("ERR wrong type")]),
  )
  let raised = try {
    let _ = client.get("key")
    false
  } catch {
    @moonredis.Reply(msg) => msg == "ERR wrong type"
    _ => false
  }
  assert_true(raised)
}
