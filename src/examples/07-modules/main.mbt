// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One command from each Redis 8 module, against a real server: a JSON document, an index
/// over hash documents, a time series, a Bloom filter and a t-digest. Needs a redis 8; when
/// none is listening it says so and stops.
///
///     moon run src/examples/07-modules --target native
#coverage.skip
async fn main {
  let options = @moonredis.ClientOptions::at("127.0.0.1", 6379)
  let conn = @socket.Connection::connect(options) catch {
    _ => {
      println("no redis at 127.0.0.1:6379; start one to run this example.")
      return
    }
  }
  let client = @moonredis.Client::new(conn)

  println("JSON")
  try {
    ignore(client.json_del("moonredis:example:doc"))
    ignore(
      client.json_set(
        "moonredis:example:doc",
        "$",
        @json.parse("{\"title\":\"moon\",\"readings\":[1,2,3]}"),
      ),
    )
    let title = client.json_get_text("moonredis:example:doc", path="$.title")
    println("  JSON.GET $.title -> " + title.unwrap_or("(nil)"))
    let grown = client.json_arrappend("moonredis:example:doc", "$.readings", [
      @json.Json::number(4.0),
    ])
    println("  JSON.ARRAPPEND $.readings 4 -> " + grown[0].unwrap().to_string())
  } catch {
    @moonredis.Reply(message) => println("  the server refused: " + message)
    @moonredis.Protocol(message) => println("  unexpected reply: " + message)
    _ => println("  the connection failed")
  }

  println("search")
  try {
    client.ft_dropindex("moonredis:example:idx", delete_documents=true) catch {
      _ => ()
    }
    client.ft_create("moonredis:example:idx", {
      ..@moonredis.Schema::new([
        @moonredis.SchemaField::text("title"),
        @moonredis.SchemaField::numeric("pages", sortable=true),
      ]),
      prefixes: ["moonredis:example:book:"],
    })
    ignore(
      client.hset("moonredis:example:book:1", [
        ("title", "the moon is a harsh mistress"),
        ("pages", "288"),
      ]),
    )
    ignore(
      client.hset("moonredis:example:book:2", [
        ("title", "the moon and sixpence"),
        ("pages", "224"),
      ]),
    )
    let found = client.ft_search("moonredis:example:idx", "moon", options={
      ..@moonredis.search_default,
      sort_by: Some({ field: "pages", ascending: true, }),
      return_fields: ["title"],
    })
    println("  FT.SEARCH moon -> " + found.total.to_string() + " documents")
    for hit in found.hits {
      println("    " + hit.id + " " + hit.field("title").unwrap_or(""))
    }
    let grouped = client.ft_aggregate("moonredis:example:idx", "*", options={
      ..@moonredis.aggregate_default,
      group_by: ["@pages"],
      reducers: [{ function: "COUNT", args: [], as_: Some("books"), }],
    })
    println(
      "  FT.AGGREGATE grouped rows -> " + grouped.rows.length().to_string(),
    )
    client.ft_dropindex("moonredis:example:idx", delete_documents=true)
  } catch {
    @moonredis.Reply(message) => println("  the server refused: " + message)
    @moonredis.Protocol(message) => println("  unexpected reply: " + message)
    _ => println("  the connection failed")
  }

  println("time series")
  try {
    ignore(client.del(["moonredis:example:ts"]))
    client.ts_create("moonredis:example:ts", labels=[("sensor", "moon")])
    for (timestamp, value) in [(1000L, 1.5), (2000L, 2.5), (3000L, 3.5)] {
      ignore(client.ts_add("moonredis:example:ts", timestamp, value))
    }
    let samples = client.ts_range(
      "moonredis:example:ts",
      @moonredis.Min,
      @moonredis.Max,
    )
    println("  TS.RANGE -> " + samples.length().to_string() + " samples")
    match client.ts_get("moonredis:example:ts") {
      Some(sample) =>
        println(
          "  TS.GET -> " +
          sample.timestamp.to_string() +
          " " +
          sample.value.to_string(),
        )
      None => println("  TS.GET -> (empty)")
    }
  } catch {
    @moonredis.Reply(message) => println("  the server refused: " + message)
    @moonredis.Protocol(message) => println("  unexpected reply: " + message)
    _ => println("  the connection failed")
  }

  println("probabilistic")
  try {
    ignore(client.del(["moonredis:example:bf", "moonredis:example:td"]))
    client.bf_reserve("moonredis:example:bf", 0.01, 100)
    ignore(client.bf_add("moonredis:example:bf", "moon"))
    println(
      "  BF.EXISTS moon -> " +
      client.bf_exists("moonredis:example:bf", "moon").to_string(),
    )
    client.tdigest_create("moonredis:example:td")
    client.tdigest_add("moonredis:example:td", [1.0, 2.0, 3.0, 4.0, 5.0])
    let median = client.tdigest_quantile("moonredis:example:td", [0.5])[0]
    println("  TDIGEST.QUANTILE 0.5 -> " + median.to_string())
  } catch {
    @moonredis.Reply(message) => println("  the server refused: " + message)
    @moonredis.Protocol(message) => println("  unexpected reply: " + message)
    _ => println("  the connection failed")
  }

  ignore(client.del(["moonredis:example:doc"])) catch {
    _ => ()
  }
  ignore(client.del(["moonredis:example:ts"])) catch {
    _ => ()
  }
  ignore(client.del(["moonredis:example:bf", "moonredis:example:td"])) catch {
    _ => ()
  }
}
