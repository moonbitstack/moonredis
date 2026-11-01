// The client and the command entry every typed method routes through. A client is a thin
// wrapper over a `RedisConn`; `command` sends an array of argument bytes and turns a redis
// error reply into `RedisError`, leaving transport failures to surface from `execute`.

///|
/// A redis client over a `RedisConn`: the typed command families are methods on it, and
/// `command` is the general entry when a caller wants to send raw argument bytes.
pub struct Client {
  conn : &RedisConn
}

///|
/// A client over `conn`.
pub fn Client::new(conn : &RedisConn) -> Client {
  { conn, }
}

///|
/// Send `args` as a command and return the reply, turning a redis error reply (`-ERR` or
/// a bulk error) into `RedisError::Reply`. A transport failure raises from `execute` as a
/// `Connection` or `Closed` error, unchanged.
pub async fn Client::command(
  self : Client,
  args : Array[Bytes],
) -> @resp.RespValue raise RedisError {
  let reply = self.conn.execute(args)
  match reply {
    @resp.Error(msg) => raise Reply(msg)
    @resp.BulkError(msg) => raise Reply(msg)
    other => other
  }
}
