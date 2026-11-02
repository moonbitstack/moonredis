// A six-node cluster and a sentinel, both started by `scripts/start_redis.sh`.

///|
let cluster_ports : Array[Int32] = [7000, 7001, 7002, 7003, 7004, 7005]

///|
/// A connection per node, by address, with the admin client of the first.
async fn cluster_nodes() -> (
  Array[(String, &@moonredis.RedisConn)],
  @moonredis.Client,
)? {
  let nodes : Array[(String, &@moonredis.RedisConn)] = []
  let mut admin = None
  for port in cluster_ports {
    guard live(port) is Some(conn) else { return None }
    nodes.push(("127.0.0.1:\{port}", conn))
    if admin is None {
      admin = Some(@moonredis.Client::new(conn))
    }
  }
  Some((nodes, admin.unwrap()))
}

///|
/// The connection to `address` among `nodes`, as a client.
fn client_of(
  nodes : Array[(String, &@moonredis.RedisConn)],
  address : String,
) -> @moonredis.Client {
  for node in nodes {
    if node.0 == address {
      return @moonredis.Client::new(node.1)
    }
  }
  abort("no connection to \{address}")
}

///|
async fn node_id(client : @moonredis.Client) -> Bytes {
  match client.command([b"CLUSTER", b"MYID"]) {
    @resp.BulkString(id) => id
    other => fail("no node id: \{@resp.resp_kind(other)}")
  }
}

///|
async fn live_cluster() -> (@moonredis.ClusterClient, @moonredis.Client)? {
  guard cluster_nodes() is Some((nodes, admin)) else { return None }
  let topology = @moonredis.decode_cluster_slots(admin.cluster_slots())
  Some((@moonredis.ClusterClient::new(nodes, topology), admin))
}

///|
fn set_(key : String, value : String) -> Array[Bytes] {
  [b"SET", @utf8.encode(key), @utf8.encode(value)]
}

///|
fn get_(key : String) -> Array[Bytes] {
  [b"GET", @utf8.encode(key)]
}

///|
async test "keys spread across the masters and read back" {
  guard live_cluster() is Some((cluster, _)) else { return }
  for i in 0..<300 {
    let key = "it:spread:\{i}"
    assert_eq(cluster.command(set_(key, "v\{i}")), @resp.SimpleString("OK"))
  }
  let owners : Map[String, Unit] = Map([])
  for i in 0..<300 {
    let key = "it:spread:\{i}"
    assert_eq(
      cluster.command(get_(key)),
      @resp.BulkString(@utf8.encode("v\{i}")),
    )
    owners[cluster.topology.node_for_slot(@moonredis.hash_slot(key)).unwrap()] = ()
    ignore(cluster.command([b"DEL", @utf8.encode(key)]))
  }
  assert_eq(owners.length(), 3)
}

///|
async test "a stale topology is corrected by MOVED and the other slots keep working" {
  guard cluster_nodes() is Some((nodes, admin)) else { return }
  let right = @moonredis.decode_cluster_slots(admin.cluster_slots())
  let cluster = @moonredis.ClusterClient::new(nodes, right)
  // Point the slot of one key at a node that does not hold it.
  let key = "it:moved"
  let slot = @moonredis.hash_slot(key)
  let owner = right.node_for_slot(slot).unwrap()
  let wrong = if owner == "127.0.0.1:7000" {
    "127.0.0.1:7001"
  } else {
    "127.0.0.1:7000"
  }
  cluster.topology.assign(slot, wrong)
  assert_eq(cluster.command(set_(key, "v")), @resp.SimpleString("OK"))
  assert_eq(cluster.topology.node_for_slot(slot), Some(owner))
  // A redirect once replaced the whole topology with this one slot.
  let other = "it:unrelated"
  assert_true(@moonredis.hash_slot(other) != slot)
  assert_eq(cluster.command(set_(other, "w")), @resp.SimpleString("OK"))
  ignore(cluster.command([b"DEL", @utf8.encode(key)]))
  ignore(cluster.command([b"DEL", @utf8.encode(other)]))
}

///|
async test "a key already moved mid-migration is reached through ASK" {
  guard cluster_nodes() is Some((nodes, admin)) else { return }
  let topology = @moonredis.decode_cluster_slots(admin.cluster_slots())
  let cluster = @moonredis.ClusterClient::new(nodes, topology)
  let key = "it:{asked}"
  let slot = @moonredis.hash_slot(key)
  let source = topology.node_for_slot(slot).unwrap()
  let target = topology.node_for_slot((slot + 8000) % 16384).unwrap()
  assert_true(source != target)
  let giving = client_of(nodes, source)
  let taking = client_of(nodes, target)
  let source_id = node_id(giving)
  let target_id = node_id(taking)
  let number = @utf8.encode(slot.to_string())
  ignore(
    taking.command([b"CLUSTER", b"SETSLOT", number, b"IMPORTING", source_id]),
  )
  ignore(
    giving.command([b"CLUSTER", b"SETSLOT", number, b"MIGRATING", target_id]),
  )
  // The source no longer holds a key that is absent, so it sends the client to the target.
  assert_eq(cluster.command(set_(key, "there")), @resp.SimpleString("OK"))
  assert_eq(cluster.topology.node_for_slot(slot), Some(source))
  assert_eq(cluster.command(get_(key)), @resp.BulkString(b"there"))
  ignore(cluster.command([b"DEL", @utf8.encode(key)]))
  ignore(taking.command([b"CLUSTER", b"SETSLOT", number, b"NODE", source_id]))
  ignore(giving.command([b"CLUSTER", b"SETSLOT", number, b"NODE", source_id]))
}

///|
async test "a node the client has not met is dialled" {
  guard cluster_nodes() is Some((nodes, admin)) else { return }
  let topology = @moonredis.decode_cluster_slots(admin.cluster_slots())
  let key = "it:dialled"
  let owner = topology.node_for_slot(@moonredis.hash_slot(key)).unwrap()
  let dialled = Ref(0)
  let cluster = @moonredis.ClusterClient::new(
    nodes.filter(n => n.0 != owner),
    @moonredis.ClusterTopology::new([
      @moonredis.ClusterSlot::new(
        0,
        16383,
        if owner == "127.0.0.1:7000" {
          "127.0.0.1:7001"
        } else {
          "127.0.0.1:7000"
        },
      ),
    ]),
    dial=address => {
      dialled.val += 1
      let port = @string.parse_int(address.split(":").collect()[1].to_owned()) catch {
        _ => raise @moonredis.Connection("bad address")
      }
      let conn : &@moonredis.RedisConn = @socket.Connection::connect(
        @moonredis.ClientOptions::at("127.0.0.1", port),
      )
      conn
    },
  )
  assert_eq(cluster.command(set_(key, "v")), @resp.SimpleString("OK"))
  assert_eq(dialled.val, 1)
  ignore(cluster.command([b"DEL", @utf8.encode(key)]))
}

///|
async test "a redirect loop stops at the limit" {
  let cluster = @moonredis.ClusterClient::new(
    [
      ("a:1", @moonredis.FakeConn::handler(_ => @resp.Error("MOVED 1 b:1"))),
      ("b:1", @moonredis.FakeConn::handler(_ => @resp.Error("MOVED 1 a:1"))),
    ],
    @moonredis.ClusterTopology::new([
      @moonredis.ClusterSlot::new(0, 16383, "a:1"),
    ]),
  )
  let stopped = try {
    ignore(cluster.command(get_("k")))
    false
  } catch {
    @moonredis.Protocol(_) => true
    _ => false
  }
  assert_true(stopped)
}

///|
async test "sentinel names the master, and the replica after a failover" {
  guard live(26379) is Some(watcher) else { return }
  let sentinel = @moonredis.SentinelClient::new([watcher])
  let first = sentinel.resolve("mymaster")
  assert_eq(first, "127.0.0.1:6390")
  guard live(6390) is Some(master) else { return }
  // No save and no reply: the server goes away with the command.
  ignore(@moonredis.Client::new(master).shutdown(save=false)) catch {
    _ => ()
  }
  let mut now = first
  for _ in 0..<100 {
    now = sentinel.resolve("mymaster")
    if now != first {
      break
    }
    @async.sleep(100)
  }
  assert_eq(now, "127.0.0.1:6391")
  guard live(6391) is Some(promoted) else { return }
  let client = @moonredis.Client::new(promoted)
  assert_true(client.info(section="replication").contains("role:master"))
  assert_true(client.set("it:after-failover", "v"))
  ignore(client.del(["it:after-failover"]))
}
