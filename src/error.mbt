// Errors the client raises, and the helpers that pull a redis error reply apart into the
// redirect or state a caller acts on. A redis error reply is one value among the others a
// command returns, so the client turns it into `RedisError::Reply`; transport failures and a
// closed connection are `Connection` and `Closed`; a reply the client cannot make sense of is
// `Protocol`.

///|
/// Why a redis call failed: a redis error reply, a transport failure, a closed
/// connection, a reply the client could not interpret as the command promised, or a
/// transaction a watched key changed under.
#derive(Eq, Debug)
pub(all) suberror RedisError {
  Reply(String)
  Connection(String)
  Protocol(String)
  Closed
  Aborted
}

///|
pub extend RedisError with Debug::{to_repr}

///|
pub extend RedisError with Eq::{not_equal, equal}

///|
/// The client's reply when a command returns a redis error value, or `Protocol` when the
/// reply is not an error value at all but also not the shape the command expected.
pub fn reply_error(reply : @resp.RespValue) -> RedisError {
  match reply {
    @resp.Error(msg) => Reply(msg)
    @resp.BulkError(msg) => Reply(msg)
    other => Protocol("unexpected reply: " + @resp.resp_kind(other))
  }
}

///|
/// Where a cluster node sent a command.
#derive(Eq, Debug)
pub(all) enum Redirect {
  /// The slot lives there now, so route it there from here on.
  Moved(slot~ : Int32, node~ : String)
  /// The slot is migrating and this key has gone ahead: ask there this once, after `ASKING`.
  Ask(slot~ : Int32, node~ : String)
}

///|
pub extend Redirect with Debug::{to_repr}

///|
pub extend Redirect with Eq::{not_equal, equal}

///|
/// What a `MOVED` or `ASK` error reply points at; `None` when the message is neither.
pub fn redirect(msg : String) -> Redirect? {
  let space = msg.find(" ")
  guard space is Some(at) else { return None }
  let tag = msg[0:at].to_owned()
  if tag != "MOVED" && tag != "ASK" {
    return None
  }
  let rest = msg[at + 1:].to_owned()
  let second = rest.find(" ")
  guard second is Some(at2) else { return None }
  let slot_text = rest[0:at2].to_owned()
  let node = rest[at2 + 1:].to_owned()
  let slot = @string.parse_int(slot_text) catch { _ => return None }
  Some(if tag == "MOVED" { Moved(slot~, node~) } else { Ask(slot~, node~) })
}

///|
/// Whether a redis error reply is the `NOSCRIPT` a forgotten script digest draws, so a
/// `Script` reloads and retries.
pub fn is_noscript(msg : String) -> Bool {
  msg.has_prefix("NOSCRIPT")
}

///|
/// Whether a redis error reply is a `CLUSTERDOWN`, the cluster unable to serve.
pub fn is_cluster_down(msg : String) -> Bool {
  msg.has_prefix("CLUSTERDOWN")
}
