// The connection and server commands, named as in redis-py. These manage the session
// (auth, select, client name) and the server (info, flush, config, slow log, replication).

///|
/// `PING`: a round-trip health check, returning the server's `PONG` text.
pub async fn Client::ping(self : Client) -> String raise RedisError {
  expect_string_value(self.command([b"PING"]))
}

///|
/// `PING message`: echo `message` back, confirming the connection.
pub async fn Client::ping_message(
  self : Client,
  message : String,
) -> String raise RedisError {
  expect_string_value(self.command([b"PING", arg_string(message)]))
}

///|
/// `ECHO message`: return `message` unchanged (a larger round-trip probe than `PING`).
pub async fn Client::echo(
  self : Client,
  message : String,
) -> Bytes raise RedisError {
  expect_bytes(self.command([b"ECHO", arg_string(message)])).unwrap()
}

///|
/// `SELECT index`: switch the connection to logical database `index`.
pub async fn Client::select(
  self : Client,
  index : Int32,
) -> Unit raise RedisError {
  status_ok(self.command([b"SELECT", arg_int(index)]))
}

///|
/// `AUTH password`: authenticate with the default user.
pub async fn Client::auth(
  self : Client,
  password : String,
) -> Unit raise RedisError {
  status_ok(self.command([b"AUTH", arg_string(password)]))
}

///|
/// `AUTH user password`: authenticate with a named ACL account.
pub async fn Client::auth_user(
  self : Client,
  username : String,
  password : String,
) -> Unit raise RedisError {
  status_ok(self.command([b"AUTH", arg_string(username), arg_string(password)]))
}

///|
/// `INFO [section]`: the server's key/value metrics, as the raw text block redis returns.
pub async fn Client::info(
  self : Client,
  section? : String,
) -> String raise RedisError {
  let args : Array[Bytes] = [b"INFO"]
  match section {
    Some(s) => args.push(arg_string(s))
    None => ()
  }
  expect_string_value(self.command(args))
}

///|
/// `DBSIZE`: the number of keys in the selected database.
pub async fn Client::dbsize(self : Client) -> Int64 raise RedisError {
  expect_int64(self.command([b"DBSIZE"]))
}

///|
/// `FLUSHDB [ASYNC|SYNC]`: delete every key in the selected database.
pub async fn Client::flushdb(
  self : Client,
  sync? : Bool,
) -> Unit raise RedisError {
  self.flush_target(b"FLUSHDB", sync)
}

///|
/// `FLUSHALL [ASYNC|SYNC]`: delete every key in every database.
pub async fn Client::flushall(
  self : Client,
  sync? : Bool,
) -> Unit raise RedisError {
  self.flush_target(b"FLUSHALL", sync)
}

///|
/// Build and send a `FLUSHDB`/`FLUSHALL`, choosing the sync mode.
async fn Client::flush_target(
  self : Client,
  op : Bytes,
  sync : Bool?,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [op]
  match sync {
    Some(true) => args.push(b"SYNC")
    Some(false) => args.push(b"ASYNC")
    None => ()
  }
  status_ok(self.command(args))
}

///|
/// `SWAPDB a b`: atomically swap the data of databases `a` and `b`.
pub async fn Client::swapdb(
  self : Client,
  a : Int32,
  b : Int32,
) -> Unit raise RedisError {
  status_ok(self.command([b"SWAPDB", arg_int(a), arg_int(b)]))
}

///|
/// `TIME`: the server's current time as (seconds, microseconds).
pub async fn Client::time_(self : Client) -> (Int64, Int64) raise RedisError {
  let items = expect_array(self.command([b"TIME"]))
  guard items.length() >= 2 else { raise Protocol("unexpected TIME reply") }
  (expect_number(items[0]), expect_number(items[1]))
}

///|
/// `LASTSAVE`: the Unix timestamp of the last successful save to disk.
pub async fn Client::lastsave(self : Client) -> Int64 raise RedisError {
  expect_int64(self.command([b"LASTSAVE"]))
}

///|
/// `SAVE`: synchronously save the dataset to disk (blocks the server).
pub async fn Client::save(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"SAVE"]))
}

///|
/// `BGSAVE`: start a background save, returning the status line.
pub async fn Client::bgsave(self : Client) -> String raise RedisError {
  expect_string_value(self.command([b"BGSAVE"]))
}

///|
/// `BGREWRITEAOF`: start a background rewrite of the append-only file.
pub async fn Client::bgrewriteaof(self : Client) -> String raise RedisError {
  expect_string_value(self.command([b"BGREWRITEAOF"]))
}

///|
/// `SHUTDOWN [NOSAVE|SAVE]`: stop the server. The call normally raises `Closed` when the
/// connection drops, rather than returning.
pub async fn Client::shutdown(
  self : Client,
  save? : Bool,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"SHUTDOWN"]
  match save {
    Some(true) => args.push(b"SAVE")
    Some(false) => args.push(b"NOSAVE")
    None => ()
  }
  status_ok(self.command(args))
}

///|
/// `CONFIG GET parameter`: the current value(s) of a config parameter (which may match
/// several via a glob), as alternating name/value pairs.
pub async fn Client::config_get(
  self : Client,
  parameter : String,
) -> Array[(String, String)] raise RedisError {
  let items = expect_array(
    self.command([b"CONFIG", b"GET", arg_string(parameter)]),
  )
  decode_pairs(items)
}

///|
/// `CONFIG SET parameter value`: change a config parameter at runtime.
pub async fn Client::config_set(
  self : Client,
  parameter : String,
  value : String,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"CONFIG", b"SET", arg_string(parameter), arg_string(value)]),
  )
}

///|
/// `CONFIG REWRITE`: persist the running config to the config file.
pub async fn Client::config_rewrite(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"CONFIG", b"REWRITE"]))
}

///|
/// `CONFIG RESETSTAT`: reset the server's statistics counters.
pub async fn Client::config_resetstat(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"CONFIG", b"RESETSTAT"]))
}

///|
/// `CLIENT SETNAME name`: label this connection in `CLIENT LIST`.
pub async fn Client::client_setname(
  self : Client,
  name : String,
) -> Unit raise RedisError {
  status_ok(self.command([b"CLIENT", b"SETNAME", arg_string(name)]))
}

///|
/// `CLIENT GETNAME`: this connection's name, or `None` if unset.
pub async fn Client::client_getname(self : Client) -> String? raise RedisError {
  expect_string(self.command([b"CLIENT", b"GETNAME"]))
}

///|
/// `CLIENT ID`: this connection's numeric id.
pub async fn Client::client_id(self : Client) -> Int64 raise RedisError {
  expect_int64(self.command([b"CLIENT", b"ID"]))
}

///|
/// `CLIENT KILL [ID id] [ADDR host:port] [TYPE ...] [SKIPME yes/no]`: close matching
/// client connections.
pub async fn Client::client_kill(
  self : Client,
  filters : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"CLIENT", b"KILL"]
  for f in filters {
    args.push(arg_string(f))
  }
  // The filter form counts what it killed; the old `addr:port` form answers OK.
  match self.command(args) {
    @resp.SimpleString(_) => 1
    other => expect_int64(other)
  }
}

///|
/// `COMMAND COUNT`: the number of commands the server implements.
pub async fn Client::command_count(self : Client) -> Int64 raise RedisError {
  expect_int64(self.command([b"COMMAND", b"COUNT"]))
}

///|
/// `SLOWLOG GET [count]`: the most recent slow commands the server logged.
pub async fn Client::slowlog_get(
  self : Client,
  count? : Int32,
) -> Array[@resp.RespValue] raise RedisError {
  let args : Array[Bytes] = [b"SLOWLOG", b"GET"]
  match count {
    Some(n) => args.push(arg_int(n))
    None => ()
  }
  expect_array(self.command(args))
}

///|
/// `SLOWLOG LEN`: the number of entries in the slow log.
pub async fn Client::slowlog_len(self : Client) -> Int64 raise RedisError {
  expect_int64(self.command([b"SLOWLOG", b"LEN"]))
}

///|
/// `SLOWLOG RESET`: clear the slow log.
pub async fn Client::slowlog_reset(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"SLOWLOG", b"RESET"]))
}

///|
/// `REPLICAOF host port`: make this server a replica of `host:port`. Use `REPLICAOF NO ONE`
/// (via `replicaof_noone`) to promote it back to a master.
pub async fn Client::replicaof(
  self : Client,
  host : String,
  port : Int32,
) -> Unit raise RedisError {
  status_ok(self.command([b"REPLICAOF", arg_string(host), arg_int(port)]))
}

///|
/// `REPLICAOF NO ONE`: stop replicating and become a master.
pub async fn Client::replicaof_noone(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"REPLICAOF", b"NO", b"ONE"]))
}
