// Pipeline and transaction batching. A pipeline queues several commands and sends them
// together, returning their replies in order; in transaction mode it wraps them in
// `MULTI`/`EXEC` so redis runs them atomically.

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
/// Run the queued commands in one round trip. Without `multi` the replies come back in
/// order, an error reply being one among them. With `multi` they run atomically and the
/// `EXEC` result comes back: `Aborted` when a watched key changed, `Reply` when redis refused
/// the batch, as it does for a command it could not queue.
pub async fn Pipeline::execute(
  self : Pipeline,
) -> Array[@resp.RespValue] raise RedisError {
  guard self.transaction else { return self.conn.execute_all(self.queue) }
  let replies = self.conn.execute_all([[b"MULTI"], ..self.queue, [b"EXEC"]])
  match replies[replies.length() - 1] {
    @resp.Null => raise Aborted
    @resp.Error(msg) | @resp.BulkError(msg) => raise Reply(msg)
    other => expect_array(other)
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
