// A pub/sub subscription over a connection: it sends `SUBSCRIBE`, consumes the confirmation
// frames, and yields `Message` frames as they arrive. A subscribed connection carries only
// pushes, so the ordinary request/reply path is not used while subscribed.

///|
/// A live subscription: the subscribed connection and the channels/patterns on it.
pub struct Subscription {
  conn : Connection
}

///|
/// Subscribe `conn` to `channels` (or patterns) and consume the confirmation frames, so the
/// next read returns a message rather than a confirmation.
pub async fn Subscription::subscribe(
  conn : Connection,
  channels : Array[String],
  pattern? : Bool,
) -> Subscription raise @moonredis.RedisError {
  let op : Bytes = if pattern.unwrap_or(false) {
    b"PSUBSCRIBE"
  } else {
    b"SUBSCRIBE"
  }
  let args : Array[Bytes] = [op]
  for c in channels {
    args.push(@utf8.encode(c))
  }
  write_bytes(conn.conn, @resp.resp_encode_command(args))
  for _i = 0; _i < channels.length(); _i = _i + 1 {
    let _ = read_value(conn.conn)
  }
  { conn, }
}

///|
/// The next message frame, or `None` if the next frame is not a pub/sub message (a
/// confirmation, for example).
pub async fn Subscription::next(
  self : Subscription,
) -> @moonredis.Message? raise @moonredis.RedisError {
  let value = read_value(self.conn.conn)
  @moonredis.Message::parse(value)
}

///|
/// `UNSUBSCRIBE`/`PUNSUBSCRIBE` from the given channels or patterns, consuming the
/// confirmation frames.
pub async fn Subscription::unsubscribe(
  self : Subscription,
  channels : Array[String],
  pattern? : Bool,
) -> Unit raise @moonredis.RedisError {
  let op : Bytes = if pattern.unwrap_or(false) {
    b"PUNSUBSCRIBE"
  } else {
    b"UNSUBSCRIBE"
  }
  let args : Array[Bytes] = [op]
  for c in channels {
    args.push(@utf8.encode(c))
  }
  write_bytes(self.conn.conn, @resp.resp_encode_command(args))
  for _i = 0; _i < channels.length(); _i = _i + 1 {
    let _ = read_value(self.conn.conn)
  }
}
