// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A pipeline sends its commands together; a transaction over a watched key stops when
/// another connection writes that key first. Needs a redis; when none is listening it says
/// so and stops.
///
///     moon run src/examples/04-pipeline --target native
#coverage.skip
async fn main {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let mine = @socket.Connection::connect(options) catch {
    _ => {
      println("no redis at 127.0.0.1:6379; start one to run this example.")
      return
    }
  }
  let theirs = @socket.Connection::connect(options)
  let batch = @moonredis.Pipeline::new(mine)
  for _ in 0..<100 {
    batch.add([b"INCR", b"moonredis:example:count"])
  }
  let replies = batch.execute()
  println(
    "100 INCR in one round trip, last reply: \{@resp.resp_kind(replies[99])}",
  )

  let client = @moonredis.Client::new(mine)
  client.watch(["moonredis:example:count"])
  ignore(@moonredis.Client::new(theirs).set("moonredis:example:count", "0"))
  let transaction = @moonredis.Pipeline::new(mine)
  transaction.multi()
  transaction.add([b"INCR", b"moonredis:example:count"])
  try {
    ignore(transaction.execute())
    println("the transaction ran")
  } catch {
    @moonredis.Aborted => println("the watched key changed, so nothing ran")
    e => raise e
  }
  ignore(client.del(["moonredis:example:count"]))
}
