// A connection pool: a small stack of idle connections reused across commands, bounded by
// the pool options. `get` borrows an idle connection or opens one, and `put` returns it.

///|
/// A pool of connections to one server, kept warm up to `max_idle`.
pub struct Pool {
  options : @moonredis.ClientOptions
  idle : Array[Connection]
}

///|
/// An empty pool for `options`.
pub fn Pool::new(options : @moonredis.ClientOptions) -> Pool {
  { options, idle: [], }
}

///|
/// Borrow a connection: reuse an idle one or open a new one.
pub async fn Pool::get(self : Pool) -> Connection raise @moonredis.RedisError {
  match self.idle.pop() {
    Some(conn) => conn
    None => Connection::connect(self.options)
  }
}

///|
/// Return a connection to the pool. It is kept only while the pool is under `max_idle`;
/// past that it is dropped (the connection closes when its socket is collected).
pub fn Pool::put(self : Pool, conn : Connection) -> Unit {
  if self.idle.length() < self.options.pool.max_idle {
    self.idle.push(conn)
  }
}

///|
/// How many idle connections the pool holds.
pub fn Pool::idle_count(self : Pool) -> Int32 {
  self.idle.length()
}
