// The configuration a connection and the client around it take: which server and how to
// authenticate, which RESP version to speak, and the pool, retry and client-side caching
// policies. Each policy is a record with a public preset of the market-standard defaults,
// so a caller overrides only what it must.

///|
/// Which RESP version to negotiate with `HELLO`. RESP2 is the long-standing wire; RESP3
/// adds the typed null, boolean, double, map, set and push values and is required for
/// client-side caching.
pub(all) enum Protocol {
  Resp2
  Resp3
}

///|
/// The `HELLO` version argument each protocol negotiates.
pub fn protocol_version(protocol : Protocol) -> Int32 {
  match protocol {
    Resp2 => 2
    Resp3 => 3
  }
}

///|
/// The pool a client draws connections from: its size bounds, how long an idle
/// connection lives, and whether a borrowed connection is checked before use.
pub(all) struct PoolOptions {
  /// The most idle connections kept ready; the pool drops idle ones past it. 10, as in
  /// `go-redis`'s `MaxIdle`.
  max_idle : Int32
  /// The most connections open at once; 0 means no cap, as `go-redis` defaults
  /// (`PoolSize`/`MaxActive` 0).
  max_active : Int32
  /// The fewest connections kept warm, so a burst does not open them all at once. 1, as
  /// `go-redis`'s `MinIdleConns`.
  min_idle : Int32
  /// How long an idle connection is kept before reclaim, in milliseconds. 300000 (5
  /// minutes), as `go-redis`'s `IdleTimeout`.
  idle_timeout : Int64
  /// Whether a connection is pinged before it is handed out. True, as `go-redis`'s
  /// `PoolFIFO` off and a live check on borrow.
  health_check : Bool
}

///|
pub let pool_default : PoolOptions = PoolOptions::{
  max_idle: 10,
  max_active: 0,
  min_idle: 1,
  idle_timeout: 300000,
  health_check: true,
}

///|
/// How a call retries after a transport failure: how many attempts in total, the backoff
/// between them and how hard it backs off.
pub(all) struct RetryOptions {
  /// Total attempts including the first; 3, as `go-redis`'s `MaxRetries`.
  attempts : Int32
  /// The delay before the first retry, in milliseconds. 100, as `go-redis`'s
  /// `MinRetryBackoff`/`MaxRetryBackoff` meet in the middle.
  base_delay : Int64
  /// The longest a retry waits, in milliseconds. 2000, as `go-redis`'s
  /// `MaxRetryBackoff`.
  max_delay : Int64
  /// The 0-9 aggressiveness of the backoff growth; each step waits `base * level^step`.
  /// 1 (linear), as `go-redis`'s near-linear backoff.
  level : Int32
  /// Whether to scatter retries by up to a quarter of the delay, so many clients do not
  /// retry in lockstep. True.
  jitter : Bool
}

///|
pub let retry_default : RetryOptions = RetryOptions::{
  attempts: 3,
  base_delay: 100,
  max_delay: 2000,
  level: 1,
  jitter: true,
}

///|
/// Client-side caching (`CLIENT TRACKING`): whether keys this client reads are tracked so
/// redis pushes invalidations, and in which mode.
pub(all) struct TrackingOptions {
  /// Whether tracking is on. False; it is off until a caller opts in.
  enabled : Bool
  /// Broadcast mode, where redis tracks and invalidates by prefix rather than per client
  /// table. False.
  bcast : Bool
  /// Opt-in tracking: only keys read inside a `CLIENT CACHING yes` block are tracked.
  /// False.
  optin : Bool
  /// Opt-out tracking: every read is tracked unless opted out. False.
  optout : Bool
  /// Suppress the invalidation echoed back to the client that caused it. False.
  noloop : Bool
  /// Track to another client's table by its ID (the redirect target pattern), rather
  /// than this connection's. None.
  redirect : Int64?
}

///|
pub let tracking_default : TrackingOptions = TrackingOptions::{
  enabled: false,
  bcast: false,
  optin: false,
  optout: false,
  noloop: false,
  redirect: None,
}

///|
/// Everything needed to reach and speak to a redis: the endpoint and credentials, the
/// protocol, the timeouts, and the pool, retry and tracking policies.
pub(all) struct ClientOptions {
  /// The host to dial. `127.0.0.1`.
  host : String
  /// The port to dial; 6379, redis's well-known port (not the organisation's 12000,
  /// which is for the servers this project serves).
  port : Int32
  /// The ACL username, when redis runs with ACL accounts. None (the default user).
  username : String?
  /// The password, for AUTH. None.
  password : String?
  /// The logical database to `SELECT` on connect. 0.
  db : Int32
  /// The RESP version to negotiate. Resp3.
  protocol : Protocol
  /// The TLS client config, when the connection is encrypted. None (cleartext).
  tls : @tls.Client?
  /// How long to wait for a connection to open, in milliseconds. 5000.
  connect_timeout : Int64
  /// How long to wait for a reply, in milliseconds. 0 means no bound.
  read_timeout : Int64
  /// How long to wait to enqueue a write, in milliseconds. 0 means no bound.
  write_timeout : Int64
  /// The pool policy.
  pool : PoolOptions
  /// The retry policy.
  retry : RetryOptions
  /// The client-side caching policy.
  tracking : TrackingOptions
}

///|
pub let client_default : ClientOptions = ClientOptions::{
  host: "127.0.0.1",
  port: 6379,
  username: None,
  password: None,
  db: 0,
  protocol: Resp3,
  tls: None,
  connect_timeout: 5000,
  read_timeout: 0,
  write_timeout: 0,
  pool: pool_default,
  retry: retry_default,
  tracking: tracking_default,
}

///|
/// `ClientOptions` at `host:port`, over the standard defaults (RESP3, database 0, no TLS).
pub fn ClientOptions::at(host : String, port : Int32) -> ClientOptions {
  { ..client_default, host, port, }
}

///|
/// A copy of `self` that authenticates with `username` and `password`.
pub fn ClientOptions::with_auth(
  self : ClientOptions,
  username : String?,
  password : String?,
) -> ClientOptions {
  { ..self, username, password, }
}

///|
/// A copy of `self` that `SELECT`s `db` on connect.
pub fn ClientOptions::with_db(
  self : ClientOptions,
  db : Int32,
) -> ClientOptions {
  { ..self, db, }
}

///|
/// The delay before retry number `attempt` (0-based), growing as `base * level^attempt`
/// and capped at `max_delay`. The transport adds jitter when the policy asks for it.
pub fn backoff_delay(attempt : Int32, retry : RetryOptions) -> Int64 {
  let step = if attempt < 0 { 0 } else { attempt }
  let level = if retry.level <= 0 { 1 } else { retry.level }
  let factor = ipow(level, step)
  let raw = retry.base_delay * factor
  if raw < 0 || raw > retry.max_delay {
    retry.max_delay
  } else {
    raw
  }
}

///|
fn ipow(base : Int32, exp : Int32) -> Int64 {
  if exp <= 0 {
    return 1
  }
  let mut result : Int64 = base.to_int64()
  for _i = 1; _i < exp; _i = _i + 1 {
    result = result * base.to_int64()
    if result > 9223372036854775807 {
      return 9223372036854775807
    }
  }
  result
}
