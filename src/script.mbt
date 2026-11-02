///|
/// A Lua script run by its digest, as go-redis's `Script` runs one: loaded on first use, and
/// loaded again if the server has forgotten it.
pub struct Script {
  source : String
  priv mut digest : String?
}

///|
/// A script of `source`. Nothing is sent until `run`.
pub fn Script::new(source : String) -> Script {
  { source, digest: None, }
}

///|
/// Run the script over `keys` and `args`.
pub async fn Script::run(
  self : Script,
  client : Client,
  keys : Array[String],
  args : Array[String],
) -> @resp.RespValue raise RedisError {
  let digest = match self.digest {
    Some(digest) => digest
    None => self.load(client)
  }
  client.evalsha(digest, keys, args) catch {
    Reply(message) if is_noscript(message) =>
      client.evalsha(self.load(client), keys, args)
    e => raise e
  }
}

///|
async fn Script::load(
  self : Script,
  client : Client,
) -> String raise RedisError {
  let digest = client.script_load(self.source)
  self.digest = Some(digest)
  digest
}
