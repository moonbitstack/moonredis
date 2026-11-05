// The Redis 8 module command families against a live server, under both protocols. Every
// group asserts the content of the reply rather than "it did not raise": a decoder that
// reads the wrong field still returns a value, and only the value shows it.
// The search module only indexes database 0, so its keys carry a prefix of their own and
// the package runs its tests one at a time.

///|
/// A client on database `db` speaking `protocol`, or `None` when no server is listening and
/// none is required. Each test loops over the two protocols itself rather than handing its
/// body to a helper: a panic raised inside a closure runs in a task of its own, and the test
/// would pass without it.
async fn connect(
  db : Int32,
  protocol : @moonredis.Protocol,
) -> @moonredis.Client? {
  guard live(6379, protocol~, db~) is Some(conn) else { return None }
  Some(@moonredis.Client::new(conn))
}

///|
async test "modules: json documents" {
  for protocol in [@moonredis.Resp2, @moonredis.Resp3] {
    guard connect(3, protocol) is Some(c) else { return }
    let key = "moonredis:mod:json"
    ignore(c.json_del(key))
    let document =
      #|{"s":"hi","n":1,"b":true,"arr":[1,2,3],"o":{"k":"v"}}
    let parsed = @json.parse(document[:])
    assert_true(c.json_set(key, "$", parsed))
    assert_false(c.json_set(key, "$", parsed, nx=true))
    assert_eq(c.json_get_text(key), Some(document))
    assert_eq(c.json_type(key), [Some("object")])
    assert_eq(c.json_type(key, path="$.n"), [Some("integer")])
    assert_eq(c.json_type(key, path="$.missing"), [])
    assert_eq(c.json_arrlen(key, path="$.arr"), [Some(3L)])
    assert_eq(c.json_strlen(key, path="$.s"), [Some(2L)])
    assert_eq(c.json_objkeys(key, path="$.o"), [Some(["k"])])
    assert_eq(c.json_objlen(key, path="$.o"), [Some(1L)])
    assert_eq(c.json_numincrby(key, "$.n", 4), [Some(5.0)])
    assert_eq(c.json_nummultby(key, "$.n", 2), [Some(10.0)])
    assert_eq(c.json_strappend(key, "$.s", "!"), [Some(3L)])
    assert_eq(c.json_arrappend(key, "$.arr", [@json.Json::number(4.0)]), [
      Some(4L),
    ])
    assert_eq(c.json_arrinsert(key, "$.arr", 0, [@json.Json::number(0.0)]), [
      Some(5L),
    ])
    assert_eq(c.json_arrindex(key, "$.arr", @json.Json::number(3.0)), [Some(3L)])
    assert_eq(c.json_arrtrim(key, "$.arr", 0, 1), [Some(2L)])
    let popped = c.json_arrpop(key, "$.arr")
    assert_eq(popped.length(), 1)
    assert_eq(popped[0].unwrap().stringify(), "1")
    assert_eq(c.json_toggle(key, "$.b"), [Some(false)])
    assert_eq(c.json_clear(key, path="$.o"), 1L)
    c.json_merge(key, "$.o", @json.parse("{\"n\":1}"))
    assert_eq(c.json_get_text(key, path="$.o"), Some("[{\"n\":1}]"))
    let other = "moonredis:mod:json2"
    c.json_mset([(other, "$", @json.parse("{\"o\":{\"z\":9}}"))])
    let both = c.json_mget([key, other], "$.o")
    assert_eq(both[0].unwrap().stringify(), "[{\"n\":1}]")
    assert_eq(both[1].unwrap().stringify(), "[{\"z\":9}]")
    assert_eq(c.json_del(other, path="$"), 1L)
    assert_true(c.json_debug_memory(key) > 0)
    let as_resp = c.json_resp(key)
    assert_true(as_resp is @resp.Array(_))
  }
}

///|
async test "modules: search over hash documents" {
  for protocol in [@moonredis.Resp2, @moonredis.Resp3] {
    guard connect(0, protocol) is Some(c) else { return }
    let index = "moonredis:mod:idx"
    let prefix = "moonredis:mod:doc:"
    ignore(c.del(["moonredis:mod:sug"]))
    // A search dictionary is not a key `DEL` can reach: it is emptied through its own
    // command, so the counts below do not depend on what an earlier run left behind.
    let stale = c.ft_dictdump("moonredis:mod:dict") catch { _ => [] }
    if stale.length() > 0 {
      ignore(c.ft_dictdel("moonredis:mod:dict", stale))
    }
    c.ft_dropindex(index, delete_documents=true) catch {
      _ => ()
    }
    c.ft_create(index, {
      ..@moonredis.Schema::new([
        @moonredis.SchemaField::text("title", sortable=true),
        @moonredis.SchemaField::numeric("num", sortable=true),
        @moonredis.SchemaField::tag("tag"),
      ]),
      prefixes: [prefix],
    })
    ignore(
      c.hset(prefix + "1", [
        ("title", "hello world"),
        ("num", "1"),
        ("tag", "x"),
      ]),
    )
    ignore(
      c.hset(prefix + "2", [
        ("title", "goodbye moon"),
        ("num", "2"),
        ("tag", "y"),
      ]),
    )
    assert_true(c.ft_list().contains(index))

    let all = c.ft_search(index, "*")
    assert_eq(all.total, 2L)
    assert_eq(all.hits.length(), 2)
    assert_eq(all.hits[0].field("title"), Some("hello world"))

    let one = c.ft_search(index, "hello")
    assert_eq(one.total, 1L)
    assert_eq(one.hits[0].id, prefix + "1")

    let projected = c.ft_search(index, "*", options={
      ..@moonredis.search_default,
      return_fields: ["title"],
    })
    assert_eq(projected.hits[0].field("title"), Some("hello world"))
    assert_eq(projected.hits[0].field("num"), None)

    let sorted = c.ft_search(index, "*", options={
      ..@moonredis.search_default,
      sort_by: Some({ field: "num", ascending: false, }),
      limit: 1,
    })
    assert_eq(sorted.total, 2L)
    assert_eq(sorted.hits.length(), 1)
    assert_eq(sorted.hits[0].id, prefix + "2")

    let scored = c.ft_search(index, "hello", options={
      ..@moonredis.search_default,
      with_scores: true,
      limit: 1,
    })
    assert_true(scored.hits[0].score.unwrap() > 0.0)

    let ids = c.ft_search(index, "*", options={
      ..@moonredis.search_default,
      nocontent: true,
    })
    assert_eq(ids.hits[0].fields.length(), 0)

    let filtered = c.ft_search(index, "*", options={
      ..@moonredis.search_default,
      filter: Some({ field: "num", min: "2", max: "1000", }),
    })
    assert_eq(filtered.total, 1L)
    assert_eq(filtered.hits[0].id, prefix + "2")

    let grouped = c.ft_aggregate(index, "*", options={
      ..@moonredis.aggregate_default,
      group_by: ["@tag"],
      reducers: [{ function: "COUNT", args: [], as_: Some("c"), }],
    })
    assert_eq(grouped.rows.length(), 2)
    assert_eq(
      @moonredis.aggregate_field(grouped.rows[0], "c").unwrap().int(),
      Some(1L),
    )

    let applied = c.ft_aggregate(index, "@num:[1 1]", options={
      ..@moonredis.aggregate_default,
      load: ["@num"],
      apply: [("@num*2", "d")],
    })
    assert_eq(applied.rows.length(), 1)
    assert_eq(
      @moonredis.aggregate_field(applied.rows[0], "d").unwrap().double(),
      Some(2.0),
    )

    let paged = c.ft_aggregate(index, "*", options={
      ..@moonredis.aggregate_default,
      load: ["@num"],
      sort_by: [{ field: "@num", ascending: true, }],
      cursor_count: Some(1),
    })
    assert_eq(paged.rows.length(), 1)
    let cursor = paged.cursor.unwrap()
    let next = c.ft_cursor_read(index, cursor, count=1)
    assert_eq(next.rows.length(), 1)
    assert_true(next.cursor is Some(_))

    let info = c.ft_info(index)
    assert_eq(info.name, index)
    assert_eq(info.key_type, "HASH")
    assert_eq(info.prefixes, [prefix])
    assert_eq(info.num_docs, 2L)
    assert_eq(info.attributes.length(), 3)
    assert_eq(info.attributes[0].attribute, "title")
    assert_true(info.attributes[0].sortable)

    assert_true(c.ft_explain(index, "hello").contains("hello"))
    assert_true(c.ft_explaincli(index, "hello").length() > 0)

    let tags = c.ft_tagvals(index, "tag")
    assert_eq(tags.length(), 2)
    assert_true(tags.contains("x"))

    let misspelt = c.ft_spellcheck(index, "helo")
    assert_eq(misspelt.length(), 1)
    assert_eq(misspelt[0].term, "helo")

    assert_eq(c.ft_dictadd("moonredis:mod:dict", ["redis", "moonbit"]), 2L)
    let dictionary = c.ft_dictdump("moonredis:mod:dict")
    assert_eq(dictionary.length(), 2)
    assert_true(dictionary.contains("moonbit"))
    assert_eq(c.ft_dictdel("moonredis:mod:dict", ["redis"]), 1L)

    c.ft_synupdate(index, "1", ["hello", "hi"])
    let synonyms = c.ft_syndump(index)
    assert_true(synonyms.length() >= 2)

    assert_eq(c.ft_sugadd("moonredis:mod:sug", "hello", 1.0), 1L)
    assert_eq(c.ft_sugadd("moonredis:mod:sug", "help", 2.0), 2L)
    assert_eq(c.ft_sugget("moonredis:mod:sug", "hel"), ["help", "hello"])
    assert_eq(c.ft_sugget_scored("moonredis:mod:sug", "hel").length(), 2)
    assert_eq(c.ft_suglen("moonredis:mod:sug"), 2L)
    assert_true(c.ft_sugdel("moonredis:mod:sug", "help"))
    assert_eq(c.ft_suglen("moonredis:mod:sug"), 1L)

    // An alias resolves to the index itself, which is what `FT.INFO` reports by name.
    c.ft_aliasdel("moonredis:mod:alias") catch {
      _ => ()
    }
    c.ft_aliasadd("moonredis:mod:alias", index)
    assert_eq(c.ft_info("moonredis:mod:alias").name, index)
    c.ft_aliasupdate("moonredis:mod:alias", index)
    c.ft_aliasdel("moonredis:mod:alias")

    let config = c.ft_config_get("timeout")
    assert_eq(config.length(), 1)
    assert_eq(config[0].0, "TIMEOUT")

    // RESP2 answers `[result, profile]`; RESP3 answers a map of `Results` and `Profile`.
    let profile = c.ft_profile(index, false, "hello")
    let profile_parts = match profile {
      @resp.Array(items) => items.length()
      @resp.RespMap(pairs) => pairs.length()
      _ => 0
    }
    assert_eq(profile_parts, 2)

    c.ft_dropindex(index, delete_documents=true)
    assert_eq(c.exists([prefix + "1", prefix + "2"]), 0L)
    ignore(c.del(["moonredis:mod:sug", "moonredis:mod:dict"]))
  }
}

///|
async test "modules: search over json documents and vectors" {
  for protocol in [@moonredis.Resp2, @moonredis.Resp3] {
    guard connect(0, protocol) is Some(c) else { return }
    let index = "moonredis:mod:vidx"
    let prefix = "moonredis:mod:vec:"
    c.ft_dropindex(index, delete_documents=true) catch {
      _ => ()
    }
    c.ft_create(index, {
      ..@moonredis.Schema::new([
        @moonredis.SchemaField::text("$.title", as_="title"),
        @moonredis.SchemaField::vector(
          "$.vec",
          @moonredis.VectorSpec::flat(2, distance="L2"),
          as_="vec",
        ),
      ]),
      on: @moonredis.Json,
      prefixes: [prefix],
    })
    let first : Bytes = b"\x00\x00\x80\x3f\x00\x00\x00\x00"
    let second : Bytes = b"\x00\x00\x00\x00\x00\x00\x80\x3f"
    ignore(
      c.json_set(
        prefix + "1",
        "$",
        @json.parse("{\"title\":\"x\",\"vec\":[1,0]}"),
      ),
    )
    ignore(
      c.json_set(
        prefix + "2",
        "$",
        @json.parse("{\"title\":\"y\",\"vec\":[0,1]}"),
      ),
    )

    let found = c.ft_search(index, "x")
    assert_eq(found.total, 1L)
    assert_eq(found.hits[0].id, prefix + "1")

    let nearest = c.ft_search(index, "*=>[KNN 1 @vec $q AS dist]", options={
      ..@moonredis.search_default,
      params: [("q", first)],
      sort_by: Some({ field: "dist", ascending: true, }),
      return_fields: ["dist"],
      dialect: Some(2),
    })
    assert_eq(nearest.total, 1L)
    assert_eq(nearest.hits[0].id, prefix + "1")
    let _ = second

    let info = c.ft_info(index)
    assert_eq(info.key_type, "JSON")
    assert_eq(info.num_docs, 2L)

    c.ft_dropindex(index, delete_documents=true)
  }
}

///|
async test "modules: time series" {
  for protocol in [@moonredis.Resp2, @moonredis.Resp3] {
    guard connect(4, protocol) is Some(c) else { return }
    let key = "moonredis:mod:ts"
    let other = "moonredis:mod:ts2"
    ignore(c.del([key, other, "moonredis:mod:ts-avg"]))
    c.ts_create(key, retention=60000, labels=[("sensor", "s1")])
    assert_eq(c.ts_add(key, 1000, 1.5), 1000L)
    let added = c.ts_madd([(key, 2000, 2.5), (key, 3000, 3.5)])
    assert_eq(added, [Some(2000L), Some(3000L)])

    let samples = c.ts_range(key, @moonredis.Min, @moonredis.Max)
    assert_eq(samples.length(), 3)
    assert_eq(samples[0].timestamp, 1000L)
    assert_eq(samples[0].value, 1.5)
    assert_eq(samples[2].value, 3.5)

    let limited = c.ts_range(key, @moonredis.Min, @moonredis.Max, options={
      ..@moonredis.range_default,
      count: 2,
    })
    assert_eq(limited.length(), 2)

    let averaged = c.ts_range(key, @moonredis.Min, @moonredis.Max, options={
      ..@moonredis.range_default,
      aggregation: Some("avg"),
      bucket: 2000,
    })
    assert_eq(averaged.length(), 2)
    assert_eq(averaged[0].value, 1.5)
    assert_eq(averaged[1].value, 3.0)

    let high = c.ts_range(key, @moonredis.Min, @moonredis.Max, options={
      ..@moonredis.range_default,
      filter_by_value: Some((3.0, 4.0)),
    })
    assert_eq(high.length(), 1)
    assert_eq(high[0].timestamp, 3000L)

    let reversed = c.ts_revrange(key, @moonredis.Min, @moonredis.Max)
    assert_eq(reversed[0].timestamp, 3000L)

    let latest = c.ts_get(key).unwrap()
    assert_eq(latest.timestamp, 3000L)
    assert_eq(latest.value, 3.5)

    let by_label = c.ts_mrange(@moonredis.Min, @moonredis.Max, ["sensor=s1"], options={
      ..@moonredis.multi_range_default,
      with_labels: true,
    })
    assert_eq(by_label.length(), 1)
    assert_eq(by_label[0].key, key)
    assert_eq(by_label[0].labels, [("sensor", "s1")])
    assert_eq(by_label[0].samples.length(), 3)

    let newest = c.ts_mget(["sensor=s1"])
    assert_eq(newest[0].samples[0].value, 3.5)
    ignore(c.del([key, other]))
  }
}

///|
async test "modules: time series labels, rules and info" {
  for protocol in [@moonredis.Resp2, @moonredis.Resp3] {
    guard connect(4, protocol) is Some(c) else { return }
    let key = "moonredis:mod:ts"
    let other = "moonredis:mod:ts2"
    let compacted = "moonredis:mod:ts-avg"
    ignore(c.del([key, other, compacted]))
    c.ts_create(key, retention=60000, labels=[("sensor", "s1")])
    ignore(c.ts_add(key, 1000, 1.5))
    ignore(c.ts_add(key, 2000, 2.5))
    ignore(c.ts_add(key, 3000, 3.5))

    let info = c.ts_info(key)
    assert_eq(info.total_samples, 3L)
    assert_eq(info.retention_millis, 60000L)
    assert_eq(info.labels, [("sensor", "s1")])

    assert_eq(c.ts_queryindex(["sensor=s1"]), [key])
    assert_eq(c.ts_querylabels(), ["sensor"])
    assert_eq(c.ts_querylabel_values("sensor"), ["s1"])

    let from_2000 = c.ts_read(key, 2000)
    assert_eq(from_2000.length(), 2)
    assert_eq(from_2000[0].timestamp, 2000L)

    c.ts_create(other, labels=[("sensor", "s1")])
    ignore(c.ts_add(other, 1000, 10.0))
    ignore(c.ts_add(other, 3000, 30.0))
    let pivoted = c.ts_nrange([key, other], @moonredis.Min, @moonredis.Max)
    assert_eq(pivoted.length(), 3)
    assert_eq(pivoted[0].values, [Some(1.5), Some(10.0)])
    assert_eq(pivoted[1].values, [Some(2.5), None])

    c.ts_create(compacted)
    c.ts_createrule(key, compacted, "avg", 10000)
    assert_eq(c.ts_info(key).rules.length(), 1)
    assert_eq(c.ts_info(key).rules[0].destination, compacted)
    c.ts_deleterule(key, compacted)

    assert_eq(c.ts_del(key, "0", "1000"), 1L)
    assert_eq(c.ts_range(key, @moonredis.Min, @moonredis.Max).length(), 2)
    ignore(c.del([key, other, compacted]))
  }
}

///|
async test "modules: bloom and cuckoo filters" {
  for protocol in [@moonredis.Resp2, @moonredis.Resp3] {
    guard connect(5, protocol) is Some(c) else { return }
    let bloom = "moonredis:mod:bf"
    let copy = "moonredis:mod:bf-copy"
    ignore(c.del([bloom, copy]))
    c.bf_reserve(bloom, 0.01, 100)
    assert_true(c.bf_add(bloom, "a"))
    assert_false(c.bf_add(bloom, "a"))
    assert_eq(c.bf_madd(bloom, ["b", "c"]), [true, true])
    assert_true(c.bf_exists(bloom, "b"))
    assert_false(c.bf_exists(bloom, "zzz"))
    assert_eq(c.bf_mexists(bloom, ["a", "zzz"]), [true, false])
    assert_eq(c.bf_card(bloom), 3L)
    let info = c.bf_info(bloom)
    assert_eq(info.int("Capacity"), Some(100L))
    assert_eq(info.int("Number of items inserted"), Some(3L))

    // A dump is a list of chunks; the iterator 0 comes back with no data and ends it.
    let mut iterator = 0L
    let copy_key = copy
    while true {
      let (next, chunk) = c.bf_scandump(bloom, iterator)
      if next == 0L {
        break
      }
      guard chunk is Some(data) else { fail("a chunk without data") }
      c.bf_loadchunk(copy_key, next, data)
      iterator = next
    }
    assert_true(c.bf_exists(copy, "a"))

    let inserted = c.bf_insert("moonredis:mod:bf2", ["x", "y"], capacity=100)
    assert_eq(inserted, [true, true])

    let cuckoo = "moonredis:mod:cf"
    ignore(c.del([cuckoo]))
    c.cf_reserve(cuckoo, 100)
    assert_true(c.cf_add(cuckoo, "a"))
    assert_false(c.cf_addnx(cuckoo, "a"))
    assert_true(c.cf_add(cuckoo, "a"))
    assert_eq(c.cf_count(cuckoo, "a"), 2L)
    assert_true(c.cf_exists(cuckoo, "a"))
    assert_eq(c.cf_mexists(cuckoo, ["a", "zzz"]), [true, false])
    assert_eq(c.cf_insert(cuckoo, ["b", "c"], capacity=100), [true, true])
    assert_eq(c.cf_insertnx(cuckoo, ["b", "d"], capacity=100), [false, true])
    assert_true(c.cf_del(cuckoo, "a"))
    let cuckoo_info = c.cf_info(cuckoo)
    assert_eq(cuckoo_info.int("Number of buckets").unwrap() > 0, true)
    ignore(c.del([bloom, copy, cuckoo, "moonredis:mod:bf2"]))
  }
}

///|
async test "modules: count-min sketch, top-k and t-digest" {
  for protocol in [@moonredis.Resp2, @moonredis.Resp3] {
    guard connect(6, protocol) is Some(c) else { return }
    let sketch = "moonredis:mod:cms"
    let merged = "moonredis:mod:cms-sum"
    ignore(c.del([sketch, merged]))
    c.cms_initbydim(sketch, 100, 5)
    assert_eq(c.cms_incrby(sketch, [("a", 3), ("b", 2)]), [3L, 2L])
    assert_eq(c.cms_query(sketch, ["a", "zzz"]), [3L, 0L])
    let cms_info = c.cms_info(sketch)
    assert_eq(cms_info.int("width"), Some(100L))
    assert_eq(cms_info.int("depth"), Some(5L))
    assert_eq(cms_info.int("count"), Some(5L))
    c.cms_initbydim(merged, 100, 5)
    c.cms_merge(merged, [sketch])
    assert_eq(c.cms_query(merged, ["a"]), [3L])

    let top = "moonredis:mod:topk"
    ignore(c.del([top]))
    c.topk_reserve(top, 3)
    let evicted = c.topk_add(top, ["a", "b", "a", "c", "a"])
    assert_eq(evicted, [None, None, None, None, None])
    assert_eq(c.topk_query(top, ["a", "zzz"]), [true, false])
    assert_true(c.topk_count(top, ["a"])[0] > 0L)
    assert_eq(c.topk_list(top), ["a", "b", "c"])
    let with_counts = c.topk_list_with_count(top)
    assert_eq(with_counts.length(), 3)
    assert_eq(with_counts[0].0, "a")
    assert_eq(c.topk_info(top).int("k"), Some(3L))

    let digest = "moonredis:mod:td"
    let digest_copy = "moonredis:mod:td-copy"
    ignore(c.del([digest, digest_copy]))
    c.tdigest_create(digest, compression=100)
    c.tdigest_add(digest, [1.0, 2.0, 3.0, 4.0, 5.0])
    assert_eq(c.tdigest_min(digest), 1.0)
    assert_eq(c.tdigest_max(digest), 5.0)
    let median = c.tdigest_quantile(digest, [0.5])
    assert_true(median[0] > 2.9 && median[0] < 3.1)
    let cdf = c.tdigest_cdf(digest, [3.0])
    assert_true(cdf[0] > 0.49 && cdf[0] < 0.51)
    assert_eq(c.tdigest_rank(digest, [3.0]), [2L])
    assert_eq(c.tdigest_revrank(digest, [3.0]), [2L])
    assert_eq(c.tdigest_byrank(digest, [0]), [1.0])
    assert_eq(c.tdigest_byrevrank(digest, [0]), [5.0])
    let mean = c.tdigest_trimmed_mean(digest, 0.1, 0.9)
    assert_true(mean > 2.9 && mean < 3.1)
    let digest_info = c.tdigest_info(digest)
    assert_eq(digest_info.int("Observations"), Some(5L))
    assert_eq(digest_info.int("Compression"), Some(100L))
    c.tdigest_merge(digest_copy, [digest], compression=100)
    assert_eq(c.tdigest_min(digest_copy), 1.0)
    c.tdigest_reset(digest)
    assert_true(c.tdigest_min(digest).is_nan())
    ignore(c.del([sketch, merged, top, digest, digest_copy]))
  }
}
