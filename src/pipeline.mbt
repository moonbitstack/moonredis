// Pipeline and transaction batching. A pipeline queues several commands and runs them
// together, returning their replies in order; in transaction mode it wraps them in
// `MULTI`/`EXEC` so redis runs them atomically. Both are transport-independent and are
// tested against the `FakeConn`.

///|
/// A queued batch of commands against one connection. Add commands with `add`; run them
/// with `execute`. Set `multi` first to send them inside `MULTI`/`EXEC`.
pub struct Pipeline {
  conn : &RedisConn
  queue : Array[Array[Bytes]]
  mut transaction : Bool
}

///|
/// A pipeline over `conn`.
pub fn Pipeline::new(conn : &RedisConn) -> Pipeline {
  { conn, queue: [], transaction: false, }
}

///|
/// Queue `args` as the next command.
pub fn Pipeline::add(self : Pipeline, args : Array[Bytes]) -> Unit {
  self.queue.push(args)
}

///|
/// Switch the pipeline to transaction mode: `execute` will wrap the queued commands in
/// `MULTI`/`EXEC`.
pub fn Pipeline::multi(self : Pipeline) -> Unit {
  self.transaction = true
}

///|
/// Run the queued commands. Without `multi` each command is sent and its reply collected
/// in order; with `multi` they run atomically inside `MULTI`/`EXEC` and the `EXEC` result
/// array is returned (the intervening `QUEUED` replies are consumed).
pub async fn Pipeline::execute(
  self : Pipeline,
) -> Array[@resp.RespValue] raise RedisError {
  if self.transaction {
    let _ = self.conn.execute([b"MULTI"])
    for cmd in self.queue {
      let _ = self.conn.execute(cmd)
    }
    let result = self.conn.execute([b"EXEC"])
    expect_array(result)
  } else {
    let out : Array[@resp.RespValue] = []
    for cmd in self.queue {
      out.push(self.conn.execute(cmd))
    }
    out
  }
}

///|
/// `WATCH key...`: mark keys so a later transaction aborts if they change before `EXEC`.
pub async fn Client::watch(
  self : Client,
  keys : Array[String],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"WATCH"]
  for k in keys {
    args.push(arg_string(k))
  }
  status_ok(self.command(args))
}

///|
/// `UNWATCH`: clear all watched keys.
pub async fn Client::unwatch(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"UNWATCH"]))
}

///|
/// `DISCARD`: abort a transaction started with `MULTI`.
pub async fn Client::discard(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"DISCARD"]))
}
