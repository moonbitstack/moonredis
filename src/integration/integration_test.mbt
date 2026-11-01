// Integration tests against a live redis. Each connects to 127.0.0.1:6379 and returns early
// when nothing is listening, so the unit suite passes without a server and CI — which starts
// a redis — exercises them for real.

///|
async test "socket: ping and set/get against a live redis (skips if none)" {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let conn = @socket.Connection::connect(options) catch { _ => return }
  let client = @moonredis.Client::new(conn)
  assert_eq(client.ping(), "PONG")
  assert_true(client.set("moonredis:it:key", "v"))
  assert_eq(client.get("moonredis:it:key"), Some(b"v"))
  let _ = client.del(["moonredis:it:key"])
}

///|
async test "socket: hash round-trip" {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let conn = @socket.Connection::connect(options) catch { _ => return }
  let client = @moonredis.Client::new(conn)
  let _ = client.del(["moonredis:it:h"])
  assert_eq(client.hset("moonredis:it:h", [("a", "1"), ("b", "2")]), 2)
  let pairs = client.hgetall("moonredis:it:h")
  assert_eq(pairs.length(), 2)
  assert_eq(client.hget("moonredis:it:h", "a"), Some(b"1"))
  let _ = client.del(["moonredis:it:h"])
}

///|
async test "socket: pipeline collects ordered replies" {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let conn = @socket.Connection::connect(options) catch { _ => return }
  let p = @moonredis.Pipeline::new(conn)
  p.add([b"SET", b"moonredis:it:p", b"1"])
  p.add([b"GET", b"moonredis:it:p"])
  p.add([b"DEL", b"moonredis:it:p"])
  let replies = p.execute()
  assert_eq(replies.length(), 3)
  assert_eq(replies[1], @resp.BulkString(b"1"))
}

///|
async test "socket: a published message reaches a subscriber" {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let sub_conn = @socket.Connection::connect(options) catch { _ => return }
  let sub = @socket.Subscription::subscribe(sub_conn, ["moonredis:it:ch"])
  let pub_conn = @socket.Connection::connect(options) catch { _ => return }
  let publisher = @moonredis.Client::new(pub_conn)
  let _ = publisher.publish("moonredis:it:ch", "hello")
  match sub.next() {
    Some(m) => {
      assert_eq(m.kind, "message")
      assert_eq(m.channel, "moonredis:it:ch")
      assert_eq(m.payload, b"hello")
    }
    None => assert_true(false)
  }
}
