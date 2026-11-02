// Retry policy and a retrying connection. A transport failure (a dropped connection or a
// closed socket) is transient and worth another attempt; a redis error reply is not, since
// the server answered. `backoff_delay` gives a transport the wait between attempts;
// `RetryConn` applies the policy in front of any connection.

///|
/// Whether an error on `attempt` (0-based, the attempt that just failed) is worth retrying
/// under `retry`: only a transport failure, and only while attempts remain.
pub fn should_retry(
  error : RedisError,
  attempt : Int32,
  retry : RetryOptions,
) -> Bool {
  if attempt + 1 >= retry.attempts {
    return false
  }
  match error {
    Connection(_) | Closed => true
    _ => false
  }
}

///|
/// A connection that retries transport failures up to `retry.attempts` times, leaving a
/// redis error reply to surface at once. A dropped connection stays dropped, so a retry that
/// is to reach the server needs `dial` to open another; `wait` sleeps for the backoff.
/// `@socket.connect_retrying` wires both.
pub struct RetryConn {
  mut inner : &RedisConn
  retry : RetryOptions
  dial : (async () -> &RedisConn raise RedisError)?
  wait : (async (Int64) -> Unit noraise)?
}

///|
/// A retrying view of `inner` under `retry`.
pub fn RetryConn::new(
  inner : &RedisConn,
  retry : RetryOptions,
  dial? : async () -> &RedisConn raise RedisError,
  wait? : async (Int64) -> Unit noraise,
) -> RetryConn {
  { inner, retry, dial, wait, }
}

///|
pub extend RetryConn with RedisConn::{execute, execute_all}

///|
pub impl RedisConn for RetryConn with fn execute(self, args : Array[Bytes]) -> @resp.RespValue raise RedisError {
  for attempt = 0; ; attempt = attempt + 1 {
    let failure : RedisError = try {
      if attempt > 0 && self.dial is Some(dial) {
        self.inner = dial()
      }
      return self.inner.execute(args)
    } catch {
      e => e
    }
    guard should_retry(failure, attempt, self.retry) else { raise failure }
    if self.wait is Some(wait) {
      wait(backoff_delay(attempt, self.retry))
    }
  }
}
