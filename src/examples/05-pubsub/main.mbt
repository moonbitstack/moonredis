// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A pattern subscription hears a channel it matches. Needs a redis; when none is listening it
/// says so and stops.
///
///     moon run src/examples/05-pubsub --target native
#coverage.skip
async fn main {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let listener = @socket.Connection::connect(options) catch {
    _ => {
      println("no redis at 127.0.0.1:6379; start one to run this example.")
      return
    }
  }
  let speaker = @socket.Connection::connect(options)
  let subscription = @socket.Subscription::subscribe(
    listener,
    ["moonredis:news.*"],
    pattern=true,
  )
  let heard = @moonredis.Client::new(speaker).publish(
    "moonredis:news.today", "hello",
  )
  println("\{heard} subscriber heard it")
  if subscription.next() is Some(message) {
    println(message.channel + " -> " + @utf8.decode_lossy(message.payload[:]))
  }
}
