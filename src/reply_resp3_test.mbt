// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a RESP3 map, set or push reads as RESP2's flat array" {
  let a = @resp.BulkString(b"a")
  let b = @resp.BulkString(b"b")
  assert_eq(@moonredis.expect_array(@resp.Array([a, b])), [a, b])
  assert_eq(@moonredis.expect_array(@resp.RespSet([a, b])), [a, b])
  assert_eq(@moonredis.expect_array(@resp.Push([a, b])), [a, b])
  assert_eq(@moonredis.expect_array(@resp.RespMap([(a, b)])), [a, b])
  assert_eq(@moonredis.expect_array(@resp.Null), [])
}
