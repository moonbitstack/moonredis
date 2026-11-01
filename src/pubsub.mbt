// Pub/sub. A subscription turns a connection into a stream of push frames: confirmations
// (`subscribe`, `unsubscribe`, ...) and messages (`message`, `pmessage`, `smessage`). The
// command methods below subscribe and unsubscribe a connection; `Message::parse` turns the
// frames redis sends into typed values, and the socket transport delivers them as they
// arrive. Sharded pub/sub (`ssubscribe`) targets a single cluster shard.

///|
/// One frame of the pub/sub stream. `kind` is the redis frame name (`message`,
/// `subscribe`, ...); `payload` is the message body for a `message`/`smessage` frame, and
/// `count` is the remaining subscription count for a `subscribe`/`unsubscribe` frame.
pub struct Message {
  /// The frame name redis sent (`subscribe`, `message`, `pmessage`, `smessage`,
  /// `unsubscribe`, `punsubscribe`, `sunsubscribe`).
  kind : String
  /// The channel (or shard channel for `smessage`).
  channel : String
  /// The message body, for a `message`/`smessage`/`pmessage` frame.
  payload : Bytes
  /// The pattern matched, for a `pmessage` frame.
  pattern : String?
  /// The remaining subscription count, for a subscribe/unsubscribe frame.
  count : Int64
}

///|
/// Parse a pub/sub frame — a RESP2 array or RESP3 push — into a `Message`, or `None` if
/// the value is not a pub/sub frame.
pub fn Message::parse(value : @resp.RespValue) -> Message? {
  match value {
    @resp.Array(items) | @resp.Push(items) => {
      guard items.length() >= 3 else { return None }
      let kind = match items[0] {
        @resp.SimpleString(s) => s
        @resp.BulkString(b) => @utf8.decode_lossy(b[:])
        _ => return None
      }
      match kind {
        "message" | "smessage" => {
          let channel = string_of(items[1])
          guard channel is Some(c) else { return None }
          let payload = bytes_of(items[2])
          guard payload is Some(p) else { return None }
          Some(Message::{
            kind,
            channel: c,
            payload: p,
            pattern: None,
            count: 0,
          })
        }
        "pmessage" => {
          guard items.length() >= 4 else { return None }
          let pattern = string_of(items[1])
          guard pattern is Some(pat) else { return None }
          let channel = string_of(items[2])
          guard channel is Some(c) else { return None }
          let payload = bytes_of(items[3])
          guard payload is Some(p) else { return None }
          Some(Message::{
            kind,
            channel: c,
            payload: p,
            pattern: Some(pat),
            count: 0,
          })
        }
        _ => {
          let channel = string_of(items[1])
          guard channel is Some(c) else { return None }
          let count = match items[2] {
            @resp.Integer(n) => n
            _ => 0
          }
          Some(Message::{
            kind,
            channel: c,
            payload: b"",
            pattern: None,
            count,
          })
        }
      }
    }
    _ => None
  }
}

///|
/// `SUBSCRIBE channel...`: subscribe the connection to the given channels. After this the
/// connection receives `message` frames until unsubscribed.
pub async fn Client::subscribe(
  self : Client,
  channels : Array[String],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"SUBSCRIBE"]
  for c in channels {
    args.push(arg_string(c))
  }
  let _ = self.command(args)
  ()
}

///|
/// `UNSUBSCRIBE [channel...]`: unsubscribe from the given channels, or all when omitted.
pub async fn Client::unsubscribe(
  self : Client,
  channels? : Array[String],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"UNSUBSCRIBE"]
  match channels {
    Some(cs) =>
      for c in cs {
        args.push(arg_string(c))
      }
    None => ()
  }
  let _ = self.command(args)
  ()
}

///|
/// `PSUBSCRIBE pattern...`: subscribe to channels by glob pattern.
pub async fn Client::psubscribe(
  self : Client,
  patterns : Array[String],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"PSUBSCRIBE"]
  for p in patterns {
    args.push(arg_string(p))
  }
  let _ = self.command(args)
  ()
}

///|
/// `PUNSUBSCRIBE [pattern...]`: unsubscribe from the given patterns, or all when omitted.
pub async fn Client::punsubscribe(
  self : Client,
  patterns? : Array[String],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"PUNSUBSCRIBE"]
  match patterns {
    Some(ps) =>
      for p in ps {
        args.push(arg_string(p))
      }
    None => ()
  }
  let _ = self.command(args)
  ()
}

///|
/// `SSUBSCRIBE shardchannel...`: subscribe to shard channels (cluster pub/sub), which route
/// to a single shard rather than every node.
pub async fn Client::ssubscribe(
  self : Client,
  channels : Array[String],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"SSUBSCRIBE"]
  for c in channels {
    args.push(arg_string(c))
  }
  let _ = self.command(args)
  ()
}

///|
/// `SUNSUBSCRIBE [shardchannel...]`: unsubscribe from the given shard channels, or all when
/// omitted.
pub async fn Client::sunsubscribe(
  self : Client,
  channels? : Array[String],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"SUNSUBSCRIBE"]
  match channels {
    Some(cs) =>
      for c in cs {
        args.push(arg_string(c))
      }
    None => ()
  }
  let _ = self.command(args)
  ()
}

///|
/// `PUBLISH channel message`: post `message` to `channel`, returning how many subscribers
/// received it. (Publishing is an ordinary command, not a subscription.)
pub async fn Client::publish(
  self : Client,
  channel : String,
  message : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([b"PUBLISH", arg_string(channel), arg_string(message)]),
  )
}

///|
/// `SPUBLISH shardchannel message`: post `message` to a shard channel, returning how many
/// subscribers received it.
pub async fn Client::spublish(
  self : Client,
  channel : String,
  message : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([b"SPUBLISH", arg_string(channel), arg_string(message)]),
  )
}

///|
/// Decode a frame element as text.
fn string_of(value : @resp.RespValue) -> String? {
  match value {
    @resp.SimpleString(s) => Some(s)
    @resp.BulkString(b) => Some(@utf8.decode_lossy(b[:]))
    _ => None
  }
}

///|
/// Decode a frame element as binary payload.
fn bytes_of(value : @resp.RespValue) -> Bytes? {
  match value {
    @resp.BulkString(b) => Some(b)
    _ => None
  }
}
