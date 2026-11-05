// The connection a client speaks over, and the in-memory fake the tests drive it with.
// `RedisConn` is an open, async trait so the same client runs over a real redis socket
// (`socket` package) or a scripted fake; the command and reply logic here is transport
// independent and is tested on every backend against the fake.

///|
/// A live redis connection: it sends an encoded command (an array of argument byte
/// strings) and returns the decoded reply. Implementations own the transport — a real
/// socket speaking RESP, or an in-memory fake. It is open and `async` so a socket can be
/// one: real redis I/O suspends, and a sealed synchronous trait left every implementation
/// a test double.
pub(open) trait RedisConn {
  async fn execute(Self, Array[Bytes]) -> @resp.RespValue raise RedisError
  /// Run several commands and return their replies in order, an error reply being one reply
  /// among the others. The default takes them one round trip at a time; a socket sends them
  /// together, which is what makes a pipeline worth having.
  async fn execute_all(Self, Array[Array[Bytes]]) -> Array[@resp.RespValue] raise RedisError = _
}

///|
impl RedisConn with fn execute_all(self, commands) {
  let replies = []
  for args in commands {
    replies.push(self.execute(args))
  }
  replies
}

///|
/// A redis connection backed by a scripted reply queue and, once the queue is spent, a
/// handler keyed on the command sent. The tests drive the whole command surface through
/// it without a socket, and the cluster and sentinel routing tests feed it handlers that
/// mimic a node.
pub struct FakeConn {
  queue : Array[@resp.RespValue]
  mut at : Int32
  run : (Array[Bytes]) -> @resp.RespValue
  sent : Array[Array[Bytes]]
}

///|
/// A fake that returns `replies` in order, then `Null` for every further call.
pub fn FakeConn::new(replies : Array[@resp.RespValue]) -> FakeConn {
  { queue: replies, at: 0, run: _ => @resp.Null, sent: [], }
}

///|
/// A fake that answers every call with `handler`, ignoring any queue.
pub fn FakeConn::handler(run : (Array[Bytes]) -> @resp.RespValue) -> FakeConn {
  { queue: [], at: 0, run, sent: [], }
}

///|
/// Every command the fake was asked to send, in order, so a test can assert the wire form a
/// typed method builds and not only the reply it decodes.
pub fn FakeConn::sent(self : FakeConn) -> Array[Array[Bytes]] {
  self.sent
}

///|
pub extend FakeConn with RedisConn::{execute, execute_all}

///|
pub impl RedisConn for FakeConn with fn execute(self, args : Array[Bytes]) -> @resp.RespValue raise RedisError {
  self.sent.push(args)
  if self.at < self.queue.length() {
    let v = self.queue[self.at]
    self.at += 1
    v
  } else {
    (self.run)(args)
  }
}
