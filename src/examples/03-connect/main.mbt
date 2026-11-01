// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A real connection over a socket: dial 127.0.0.1:6379, SET, then GET. Needs a redis; when
/// none is listening it says so and stops.
///
///     moon run src/examples/03-connect --target native
#coverage.skip
async fn main {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let conn = @socket.Connection::connect(options) catch {
    _ => {
      println("no redis at 127.0.0.1:6379; start one to run this example.")
      return
    }
  }
  let client = @moonredis.Client::new(conn)
  let stored = client.set("moonredis:example", "hello") catch { _ => false }
  println("SET moonredis:example hello -> " + stored.to_string())
  let got = client.get("moonredis:example") catch { _ => None }
  match got {
    Some(bytes) =>
      println("GET moonredis:example -> " + @utf8.decode_lossy(bytes[:]))
    None => println("GET moonredis:example -> (nil)")
  }
}
