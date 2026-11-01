// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The RESP codec on its own: what a command looks like on the wire, and what a reply
/// decodes to. No server needed.
///
///     moon run src/examples/01-resp
#coverage.skip
fn main {
  let wire = @resp.resp_command(["SET", "greeting", "hello"])
  println("SET greeting hello becomes:")
  println(@utf8.decode_lossy(wire[:]))
  let reply = @resp.RespValue::decode(b"$5\r\nhello\r\n") catch {
    _ => @resp.Null
  }
  println("a bulk-string reply decodes to kind: " + @resp.resp_kind(reply))
  let integer = @resp.RespValue::decode(b":42\r\n") catch { _ => @resp.Null }
  println("an integer reply decodes to kind: " + @resp.resp_kind(integer))
}
