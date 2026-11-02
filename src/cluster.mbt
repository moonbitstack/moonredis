// Cluster routing. A redis cluster shards keys across 16384 slots by CRC16; a key's slot
// decides which node owns it, and a node answers a mis-routed command with a `MOVED`
// (or, mid-migration, `ASK`) redirect to the owner. These are the routing pieces: slot
// hashing, topology, and the client that follows redirects.

///|
/// A contiguous range of slots owned by one node, named by `host:port`.
pub struct ClusterSlot {
  start : Int32
  end : Int32
  node : String
}

///|
/// A slot range `[start, end]` owned by `node` (`host:port`).
pub fn ClusterSlot::new(
  start : Int32,
  end : Int32,
  node : String,
) -> ClusterSlot {
  { start, end, node, }
}

///|
/// The slot-to-node map the client routes with.
pub struct ClusterTopology {
  slots : Array[ClusterSlot]
}

///|
/// `ClusterTopology` from an explicit slot list (used after parsing `CLUSTER SLOTS`, or in
/// tests).
pub fn ClusterTopology::new(slots : Array[ClusterSlot]) -> ClusterTopology {
  { slots, }
}

///|
/// Record that `slot` lives on `node`. Singles sit ahead of the ranges, so the first match
/// in `node_for_slot` is the latest word on a slot.
pub fn ClusterTopology::assign(
  self : ClusterTopology,
  slot : Int32,
  node : String,
) -> Unit {
  for i, s in self.slots {
    if s.start == slot && s.end == slot {
      self.slots[i] = { ..s, node, }
      return
    }
  }
  self.slots.insert(0, ClusterSlot::new(slot, slot, node))
}

///|
/// The node address (`host:port`) that owns `slot`, or `None` if no range covers it.
pub fn ClusterTopology::node_for_slot(
  self : ClusterTopology,
  slot : Int32,
) -> String? {
  for s in self.slots {
    if slot >= s.start && slot <= s.end {
      return Some(s.node)
    }
  }
  None
}

///|
/// The CRC16-CCITT (XMODEM) of `data`: polynomial `0x1021`, initial `0`, no reflection —
/// the checksum redis uses to place a key in a slot.
pub fn crc16(data : Bytes) -> Int32 {
  let mut crc : Int32 = 0
  for i = 0; i < data.length(); i = i + 1 {
    crc = crc ^ (data[i].to_int() << 8)
    for _j = 0; _j < 8; _j = _j + 1 {
      if (crc & 0x8000) != 0 {
        crc = ((crc << 1) ^ 0x1021) & 0xffff
      } else {
        crc = (crc << 1) & 0xffff
      }
    }
  }
  crc
}

///|
/// The slot a key hashes to. A key of the form `prefix{tag}suffix` hashes by `tag` (the
/// hash tag), so those keys colocate; otherwise the whole key is hashed. The result is
/// taken modulo 16384.
pub fn hash_slot(key : String) -> Int32 {
  let bytes = @utf8.encode(key)
  let mut tag_start = -1
  let mut tag_end = -1
  for i = 0; i < bytes.length(); i = i + 1 {
    if bytes[i] == b'{' {
      tag_start = i
      break
    }
  }
  if tag_start >= 0 {
    for j = tag_start + 1; j < bytes.length(); j = j + 1 {
      if bytes[j] == b'}' {
        tag_end = j
        break
      }
    }
  }
  let used : Bytes = if tag_start >= 0 && tag_end > tag_start + 1 {
    bytes[tag_start + 1:tag_end].to_owned()
  } else {
    bytes
  }
  crc16(used) % 16384
}

///|
/// Whether every key hashes to the same slot — required for multi-key commands in a
/// cluster.
pub fn same_slot(keys : Array[String]) -> Bool {
  guard keys.length() > 0 else { return true }
  let first = hash_slot(keys[0])
  for k in keys {
    if hash_slot(k) != first {
      return false
    }
  }
  true
}

///|
/// `CLUSTER SLOTS`: the cluster's slot map, as the raw reply (each caller decodes it).
pub async fn Client::cluster_slots(
  self : Client,
) -> @resp.RespValue raise RedisError {
  self.command([b"CLUSTER", b"SLOTS"])
}

///|
/// Parse a `CLUSTER SLOTS` reply into a `ClusterTopology`. Each entry is `[start, end,
/// [host, port, id], ...replicas...]`; the master's `host:port` is the owning node.
pub fn decode_cluster_slots(
  reply : @resp.RespValue,
) -> ClusterTopology raise RedisError {
  let entries = expect_array(reply)
  let out : Array[ClusterSlot] = []
  for entry in entries {
    match entry {
      @resp.Array(items) => {
        guard items.length() >= 3 else {
          raise Protocol("unexpected CLUSTER SLOTS entry")
        }
        let start = expect_int64(items[0]).to_int()
        let end = expect_int64(items[1]).to_int()
        let node = match items[2] {
          @resp.Array(master) => {
            guard master.length() >= 2 else {
              raise Protocol("unexpected CLUSTER SLOTS master")
            }
            let host = @utf8.decode_lossy(expect_bytes(master[0]).unwrap())
            let port = expect_int64(master[1]).to_int().to_string()
            host + ":" + port
          }
          _ => raise Protocol("unexpected CLUSTER SLOTS master")
        }
        out.push({ start, end, node, })
      }
      _ => raise Protocol("unexpected CLUSTER SLOTS entry")
    }
  }
  { slots: out, }
}

///|
/// How many redirects one command may follow before giving up; go-redis's `MaxRedirects`.
pub let redirect_limit : Int32 = 3

///|
/// A cluster-aware client: it routes a command to the node owning its key and follows
/// `MOVED` and `ASK` redirects. Built from a connection per node address and the topology.
///
/// A redirect can name a node it was not built with, after a reshard or a failover. `dial`
/// opens a connection to such a node; without it that redirect is a `Connection` error.
pub struct ClusterClient {
  nodes : Map[String, &RedisConn]
  mut topology : ClusterTopology
  limit : Int32
  dial : (async (String) -> &RedisConn raise RedisError)?
}

///|
/// A cluster client over `nodes` (address, connection pairs) and `topology`.
pub fn ClusterClient::new(
  nodes : Array[(String, &RedisConn)],
  topology : ClusterTopology,
  limit~ : Int32 = redirect_limit,
  dial? : async (String) -> &RedisConn raise RedisError,
) -> ClusterClient {
  { nodes: Map::from_array(nodes), topology, limit, dial, }
}

///|
/// Replace the routing topology (after a redirect, or on a refresh).
pub fn ClusterClient::set_topology(
  self : ClusterClient,
  topology : ClusterTopology,
) -> Unit {
  self.topology = topology
}

///|
/// Send `args` to the node owning its key, following redirects up to the limit. The key is
/// the first argument after the command name. `MOVED` updates the topology, since the slot
/// has gone for good; `ASK` does not, since only this key has gone ahead so far, and the node
/// it names serves the key only straight after `ASKING`.
pub async fn ClusterClient::command(
  self : ClusterClient,
  args : Array[Bytes],
) -> @resp.RespValue raise RedisError {
  let slot = cluster_slot_of_args(args)
  guard self.topology.node_for_slot(slot) is Some(addr) else {
    raise Protocol("no node owns slot " + slot.to_string())
  }
  let mut conn = self.conn_for(addr)
  let mut asking = false
  for _ in 0..<=self.limit {
    let reply = if asking {
      conn.execute_all([[b"ASKING"], args])[1]
    } else {
      conn.execute(args)
    }
    guard reply is (@resp.Error(msg) | @resp.BulkError(msg)) &&
      redirect(msg) is Some(next) else {
      return reply
    }
    match next {
      Moved(slot~, node~) => {
        self.topology.assign(slot, node)
        conn = self.conn_for(node)
        asking = false
      }
      Ask(node~, ..) => {
        conn = self.conn_for(node)
        asking = true
      }
    }
  }
  raise Protocol("more than \{self.limit} redirects for slot \{slot}")
}

///|
/// The connection for `addr`, opening one through `dial` when the client has not met it.
async fn ClusterClient::conn_for(
  self : ClusterClient,
  addr : String,
) -> &RedisConn raise RedisError {
  if self.nodes.get(addr) is Some(conn) {
    return conn
  }
  guard self.dial is Some(dial) else {
    raise Connection("no connection for node " + addr)
  }
  let conn = dial(addr)
  self.nodes[addr] = conn
  conn
}

///|
/// The slot of the key in `args` (the first argument after the command name), or 0 when the
/// command has no key argument.
fn cluster_slot_of_args(args : Array[Bytes]) -> Int32 {
  if args.length() >= 2 {
    hash_slot(@utf8.decode_lossy(args[1][:]))
  } else {
    0
  }
}
