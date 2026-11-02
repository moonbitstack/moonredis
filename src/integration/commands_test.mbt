// Every command family against a live server, under both protocols: the two answer several
// commands in different shapes, and a reader that only knows one of them is wrong under the
// other while still compiling, connecting and not raising.

///|
/// Run `body` over database `db` under RESP2, then under RESP3. Tests run side by side, so each
/// family has a database of its own to flush.
async fn both_protocols(
  db : Int32,
  body : async (@moonredis.Client) -> Unit,
) -> Unit {
  for protocol in [@moonredis.Resp2, @moonredis.Resp3] {
    guard live(6379, protocol~, db~) is Some(conn) else { return }
    let client = @moonredis.Client::new(conn)
    client.flushdb()
    body(client)
    client.flushdb()
  }
}

///|
async test "strings" {
  both_protocols(1, c => {
    assert_true(c.set("s", "hello"))
    assert_eq(c.get("s"), Some(b"hello"))
    assert_eq(c.get("missing"), None)
    assert_eq(c.append("s", " world"), 11)
    assert_eq(c.strlen("s"), 11)
    assert_eq(c.getrange("s", 0, 4), b"hello")
    assert_eq(c.setrange("s", 6, "there"), 11)
    assert_eq(c.get("s"), Some(b"hello there"))
    assert_true(c.setnx("n", "1"))
    assert_false(c.setnx("n", "2"))
    assert_eq(c.incr("n"), 2)
    assert_eq(c.incrby("n", 5), 7)
    assert_eq(c.decr("n"), 6)
    assert_eq(c.decrby("n", 2), 4)
    c.mset([("a", "1"), ("b", "2")])
    assert_eq(c.mget(["a", "gone", "b"]), [Some(b"1"), None, Some(b"2")])
    assert_eq(c.getdel("a"), Some(b"1"))
    assert_eq(c.exists(["a"]), 0)
    assert_eq(c.set_get("b", "3"), Some(b"2"))
    assert_false(c.set("b", "4", nx=true))
    assert_true(c.set("b", "4", xx=true))
    c.setex("e", 100, "v")
    assert_true(c.ttl("e") > 0)
    c.psetex("p", 100000, "v")
    assert_true(c.pttl("p") > 0)
  })
}

///|
async test "keys" {
  both_protocols(2, c => {
    ignore(c.set("k", "v"))
    assert_eq(c.type_("k"), "string")
    assert_eq(c.type_("missing"), "none")
    assert_true(c.expire("k", 100))
    assert_true(c.ttl("k") > 0)
    assert_true(c.persist("k"))
    assert_eq(c.ttl("k"), -1)
    assert_eq(c.ttl("missing"), -2)
    assert_true(c.pexpire("k", 100000))
    c.rename("k", "r")
    ignore(c.set("t", "v"))
    assert_false(c.renamenx("r", "t"))
    assert_true(c.copy("r", "c"))
    assert_eq(c.get("c"), Some(b"v"))
    assert_eq(c.touch(["r", "t", "missing"]), 2)
    let names = c.keys("*")
    names.sort()
    assert_eq(names, ["c", "r", "t"])
    assert_eq(c.dbsize(), 3)
    assert_eq(c.unlink(["c"]), 1)
    let dumped = c.dump("r").unwrap()
    c.restore("back", 0, dumped)
    assert_eq(c.get("back"), Some(b"v"))
    assert_eq(c.object_encoding("r"), "embstr")
    let (cursor, batch) = c.scan("0", pattern="*", count=100)
    assert_eq(cursor, "0")
    assert_eq(batch.length(), 3)
    assert_true(c.randomkey() is Some(_))
    assert_true(c.expireat("r", 4000000000))
    assert_true(c.pexpireat("t", 4000000000000))
    assert_eq(c.object_refcount("r") >= 1, true)
    assert_eq(c.object_idletime("r") >= 0, true)
    assert_true(c.move_("back", 15))
    assert_eq(c.get("back"), None)
    c.select(15)
    assert_eq(c.get("back"), Some(b"v"))
    assert_eq(c.del(["back"]), 1)
    c.select(2)
  })
}

///|
async test "hashes" {
  both_protocols(3, c => {
    assert_eq(c.hset("h", [("a", "1"), ("b", "2")]), 2)
    assert_eq(c.hget("h", "a"), Some(b"1"))
    assert_eq(c.hget("h", "z"), None)
    assert_true(c.hexists("h", "a"))
    assert_false(c.hexists("h", "z"))
    assert_true(c.hsetnx("h", "c", "3"))
    assert_false(c.hsetnx("h", "c", "4"))
    assert_eq(c.hlen("h"), 3)
    assert_eq(c.hmget("h", ["a", "z"]), [Some(b"1"), None])
    let all = c.hgetall("h")
    all.sort()
    assert_eq(all, [("a", "1"), ("b", "2"), ("c", "3")])
    let names = c.hkeys("h")
    names.sort()
    assert_eq(names, ["a", "b", "c"])
    let values = c.hvals("h")
    values.sort()
    assert_eq(values, ["1", "2", "3"])
    assert_eq(c.hincrby("h", "a", 4), 5)
    assert_eq(c.hincrbyfloat("h", "f", 1.5), 1.5)
    assert_eq(c.hstrlen("h", "a"), 1)
    assert_eq(c.hdel("h", ["a", "z"]), 1)
    let (cursor, pairs) = c.hscan("h", "0", pattern="*", count=100)
    assert_eq(cursor, "0")
    assert_eq(pairs.length(), 3)
    assert_eq(c.hrandfield("missing"), [])
    assert_eq(c.hrandfield("h").length(), 1)
    assert_eq(c.hrandfield("h", count=2).length(), 2)
    assert_eq(c.hrandfield_values("h", 2).length(), 2)
    let lone = c.hrandfield_values("h", -1)
    assert_true(all.iter().any(p => p.0 == lone[0].0) || lone[0].0 == "f")
  })
}

///|
async test "lists" {
  both_protocols(4, c => {
    assert_eq(c.rpush("l", ["a", "b", "c"]), 3)
    assert_eq(c.lpush("l", ["z"]), 4)
    assert_eq(c.lrange("l", 0, -1), [b"z", b"a", b"b", b"c"])
    assert_eq(c.llen("l"), 4)
    assert_eq(c.lindex("l", 1), Some(b"a"))
    assert_eq(c.lindex("l", 9), None)
    c.lset("l", 0, "y")
    assert_eq(c.linsert("l", "BEFORE", "a", "x"), 5)
    assert_eq(c.lrem("l", 0, "x"), 1)
    assert_eq(c.lpop("l"), Some(b"y"))
    assert_eq(c.rpop("l"), Some(b"c"))
    assert_eq(c.lpop("missing"), None)
    assert_eq(c.rpush("m", ["1", "2", "3", "4"]), 4)
    assert_eq(c.lpopn("m", 2), [b"1", b"2"])
    assert_eq(c.rpopn("m", 1), [b"4"])
    assert_eq(c.lmove("m", "n", "LEFT", "RIGHT"), Some(b"3"))
    assert_eq(c.blpop(["n"], 1), Some(("n", b"3")))
    assert_eq(c.blpop(["n"], 1), None)
    assert_eq(c.lpushx("missing", ["a"]), 0)
    assert_eq(c.rpushx("missing", ["a"]), 0)
    assert_eq(c.rpush("q", ["1", "2"]), 2)
    assert_eq(c.rpoplpush("q", "r"), Some(b"2"))
    assert_eq(c.brpoplpush("q", "r", 1), Some(b"1"))
    assert_eq(c.brpop(["r"], 1), Some(("r", b"2")))
    assert_eq(c.blmove("r", "s", "LEFT", "LEFT", 1), Some(b"1"))
    assert_eq(c.blmove("missing", "s", "LEFT", "LEFT", 1), None)
    assert_eq(c.rpush("t", ["1", "2", "3"]), 3)
    c.ltrim("t", 0, 0)
    assert_eq(c.lrange("t", 0, -1), [b"1"])
  })
}

///|
async test "sets" {
  both_protocols(5, c => {
    assert_eq(c.sadd("a", ["1", "2", "3"]), 3)
    assert_eq(c.sadd("b", ["2", "3", "4"]), 3)
    assert_eq(c.scard("a"), 3)
    assert_true(c.sismember("a", "1"))
    assert_false(c.sismember("a", "9"))
    let members = c.smembers("a")
    members.sort()
    assert_eq(members, ["1", "2", "3"])
    let shared = c.sinter(["a", "b"])
    shared.sort()
    assert_eq(shared, ["2", "3"])
    assert_eq(c.sdiff(["a", "b"]), ["1"])
    assert_eq(c.sunion(["a", "b"]).length(), 4)
    assert_eq(c.sinterstore("i", ["a", "b"]), 2)
    assert_eq(c.sunionstore("u", ["a", "b"]), 4)
    assert_eq(c.sdiffstore("d", ["a", "b"]), 1)
    assert_true(c.smove("a", "b", "1"))
    assert_eq(c.srem("a", ["2", "9"]), 1)
    assert_true(c.spop("a") is Some(_))
    assert_eq(c.spop("a"), None)
    assert_true(c.srandmember("b") is Some(_))
    assert_eq(c.srandmembern("b", 2).length(), 2)
    let (cursor, batch) = c.sscan("b", "0", pattern="*", count=100)
    assert_eq(cursor, "0")
    assert_eq(batch.length(), 4)
  })
}

///|
async test "sorted sets" {
  both_protocols(6, c => {
    assert_eq(c.zadd("z", [("a", 1), ("b", 2), ("c", 3)]), 3)
    assert_eq(c.zadd("z", [("a", 9)], nx=true), 0)
    assert_eq(c.zadd("z", [("a", 1.5)], xx=true, ch=true), 1)
    assert_eq(c.zscore("z", "a"), Some(1.5))
    assert_eq(c.zscore("z", "missing"), None)
    assert_eq(c.zcard("z"), 3)
    assert_eq(c.zcount("z", "1", "2"), 2)
    assert_eq(c.zrange("z", 0, -1), ["a", "b", "c"])
    assert_eq(c.zrevrange("z", 0, 0), ["c"])
    assert_eq(c.zrange_scores("z", 0, 0), [("a", 1.5)])
    assert_eq(c.zrevrange_scores("z", 0, 0), [("c", 3)])
    assert_eq(c.zrangebyscore("z", "2", "+inf"), ["b", "c"])
    assert_eq(c.zrevrangebyscore("z", "+inf", "2", offset=0, count=1), ["c"])
    assert_eq(c.zrangebyscore_scores("z", "3", "3"), [("c", 3)])
    assert_eq(c.zrevrangebyscore_scores("z", "3", "3"), [("c", 3)])
    assert_eq(c.zrank("z", "b"), Some(1))
    assert_eq(c.zrevrank("z", "b"), Some(1))
    assert_eq(c.zrank("z", "missing"), None)
    assert_eq(c.zincrby("z", 1, "b"), 3)
    assert_eq(c.zmscore("z", ["a", "missing"]), [Some(1.5), None])
    assert_eq(c.zadd("y", [("a", 2), ("x", 5)]), 2)
    assert_eq(c.zunionstore("u", ["z", "y"]), 4)
    assert_eq(
      c.zinterstore("i", ["z", "y"], weights=[1, 2], aggregate="SUM"),
      1,
    )
    assert_eq(c.zscore("i", "a"), Some(5.5))
    assert_eq(c.zpopmin("y"), [("a", 2)])
    assert_eq(c.zpopmax("y"), [("x", 5)])
    assert_eq(c.bzpopmin(["z"], 1), Some(("z", "a", 1.5)))
    assert_eq(c.zrem("z", ["b", "missing"]), 1)
    assert_eq(c.zremrangebyrank("z", 0, 0), 1)
    ignore(c.zadd("w", [("a", 1), ("b", 2)]))
    assert_eq(c.zremrangebyscore("w", "1", "1"), 1)
    let (cursor, batch) = c.zscan("w", "0", pattern="*", count=100)
    assert_eq(cursor, "0")
    assert_eq(batch.length() > 0, true)
    assert_eq(c.zrandmember("missing"), [])
    assert_eq(c.zrandmember("w"), ["b"])
    assert_eq(c.zrandmember("w", count=1), ["b"])
    assert_eq(c.zrandmember_scores("w", 1), [("b", 2)])
    ignore(c.zadd("v", [("a", 1), ("b", 2), ("c", 3)]))
    assert_eq(c.zpopmin("v", count=2), [("a", 1), ("b", 2)])
    assert_eq(c.zpopmax("v", count=1), [("c", 3)])
    assert_eq(c.zpopmin("v"), [])
    ignore(c.zadd("u2", [("m", 4)]))
    assert_eq(c.bzpopmax(["u2"], 1), Some(("u2", "m", 4)))
  })
}

///|
async test "streams" {
  both_protocols(7, c => {
    let first = c.xadd("x", "1-1", [("a", "1")])
    assert_eq(first, "1-1")
    assert_eq(c.xadd("x", "2-1", [("b", "2")]), "2-1")
    assert_eq(c.xlen("x"), 2)
    let entries = c.xrange("x", "-", "+")
    assert_eq(entries.map(e => e.id), ["1-1", "2-1"])
    assert_eq(entries[0].fields, [("a", "1")])
    assert_eq(c.xrevrange("x", "+", "-", count=1)[0].id, "2-1")
    guard c.xread([("x", "0")], count=1) is Some(read) else {
      fail("no entries")
    }
    assert_eq(read[0].0, "x")
    assert_eq(read[0].1[0].id, "1-1")
    assert_true(c.xread([("x", "$")], block=1) is None)
    c.xgroup_create("x", "g", "0")
    assert_true(c.xgroup_createconsumer("x", "g", "c"))
    guard c.xreadgroup("g", "c", [("x", ">")], count=2) is Some(taken) else {
      fail("the group read nothing")
    }
    assert_eq(taken[0].1.length(), 2)
    let pending = c.xpending("x", "g")
    assert_eq(pending.count, 2)
    assert_eq(pending.min_id, Some("1-1"))
    assert_eq(pending.max_id, Some("2-1"))
    assert_eq(pending.consumers, [("c", 2)])
    assert_eq(c.xack("x", "g", ["1-1"]), 1)
    assert_eq(c.xpending("x", "g").count, 1)
    assert_eq(c.xack("x", "g", ["2-1"]), 1)
    let none = c.xpending("x", "g")
    assert_eq(none.count, 0)
    assert_eq(none.min_id, None)
    assert_eq(none.consumers, [])
    assert_eq(c.xdel("x", ["1-1"]), 1)
    assert_eq(c.xtrim("x", 0), 1)
    assert_eq(c.xgroup_delconsumer("x", "g", "c"), 0)
    assert_true(c.xgroup_destroy("x", "g"))
  })
}

///|
async test "hyperloglog, bitmaps and geo" {
  both_protocols(8, c => {
    assert_eq(c.pfadd("p", ["a", "b", "c"]), 1)
    assert_eq(c.pfcount(["p"]), 3)
    assert_eq(c.pfadd("q", ["c", "d"]), 1)
    c.pfmerge("m", ["p", "q"])
    assert_eq(c.pfcount(["m"]), 4)
    assert_eq(c.setbit("b", 7, 1), 0)
    assert_eq(c.getbit("b", 7), 1)
    assert_eq(c.bitcount("b"), 1)
    assert_eq(c.bitpos("b", 1), 7)
    assert_eq(c.setbit("c", 0, 1), 0)
    assert_eq(c.bitop("OR", "d", ["b", "c"]), 1)
    assert_eq(c.bitcount("d"), 2)
    let places = [
      ("Palermo", 13.361389, 38.115556),
      ("Catania", 15.087269, 37.502669),
    ]
    assert_eq(c.geoadd("g", places), 2)
    guard c.geodist("g", "Palermo", "Catania", unit="km") is Some(km) else {
      fail("no distance")
    }
    assert_true(km > 166 && km < 167)
    assert_eq(c.geodist("g", "Palermo", "nowhere"), None)
    assert_eq(c.geohash("g", ["Palermo", "nowhere"]), [
      Some("sqc8b49rny0"),
      None,
    ])
    let at = c.geopos("g", ["Palermo", "nowhere"])
    assert_true(at[0] is Some((x, _)) && x > 13.3 && x < 13.4)
    assert_true(at[1] is None)
    let near = c.geosearch(
      "g",
      "km",
      from_member="Palermo",
      radius=200,
      asc=true,
    )
    assert_eq(near, ["Palermo", "Catania"])
    let box = c.geosearch(
      "g",
      "km",
      longitude=15,
      latitude=37,
      width=400,
      height=400,
      count=1,
      asc=true,
    )
    assert_eq(box, ["Catania"])
  })
}

///|
async test "scripts and functions" {
  both_protocols(9, c => {
    let reply = c.eval("return ARGV[1]", [], ["hi"])
    assert_eq(reply, @resp.BulkString(b"hi"))
    assert_eq(
      c.eval("return redis.call('set', KEYS[1], ARGV[1])", ["k"], ["v"]),
      @resp.SimpleString("OK"),
    )
    let digest = c.script_load("return 7")
    assert_eq(c.script_exists([digest, "0000"]), [true, false])
    assert_eq(c.evalsha(digest, [], []), @resp.Integer(7))
    c.script_flush()
    assert_eq(c.script_exists([digest]), [false])
    // In this test, because `SCRIPT FLUSH` reaches every database and tests run side by side.
    let script = @moonredis.Script::new("return redis.call('incr', KEYS[1])")
    assert_eq(script.run(c, ["counted"], []), @resp.Integer(1))
    assert_eq(script.run(c, ["counted"], []), @resp.Integer(2))
    c.script_flush()
    assert_eq(script.run(c, ["counted"], []), @resp.Integer(3))
    let library =
      #|#!lua name=mylib
      #|redis.register_function('seven', function() return 7 end)
    assert_eq(c.function_load(library, replace=true), "mylib")
    assert_eq(c.function_call("seven", [], []), @resp.Integer(7))
    c.function_delete("mylib")
  })
}

///|
async test "server" {
  both_protocols(10, c => {
    assert_eq(c.ping(), "PONG")
    assert_eq(c.ping_message("hey"), b"hey" |> @utf8.decode)
    assert_eq(c.echo("hey"), b"hey")
    assert_true(c.info(section="server").contains("redis_version"))
    assert_true(c.command_count() > 100)
    let (seconds, _) = c.time_()
    assert_true(seconds > 1700000000)
    c.client_setname("moonredis-it")
    assert_eq(c.client_getname(), Some("moonredis-it"))
    assert_true(c.client_id() > 0)
    assert_eq(c.config_get("maxmemory-policy").length(), 1)
    assert_eq(c.slowlog_len() >= 0, true)
    assert_eq(c.slowlog_get(count=1).length() <= 1, true)
    assert_true(c.lastsave() > 0)
  })
}
