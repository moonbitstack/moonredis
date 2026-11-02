// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Keys spread across a cluster by slot. Needs a cluster on 7000 to 7002, which
/// `scripts/start_redis.sh` starts; without one it says so and stops.
///
///     moon run src/examples/06-cluster --target native
#coverage.skip
async fn main {
  let nodes : Array[(String, &@moonredis.RedisConn)] = []
  for port in [7000, 7001, 7002, 7003, 7004, 7005] {
    let options = @moonredis.ClientOptions::at("127.0.0.1", port)
    let conn : &@moonredis.RedisConn = @socket.Connection::connect(options) catch {
      _ => {
        println(
          "no cluster at 127.0.0.1:\{port}; start one to run this example.",
        )
        return
      }
    }
    nodes.push(("127.0.0.1:\{port}", conn))
  }
  let slots = @moonredis.Client::new(nodes[0].1).cluster_slots()
  let topology = @moonredis.decode_cluster_slots(slots)
  let cluster = @moonredis.ClusterClient::new(nodes, topology)
  for name in ["apple", "banana", "cherry"] {
    let key = "moonredis:example:" + name
    ignore(cluster.command([b"SET", @utf8.encode(key), b"1"]))
    let slot = @moonredis.hash_slot(key)
    println(
      key + " is in slot \{slot} on \{topology.node_for_slot(slot).unwrap()}",
    )
    ignore(cluster.command([b"DEL", @utf8.encode(key)]))
  }
}
