// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Service discovery on Redis: an endpoint is a key that expires, so a lease lapsing needs no
// sweeper. Expiry publishes nothing a client can count on, so `watch` polls.

///|
/// What every key of a registry starts with.
pub let prefix : String = "moonsd"

///|
/// How often a watcher looks, in milliseconds: go-zero's discovery reads Redis on the same
/// order, and a change is at worst this late.
pub let poll : Int32 = 1000

///|
/// How many keys one `SCAN` round asks for.
let scan_count : Int32 = 256

///|
/// A registry over one Redis client. It is both a `Registrar` and a `Discovery`, and any number
/// of tasks may share it. Give it a client of its own: the lock orders the registry's commands,
/// not those of anything else on that connection.
pub struct Registry {
  client : @moonredis.Client
  prefix : String
  poll : Int32
  lock : @async.Mutex
}

///|
pub fn Registry::new(
  client : @moonredis.Client,
  prefix~ : String = prefix,
  poll~ : Int32 = poll,
) -> Registry {
  { client, prefix, poll, lock: @async.Mutex::Mutex(), }
}

///|
/// One command at a time, and a cancelled task still reads its reply: left unread, that reply
/// would answer whichever command came next on the connection.
async fn[T] Registry::one(self : Registry, command : async () -> T) -> T {
  @async.protect_from_cancel(() => {
    self.lock.acquire()
    defer self.lock.release()
    command()
  })
}

///|
/// The hash tag keeps a service's keys in one cluster slot.
fn Registry::key(self : Registry, service : String, id : String) -> String {
  "\{self.prefix}:{\{service}}:\{id}"
}

///|
pub extend Registry with @moonsd.Registrar::{register, renew, deregister}

///|
pub impl @moonsd.Registrar for Registry with fn register(
  self,
  service,
  endpoint,
  ttl,
) {
  let token = self.key(service, endpoint.id)
  let value = endpoint.to_json().stringify()
  ignore(self.one(() => self.client.set(token, value, px=ttl.to_int64())))
  { service, endpoint, ttl, token, }
}

///|
pub impl @moonsd.Registrar for Registry with fn renew(self, lease) {
  let held = self.one(() => {
    self.client.pexpire(lease.token, lease.ttl.to_int64())
  })
  if !held {
    raise @moonsd.Expired(lease)
  }
}

///|
pub impl @moonsd.Registrar for Registry with fn deregister(self, lease) {
  ignore(self.one(() => self.client.del([lease.token])))
}

///|
/// A service name is matched literally, whatever it contains.
fn glob_escape(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if c is ('*' | '?' | '[' | ']' | '\\') {
      out.write_char('\\')
    }
    out.write_char(c)
  }
  out.to_string()
}

///|
/// A service's endpoints, by id, so two looks at an unchanged service compare equal. A key that
/// expires between the scan and the read is simply gone.
async fn Registry::look(
  self : Registry,
  service : String,
) -> Array[@moonsd.Endpoint] {
  let pattern = self.key(glob_escape(service), "*")
  let keys : Array[String] = []
  let mut cursor = "0"
  for ;; {
    let (next, batch) = self.one(() => {
      self.client.scan(cursor, pattern~, count=scan_count)
    })
    keys.append(batch)
    cursor = next
    if cursor == "0" {
      break
    }
  }
  let out : Array[@moonsd.Endpoint] = []
  // SCAN may return a key twice while the table grows.
  let seen : Map[String, Unit] = Map([])
  for key in keys {
    if seen.contains(key) {
      continue
    }
    seen[key] = ()
    if self.one(() => self.client.get(key)) is Some(value) {
      let text = @utf8.decode_lossy(value)
      let parsed = @json.parse(text) catch {
        _ => raise @moonsd.Malformed(text)
      }
      let endpoint : @moonsd.Endpoint = @json.from_json(parsed) catch {
        _ => raise @moonsd.Malformed(text)
      }
      out.push(endpoint)
    }
  }
  out.sort_by_key(e => e.id)
  out
}

///|
pub extend Registry with @moonsd.Discovery::{resolve, watch}

///|
pub impl @moonsd.Discovery for Registry with fn resolve(self, service) {
  self.look(service)
}

///|
/// One service followed by polling.
priv struct Poller {
  registry : Registry
  service : String
  mut last : Array[@moonsd.Endpoint]?
  mut revision : Int64
  mut closed : Bool
}

///|
impl @moonsd.Watcher for Poller with fn next(self) {
  for ;; {
    if self.closed {
      fail("the watcher is closed")
    }
    let now = self.registry.look(self.service)
    if self.last is Some(before) && before == now {
      @async.sleep(self.registry.poll)
      continue
    }
    self.last = Some(now)
    self.revision = self.revision + 1
    return { endpoints: now, revision: self.revision, }
  }
}

///|
impl @moonsd.Watcher for Poller with fn close(self) {
  self.closed = true
}

///|
pub impl @moonsd.Discovery for Registry with fn watch(self, service) {
  let poller : &@moonsd.Watcher = Poller::{
    registry: self,
    service,
    last: None,
    revision: 0,
    closed: false,
  }
  poller
}
