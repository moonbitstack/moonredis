// Integration tests against live servers. They connect through `live`: with no server they
// return, so the unit suite passes on a machine without redis, and with `MOONREDIS_LIVE` set,
// as `scripts/start_redis.sh` is run for in CI, a missing server fails them.

///|
/// A connection to `port`, or `None` when nothing listens and nothing is required to.
async fn live(
  port : Int32,
  protocol? : @moonredis.Protocol,
  db? : Int32,
  tracking? : @moonredis.TrackingOptions,
) -> @socket.Connection? {
  let base = @moonredis.ClientOptions::at("127.0.0.1", port)
  let options = {
    ..base,
    protocol: protocol.unwrap_or(base.protocol),
    db: db.unwrap_or(base.db),
    tracking: tracking.unwrap_or(base.tracking),
  }
  let conn = @socket.Connection::connect(options) catch {
    _ => {
      if @env.get_env_var("MOONREDIS_LIVE") is Some(_) {
        fail("no redis on \{port}")
      }
      return None
    }
  }
  Some(conn)
}

///|
async test "a connection answers and round-trips a value" {
  guard live(6379) is Some(conn) else { return }
  let client = @moonredis.Client::new(conn)
  assert_eq(client.ping(), "PONG")
  assert_true(client.set("moonredis:it:key", "v"))
  assert_eq(client.get("moonredis:it:key"), Some(b"v"))
  ignore(client.del(["moonredis:it:key"]))
}

///|
async test "binary values survive the round trip" {
  guard live(6379) is Some(conn) else { return }
  let batch = @moonredis.Pipeline::new(conn)
  let value : Bytes = b"\x00\xff\r\n$5\r\n"
  batch.add([b"SET", b"moonredis:it:binary", value])
  batch.add([b"GET", b"moonredis:it:binary"])
  batch.add([b"DEL", b"moonredis:it:binary"])
  assert_eq(batch.execute()[1], @resp.BulkString(value))
}

///|
async test "a database is chosen on connect" {
  guard live(6379, db=11) is Some(three) else { return }
  guard live(6379, db=12) is Some(four) else { return }
  let a = @moonredis.Client::new(three)
  let b = @moonredis.Client::new(four)
  ignore(a.set("moonredis:it:db", "three"))
  assert_eq(b.get("moonredis:it:db"), None)
  ignore(a.del(["moonredis:it:db"]))
}
