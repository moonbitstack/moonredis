///|
async fn open() -> @moonredis.Client? {
  live(6379).map(conn => @moonredis.Client::new(conn))
}

///|
fn endpoint(port : Int32) -> @moonsd.Endpoint {
  @moonsd.Endpoint::new("10.1.0.1", port)
}

///|
async test "a registry meets the discovery contract" {
  guard open() is Some(client) else { return }
  let registry = @sd.Registry::new(client, poll=20)
  @conformance.check(registry, registry, service="moonredis-sd-\{@env.now()}")
}

///|
async test "a service name is matched literally" {
  guard open() is Some(client) else { return }
  let registry = @sd.Registry::new(client)
  let lease = @moonsd.Registrar::register(
    registry,
    "sd-lit-a",
    endpoint(1),
    5000,
  )
  defer @async.protect_from_cancel(() => {
    @moonsd.Registrar::deregister(registry, lease)
  })
  assert_eq(@moonsd.Discovery::resolve(registry, "sd-lit-*").length(), 0)
  assert_eq(@moonsd.Discovery::resolve(registry, "sd-lit-?").length(), 0)
  assert_eq(@moonsd.Discovery::resolve(registry, "sd-lit-[a]").length(), 0)
  assert_eq(@moonsd.Discovery::resolve(registry, "sd-lit-a").length(), 1)
}

///|
async test "two prefixes do not see each other" {
  guard open() is Some(client) else { return }
  let one = @sd.Registry::new(client, prefix="sd-one")
  let two = @sd.Registry::new(client, prefix="sd-two")
  let lease = @moonsd.Registrar::register(one, "sd-pre", endpoint(2), 5000)
  defer @async.protect_from_cancel(() => {
    @moonsd.Registrar::deregister(one, lease)
  })
  assert_eq(@moonsd.Discovery::resolve(one, "sd-pre").length(), 1)
  assert_eq(@moonsd.Discovery::resolve(two, "sd-pre").length(), 0)
}

///|
async test "a value that is not an endpoint is refused" {
  guard open() is Some(client) else { return }
  let registry = @sd.Registry::new(client)
  ignore(client.set("moonsd:{sd-bad}:x", "not json", px=5000))
  defer @async.protect_from_cancel(() => {
    ignore(client.del(["moonsd:{sd-bad}:x"]))
  })
  let refused = try @moonsd.Discovery::resolve(registry, "sd-bad") catch {
    @moonsd.Malformed(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(refused)
}

///|
async test "tasks sharing a registry get their own replies" {
  guard open() is Some(client) else { return }
  let registry = @sd.Registry::new(client)
  let services = ["sd-mix-a", "sd-mix-b", "sd-mix-c", "sd-mix-d"]
  let leases = []
  for i, service in services {
    leases.push(
      @moonsd.Registrar::register(registry, service, endpoint(100 + i), 5000),
    )
  }
  defer @async.protect_from_cancel(() => {
    for lease in leases {
      @moonsd.Registrar::deregister(registry, lease)
    }
  })
  @async.with_task_group(group => {
    for i, service in services {
      group.spawn_bg(() => {
        for _ in 0..<50 {
          let got = @moonsd.Discovery::resolve(registry, service)
          assert_eq(got, [endpoint(100 + i)])
        }
      })
    }
  })
}
