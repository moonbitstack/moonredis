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
/// redis error reply to surface at once.
pub struct RetryConn {
  inner : &RedisConn
  retry : RetryOptions
}

///|
/// A retrying view of `inner` under `retry`.
pub fn RetryConn::new(inner : &RedisConn, retry : RetryOptions) -> RetryConn {
  { inner, retry, }
}

///|
pub extend RetryConn with RedisConn::{execute}

///|
pub impl RedisConn for RetryConn with fn execute(self, args : Array[Bytes]) -> @resp.RespValue raise RedisError {
  self.attempt(args, 0)
}

///|
/// Try `args`; on a retryable failure, try again with the next attempt index.
async fn RetryConn::attempt(
  self : RetryConn,
  args : Array[Bytes],
  attempt : Int32,
) -> @resp.RespValue raise RedisError {
  self.inner.execute(args) catch {
    err =>
      if should_retry(err, attempt, self.retry) {
        self.attempt(args, attempt + 1)
      } else {
        raise err
      }
  }
}
