// Sentinel routing. Redis Sentinel monitors masters and promotes a replica on failure; a
// client asks a sentinel for the current master address rather than hard-coding it. These
// are the resolution pieces, tested against fakes; the resolved `host:port` is then dialed
// as an ordinary client (see the socket package).

///|
/// `SENTINEL ...`: send a raw sentinel sub-command (the sub-command name is the first
/// `args` element), returning the reply.
pub async fn Client::sentinel(
  self : Client,
  args : Array[String],
) -> @resp.RespValue raise RedisError {
  let cmd : Array[Bytes] = [b"SENTINEL"]
  for a in args {
    cmd.push(arg_string(a))
  }
  self.command(cmd)
}

///|
/// `SENTINEL GET-MASTER-ADDR-BY-NAME name`: the current master's `(host, port)` for the
/// monitored master `name`, or `None` if the sentinel does not know it.
pub async fn Client::sentinel_get_master_addr_by_name(
  self : Client,
  name : String,
) -> (String, Int32)? raise RedisError {
  let reply = self.command([
    b"SENTINEL",
    b"GET-MASTER-ADDR-BY-NAME",
    arg_string(name),
  ])
  match reply {
    @resp.Array(items) => {
      guard items.length() >= 2 else { return None }
      let host = @utf8.decode_lossy(expect_bytes(items[0]).unwrap())
      let port = expect_number(items[1]).to_int()
      Some((host, port))
    }
    _ => None
  }
}

///|
/// A client that resolves a master address through a list of sentinel connections, trying
/// each in turn until one answers.
pub struct SentinelClient {
  sentinels : Array[&RedisConn]
}

///|
/// A sentinel client over `sentinels` (connection to each sentinel node).
pub fn SentinelClient::new(sentinels : Array[&RedisConn]) -> SentinelClient {
  { sentinels, }
}

///|
/// Resolve the master address for `name`, querying sentinels in order; the first answer
/// wins. Returns the `host:port` string to dial.
pub async fn SentinelClient::resolve(
  self : SentinelClient,
  name : String,
) -> String raise RedisError {
  for s in self.sentinels {
    let client = Client::new(s)
    match client.sentinel_get_master_addr_by_name(name) {
      Some((host, port)) => return host + ":" + port.to_string()
      None => ()
    }
  }
  raise Connection("no sentinel resolved master for " + name)
}
