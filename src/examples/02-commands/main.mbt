// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The typed commands against an in-memory fake connection: no server, so it shows the
/// command surface and how a reply decodes into MoonBit values.
///
///     moon run src/examples/02-commands
#coverage.skip
async fn main {
  let replies = [
    @resp.SimpleString("OK"),
    @resp.BulkString(b"world"),
    @resp.Integer(1),
  ]
  let client = @moonredis.Client::new(@moonredis.FakeConn::new(replies))
  let stored = client.set("hello", "world") catch { _ => false }
  println("SET hello world -> " + stored.to_string())
  let got = client.get("hello") catch { _ => None }
  match got {
    Some(bytes) => println("GET hello -> " + @utf8.decode_lossy(bytes[:]))
    None => println("GET hello -> (nil)")
  }
  let existed = client.exists(["hello"]) catch { _ => 0 }
  println("EXISTS hello -> " + existed.to_string())
}
