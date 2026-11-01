// The geo commands, named as in redis-py. These index points by longitude/latitude in a
// sorted set (via the Geohash score) and query them; `geosearch` is the modern, unified
// query that replaces the older `GEORADIUS`/`GEORADIUSBYMEMBER`.

///|
/// `GEOADD key longitude latitude member...`: index the members, returning how many were
/// new.
pub async fn Client::geoadd(
  self : Client,
  key : String,
  points : Array[(String, Double, Double)],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"GEOADD", arg_string(key)]
  for (m, lon, lat) in points {
    args.push(arg_double(lon))
    args.push(arg_double(lat))
    args.push(arg_string(m))
  }
  expect_int64(self.command(args))
}

///|
/// `GEODIST key a b [unit]`: the distance between members `a` and `b`, or `None` if a
/// member is absent. `unit` is one of `m`, `km`, `mi`, `ft` (metres by default).
pub async fn Client::geodist(
  self : Client,
  key : String,
  a : String,
  b : String,
  unit? : String,
) -> Double? raise RedisError {
  let args : Array[Bytes] = [
    b"GEODIST",
    arg_string(key),
    arg_string(a),
    arg_string(b),
  ]
  match unit {
    Some(u) => args.push(arg_string(u))
    None => ()
  }
  match expect_bytes(self.command(args)) {
    Some(b) =>
      Some(
        @string.parse_double(@utf8.decode_lossy(b[:])) catch {
          _ => raise Protocol("invalid geodist reply")
        },
      )
    None => None
  }
}

///|
/// `GEOHASH key member...`: the geohash string of each member, `None` where absent.
pub async fn Client::geohash(
  self : Client,
  key : String,
  members : Array[String],
) -> Array[String?] raise RedisError {
  let args : Array[Bytes] = [b"GEOHASH", arg_string(key)]
  for m in members {
    args.push(arg_string(m))
  }
  let items = expect_array(self.command(args))
  items.map(x => expect_string(x))
}

///|
/// `GEOPOS key member...`: the `[longitude, latitude]` of each member, `None` where
/// absent.
pub async fn Client::geopos(
  self : Client,
  key : String,
  members : Array[String],
) -> Array[(Double, Double)?] raise RedisError {
  let args : Array[Bytes] = [b"GEOPOS", arg_string(key)]
  for m in members {
    args.push(arg_string(m))
  }
  let items = expect_array(self.command(args))
  items.map(x => {
    match x {
      @resp.Null => None
      @resp.Array(pair) => {
        guard pair.length() == 2 else {
          raise Protocol("unexpected geopos reply")
        }
        let lon = expect_double(pair[0])
        let lat = expect_double(pair[1])
        Some((lon, lat))
      }
      _ => raise Protocol("unexpected geopos reply")
    }
  })
}

///|
/// `GEOSEARCH key [FROMMEMBER m] [FROMLONLAT lon lat] [BYRADIUS r unit] [BYBOX w h unit]
/// [COUNT n] [ASC|DESC]`: the members matching a circular or rectangular area, optionally
/// ordered and capped. Returns the member names.
pub async fn Client::geosearch(
  self : Client,
  key : String,
  from_member? : String,
  longitude? : Double,
  latitude? : Double,
  radius? : Double,
  width? : Double,
  height? : Double,
  unit : String,
  count? : Int32,
  asc? : Bool,
  desc? : Bool,
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"GEOSEARCH", arg_string(key)]
  match from_member {
    Some(m) => {
      args.push(b"FROMMEMBER")
      args.push(arg_string(m))
    }
    None => ()
  }
  match (longitude, latitude) {
    (Some(lon), Some(lat)) => {
      args.push(b"FROMLONLAT")
      args.push(arg_double(lon))
      args.push(arg_double(lat))
    }
    _ => ()
  }
  match (radius, width, height) {
    (Some(r), _, _) => {
      args.push(b"BYRADIUS")
      args.push(arg_double(r))
    }
    (_, Some(w), Some(h)) => {
      args.push(b"BYBOX")
      args.push(arg_double(w))
      args.push(arg_double(h))
    }
    _ => ()
  }
  args.push(arg_string(unit))
  push_some(args, b"COUNT", count.map(arg_int))
  if asc.unwrap_or(false) {
    args.push(b"ASC")
  }
  if desc.unwrap_or(false) {
    args.push(b"DESC")
  }
  let items = expect_array(self.command(args))
  items.map(x => @utf8.decode_lossy(expect_bytes(x).unwrap()))
}
