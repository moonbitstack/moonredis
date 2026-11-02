// A real redis connection over TCP or TLS. It speaks the RESP wire the parent package
// defines, negotiates RESP2/RESP3 with `HELLO`, authenticates, selects a database, and
// supports client-side caching via `CLIENT TRACKING`. Push frames that arrive out of band
// are queued rather than returned as the command reply, so a subscription or an
// invalidation does not corrupt a request/reply exchange.

///|
/// A live redis connection: the socket, its optional TLS, and the push frames read since
/// the last command.
pub struct Connection {
  conn : @tcp.Conn
  mut pushes : Array[@resp.RespValue]
}

///|
/// Open a connection described by `options`: dial, then negotiate the protocol, authenticate,
/// select the database, and enable tracking when asked.
pub async fn Connection::connect(
  options : @moonredis.ClientOptions,
) -> Connection raise @moonredis.RedisError {
  let tcp = try {
    match options.tls {
      Some(config) => @tcp.dial(options.host, port=options.port, tls=config)
      None => @tcp.dial(options.host, port=options.port)
    }
  } catch {
    _ => raise @moonredis.Connection("failed to connect to " + options.host)
  }
  let conn : Connection = { conn: tcp, pushes: [], }
  conn.handshake(options)
  conn
}

///|
/// Negotiate the protocol and session: `HELLO` for RESP3 (which also authenticates and
/// selects), falling back to `AUTH`/`SELECT` for a server too old for `HELLO`; then
/// `SELECT` if the protocol was already RESP2; then enable tracking.
async fn Connection::handshake(
  self : Connection,
  options : @moonredis.ClientOptions,
) -> Unit raise @moonredis.RedisError {
  let mut hello_done = false
  match options.protocol {
    @moonredis.Resp3 =>
      hello_done = try {
        let _ = self.execute(hello_args(options))
        true
      } catch {
        @moonredis.Reply(_) => false
        _ => false
      }
    @moonredis.Resp2 => ()
  }
  if !hello_done {
    self.auth_resp2(options)
  }
  if options.db != 0 {
    let _ = self.execute([b"SELECT", @utf8.encode(options.db.to_string())])
  }
  if options.tracking.enabled {
    self.enable_tracking(options.tracking)
  }
}

///|
/// The `HELLO` argument array: the version, plus `AUTH user password` when credentials are
/// set so the negotiation authenticates in one round trip.
fn hello_args(options : @moonredis.ClientOptions) -> Array[Bytes] {
  let version = @moonredis.protocol_version(options.protocol)
  let args : Array[Bytes] = [b"HELLO", @utf8.encode(version.to_string())]
  match (options.username, options.password) {
    (Some(user), Some(password)) => {
      args.push(b"AUTH")
      args.push(@utf8.encode(user))
      args.push(@utf8.encode(password))
    }
    (None, Some(password)) => {
      args.push(b"AUTH")
      args.push(b"default")
      args.push(@utf8.encode(password))
    }
    _ => ()
  }
  args
}

///|
/// RESP2 authentication: `AUTH password` or `AUTH user password`.
async fn Connection::auth_resp2(
  self : Connection,
  options : @moonredis.ClientOptions,
) -> Unit raise @moonredis.RedisError {
  match (options.username, options.password) {
    (Some(user), Some(password)) => {
      let _ = self.execute([b"AUTH", @utf8.encode(user), @utf8.encode(password)])
    }
    (None, Some(password)) => {
      let _ = self.execute([b"AUTH", @utf8.encode(password)])
    }
    _ => ()
  }
}

///|
/// `CLIENT TRACKING ON [BCAST] [OPTIN] [OPTOUT] [NOLOOP] [REDIRECT id]`: turn on
/// client-side caching with the caller's policy.
async fn Connection::enable_tracking(
  self : Connection,
  tracking : @moonredis.TrackingOptions,
) -> Unit raise @moonredis.RedisError {
  let args : Array[Bytes] = [b"CLIENT", b"TRACKING", b"ON"]
  if tracking.bcast {
    args.push(b"BCAST")
  }
  if tracking.optin {
    args.push(b"OPTIN")
  }
  if tracking.optout {
    args.push(b"OPTOUT")
  }
  if tracking.noloop {
    args.push(b"NOLOOP")
  }
  match tracking.redirect {
    Some(id) => {
      args.push(b"REDIRECT")
      args.push(@utf8.encode(id.to_string()))
    }
    None => ()
  }
  let _ = self.execute(args)
}

///|
pub extend Connection with @moonredis.RedisConn::{execute, execute_all}

///|
pub impl @moonredis.RedisConn for Connection with fn execute(
  self,
  args : Array[Bytes],
) -> @resp.RespValue raise @moonredis.RedisError {
  write_bytes(self.conn, @resp.resp_encode_command(args))
  read_reply(self.conn, self.pushes)
}

///|
pub impl @moonredis.RedisConn for Connection with fn execute_all(
  self,
  commands : Array[Array[Bytes]],
) -> Array[@resp.RespValue] raise @moonredis.RedisError {
  let wire = @buffer.Buffer()
  for args in commands {
    wire.write_bytes(@resp.resp_encode_command(args))
  }
  write_bytes(self.conn, wire.to_bytes())
  let replies = []
  for _ in commands {
    replies.push(read_reply(self.conn, self.pushes))
  }
  replies
}

///|
/// A connection that opens a new socket when the old one drops, up to `options.retry`, and
/// waits the policy's backoff between tries. Only for commands that are safe to send twice:
/// a socket that dies after writing cannot say whether redis ran the command.
pub async fn connect_retrying(
  options : @moonredis.ClientOptions,
) -> @moonredis.RetryConn raise @moonredis.RedisError {
  let first : &@moonredis.RedisConn = Connection::connect(options)
  @moonredis.RetryConn::new(
    first,
    options.retry,
    dial=() => {
      let next : &@moonredis.RedisConn = Connection::connect(options)
      next
    },
    wait=delay => @async.sleep(delay.to_int()),
  )
}

///|
/// Read replies, queueing any out-of-band push frames, until a command reply arrives.
async fn read_reply(
  conn : @tcp.Conn,
  pushes : Array[@resp.RespValue],
) -> @resp.RespValue raise @moonredis.RedisError {
  let value = read_value(conn)
  match value {
    @resp.Push(_) => {
      pushes.push(value)
      read_reply(conn, pushes)
    }
    _ => value
  }
}

///|
/// Write `data` to the socket, turning a transport failure into `Closed`.
async fn write_bytes(
  conn : @tcp.Conn,
  data : Bytes,
) -> Unit raise @moonredis.RedisError {
  conn.write(data) catch {
    _ => raise @moonredis.Closed
  }
}

///|
/// The push frames read since the last call, taken (and cleared) for a subscription reader.
pub fn Connection::take_pushes(self : Connection) -> Array[@resp.RespValue] {
  let out = self.pushes
  self.pushes = []
  out
}

///|
/// Read one RESP value from the socket. Mirrors the pure decoder in the `resp` package, but
/// reads incrementally so it can run against a stream.
async fn read_value(
  conn : @tcp.Conn,
) -> @resp.RespValue raise @moonredis.RedisError {
  let marker = read_exactly(conn, 1)[0]
  match marker {
    b'+' => @resp.SimpleString(read_line(conn))
    b'-' => @resp.Error(read_line(conn))
    b':' => @resp.Integer(read_int64(conn))
    b',' => @resp.Double(parse_double(read_line(conn)))
    b'(' => @resp.BigNumber(read_line(conn))
    b'#' => @resp.Boolean(read_line(conn) == "t")
    b'_' => {
      let _ = read_exactly(conn, 2)
      @resp.Null
    }
    b'$' => read_bulk(conn, false)
    b'!' => read_bulk(conn, true)
    b'=' => read_verbatim(conn)
    b'*' => {
      let count = read_count(conn)
      if count < 0 {
        @resp.Null
      } else {
        @resp.Array(read_elems(conn, count))
      }
    }
    b'~' => @resp.RespSet(read_elems(conn, read_count(conn)))
    b'>' => @resp.Push(read_elems(conn, read_count(conn)))
    b'%' => @resp.RespMap(read_map(conn))
    _ =>
      raise @moonredis.Protocol(
        "unknown RESP marker 0x" + marker.to_int().to_string(),
      )
  }
}

///|
/// Not part of the asynchronous test build help.
async fn read_bulk(
  conn : @tcp.Conn,
  is_error : Bool,
) -> @resp.RespValue raise @moonredis.RedisError {
  let len = read_count(conn)
  if len < 0 {
    return @resp.Null
  }
  let body = read_exactly(conn, len)
  let _ = read_exactly(conn, 2)
  if is_error {
    @resp.BulkError(@utf8.decode_lossy(body[:]))
  } else {
    @resp.BulkString(body)
  }
}

///|
async fn read_verbatim(
  conn : @tcp.Conn,
) -> @resp.RespValue raise @moonredis.RedisError {
  let len = read_count(conn)
  if len < 4 {
    raise @moonredis.Protocol("verbatim string too short")
  }
  let body = read_exactly(conn, len)
  let _ = read_exactly(conn, 2)
  let fmt = @utf8.decode_lossy(body[0:3])
  @resp.VerbatimString(fmt, body[4:len].to_owned())
}

///|
async fn read_elems(
  conn : @tcp.Conn,
  count : Int32,
) -> Array[@resp.RespValue] raise @moonredis.RedisError {
  let out : Array[@resp.RespValue] = []
  for _i = 0; _i < count; _i = _i + 1 {
    out.push(read_value(conn))
  }
  out
}

///|
async fn read_map(
  conn : @tcp.Conn,
) -> Array[(@resp.RespValue, @resp.RespValue)] raise @moonredis.RedisError {
  let count = read_count(conn)
  let out : Array[(@resp.RespValue, @resp.RespValue)] = []
  for _i = 0; _i < count; _i = _i + 1 {
    let key = read_value(conn)
    let value = read_value(conn)
    out.push((key, value))
  }
  out
}

///|
async fn read_line(conn : @tcp.Conn) -> String raise @moonredis.RedisError {
  let line = conn.read_until("\r\n") catch { _ => raise @moonredis.Closed }
  match line {
    Some(text) => text
    None => raise @moonredis.Closed
  }
}

///|
async fn read_int64(conn : @tcp.Conn) -> Int64 raise @moonredis.RedisError {
  let text = read_line(conn)
  @string.parse_int64(text) catch {
    _ => raise @moonredis.Protocol("invalid RESP integer: " + text)
  }
}

///|
async fn read_count(conn : @tcp.Conn) -> Int32 raise @moonredis.RedisError {
  let text = read_line(conn)
  @string.parse_int(text) catch {
    _ => raise @moonredis.Protocol("invalid RESP count: " + text)
  }
}

///|
async fn read_exactly(
  conn : @tcp.Conn,
  n : Int32,
) -> Bytes raise @moonredis.RedisError {
  conn.read_exactly(n) catch {
    _ => raise @moonredis.Closed
  }
}

///|
fn parse_double(text : String) -> Double raise @moonredis.RedisError {
  match text {
    "inf" | "+inf" => @double.infinity
    "-inf" => @double.neg_infinity
    "nan" => @double.not_a_number
    _ =>
      @string.parse_double(text) catch {
        _ => raise @moonredis.Protocol("invalid RESP double: " + text)
      }
  }
}
