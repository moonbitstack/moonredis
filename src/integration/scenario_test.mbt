// What a server does over time and between connections: transactions losing a race, messages
// crossing, invalidations arriving, connections dying.

///|
async test "a pipeline sends everything in one go and keeps the order" {
  guard live(6379) is Some(conn) else { return }
  let client = @moonredis.Client::new(conn)
  let key = "it:pipeline"
  ignore(client.del([key]))
  let batch = @moonredis.Pipeline::new(conn)
  for _ in 0..<1000 {
    batch.add([b"INCR", @utf8.encode(key)])
  }
  let replies = batch.execute()
  assert_eq(replies.length(), 1000)
  assert_eq(replies[0], @resp.Integer(1))
  assert_eq(replies[999], @resp.Integer(1000))
  ignore(client.del([key]))
}

///|
async test "a pipeline carries an error reply among the others" {
  guard live(6379) is Some(conn) else { return }
  let batch = @moonredis.Pipeline::new(conn)
  batch.add([b"SET", b"it:mixed", b"not a number"])
  batch.add([b"INCR", b"it:mixed"])
  batch.add([b"DEL", b"it:mixed"])
  let replies = batch.execute()
  assert_true(replies[1] is @resp.Error(_))
  assert_eq(replies[2], @resp.Integer(1))
}

///|
async test "a transaction runs whole" {
  guard live(6379) is Some(conn) else { return }
  let batch = @moonredis.Pipeline::new(conn)
  batch.multi()
  batch.add([b"SET", b"it:tx", b"1"])
  batch.add([b"INCR", b"it:tx"])
  batch.add([b"DEL", b"it:tx"])
  assert_eq(batch.execute(), [
    @resp.SimpleString("OK"),
    @resp.Integer(2),
    @resp.Integer(1),
  ])
}

///|
async test "a watched key changing aborts the transaction" {
  guard live(6379) is Some(mine) else { return }
  guard live(6379) is Some(theirs) else { return }
  let client = @moonredis.Client::new(mine)
  let other = @moonredis.Client::new(theirs)
  ignore(client.set("it:watched", "before"))
  client.watch(["it:watched"])
  ignore(other.set("it:watched", "theirs"))
  let batch = @moonredis.Pipeline::new(mine)
  batch.multi()
  batch.add([b"SET", b"it:watched", b"mine"])
  let aborted = try {
    ignore(batch.execute())
    false
  } catch {
    @moonredis.Aborted => true
    _ => false
  }
  assert_true(aborted)
  assert_eq(client.get("it:watched"), Some(b"theirs"))
  ignore(client.del(["it:watched"]))
}

///|
async test "a watched key left alone lets the transaction through" {
  guard live(6379) is Some(conn) else { return }
  let client = @moonredis.Client::new(conn)
  ignore(client.set("it:calm", "before"))
  client.watch(["it:calm"])
  let batch = @moonredis.Pipeline::new(conn)
  batch.multi()
  batch.add([b"SET", b"it:calm", b"after"])
  assert_eq(batch.execute(), [@resp.SimpleString("OK")])
  ignore(client.del(["it:calm"]))
}

///|
async test "a command redis cannot queue refuses the whole transaction" {
  guard live(6379) is Some(conn) else { return }
  let batch = @moonredis.Pipeline::new(conn)
  batch.multi()
  batch.add([b"SET", b"it:refused", b"1"])
  batch.add([b"NOSUCHCOMMAND"])
  let refused = try {
    ignore(batch.execute())
    ""
  } catch {
    @moonredis.Reply(why) => why
    _ => ""
  }
  assert_true(refused.has_prefix("EXECABORT"))
  let client = @moonredis.Client::new(conn)
  assert_eq(client.get("it:refused"), None)
}

///|
async test "a pattern subscription hears a matching channel" {
  guard live(6379) is Some(listener) else { return }
  guard live(6379) is Some(speaker) else { return }
  let subscription = @socket.Subscription::subscribe(
    listener,
    ["it:news.*"],
    pattern=true,
  )
  let client = @moonredis.Client::new(speaker)
  assert_eq(client.publish("it:news.today", "hello"), 1)
  guard subscription.next() is Some(message) else { fail("no message") }
  assert_eq(message.channel, "it:news.today")
  assert_eq(message.payload, b"hello")
  assert_eq(message.pattern, Some("it:news.*"))
}

///|
async test "a shard subscription hears a shard channel" {
  guard live(6379) is Some(listener) else { return }
  guard live(6379) is Some(speaker) else { return }
  let subscription = @socket.Subscription::subscribe(
    listener,
    ["it:shard"],
    shard=true,
  )
  let client = @moonredis.Client::new(speaker)
  assert_eq(client.spublish("it:shard", "hello"), 1)
  guard subscription.next() is Some(message) else { fail("no message") }
  assert_eq(message.kind, "smessage")
  assert_eq(message.payload, b"hello")
  subscription.unsubscribe(["it:shard"], shard=true)
  assert_eq(client.spublish("it:shard", "unheard"), 0)
}

///|
async test "leaving a channel stops the messages" {
  guard live(6379) is Some(listener) else { return }
  guard live(6379) is Some(speaker) else { return }
  let subscription = @socket.Subscription::subscribe(listener, ["it:leave"])
  subscription.unsubscribe(["it:leave"])
  let client = @moonredis.Client::new(speaker)
  assert_eq(client.publish("it:leave", "unheard"), 0)
}

///|
async test "a tracked key changing elsewhere pushes an invalidation" {
  let tracking = { ..@moonredis.tracking_default, enabled: true, }
  guard live(6379, tracking~) is Some(reader) else { return }
  guard live(6379) is Some(writer) else { return }
  let client = @moonredis.Client::new(reader)
  let other = @moonredis.Client::new(writer)
  ignore(other.set("it:tracked", "before"))
  assert_eq(client.get("it:tracked"), Some(b"before"))
  ignore(other.set("it:tracked", "after"))
  // The push arrives ahead of the next reply on this connection.
  assert_eq(client.ping(), "PONG")
  let pushes = reader.take_pushes()
  assert_eq(pushes.length(), 1)
  guard pushes[0] is @resp.Push([@resp.BulkString(kind), keys]) else {
    fail("not an invalidation")
  }
  assert_eq(kind, b"invalidate")
  assert_eq(keys, @resp.Array([@resp.BulkString(b"it:tracked")]))
  ignore(other.del(["it:tracked"]))
}

///|
async test "a key not read is not invalidated" {
  let tracking = { ..@moonredis.tracking_default, enabled: true, }
  guard live(6379, tracking~) is Some(reader) else { return }
  guard live(6379) is Some(writer) else { return }
  let client = @moonredis.Client::new(reader)
  let other = @moonredis.Client::new(writer)
  ignore(other.set("it:untouched", "v"))
  assert_eq(client.ping(), "PONG")
  assert_eq(reader.take_pushes().length(), 0)
  ignore(other.del(["it:untouched"]))
}

///|
async test "a connection killed underneath reconnects and carries on" {
  guard live(6379) is Some(probe) else { return }
  let options = {
    ..@moonredis.ClientOptions::at("127.0.0.1", 6379),
    retry: { ..@moonredis.retry_default, attempts: 3, base_delay: 1, },
  }
  let conn = @socket.connect_retrying(options)
  let client = @moonredis.Client::new(conn)
  client.client_setname("it-doomed")
  let admin = @moonredis.Client::new(probe)
  assert_eq(admin.client_kill(["ID", client.client_id().to_string()]), 1)
  assert_eq(client.ping(), "PONG")
}

///|
async test "a retry stops at its limit" {
  guard live(6379) is Some(probe) else { return }
  let dials = Ref(0)
  let failing = @moonredis.RetryConn::new(
    probe,
    { ..@moonredis.retry_default, attempts: 3, },
    dial=() => {
      dials.val += 1
      raise @moonredis.Connection("still down")
    },
  )
  let admin = @moonredis.Client::new(probe)
  let id = admin.client_id()
  guard live(6379) is Some(killer) else { return }
  ignore(@moonredis.Client::new(killer).client_kill(["ID", id.to_string()]))
  let raised = try {
    ignore(@moonredis.Client::new(failing).ping())
    false
  } catch {
    @moonredis.Connection(_) => true
    _ => false
  }
  assert_true(raised)
  assert_eq(dials.val, 2)
}

///|
async test "a pool hands the same connection back" {
  guard live(6379) is Some(_) else { return }
  let pool = @socket.Pool::new(@moonredis.ClientOptions::at("127.0.0.1", 6379))
  let conn = pool.get()
  assert_eq(pool.idle_count(), 0)
  let id = @moonredis.Client::new(conn).client_id()
  pool.put(conn)
  assert_eq(pool.idle_count(), 1)
  let again = pool.get()
  assert_eq(pool.idle_count(), 0)
  assert_eq(@moonredis.Client::new(again).client_id(), id)
}
