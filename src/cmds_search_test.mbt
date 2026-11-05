// The search commands through the in-memory `FakeConn`, over both wire shapes: RESP2
// writes a search result as a flat array of ids and field lists, RESP3 as a map with
// `results` and `total_results`.

///|
async test "search: resp2 reply with scores, sort keys and fields" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.Integer(1),
      @resp.BulkString(b"d:1"),
      @resp.BulkString(b"0.5"),
      @resp.BulkString(b"#1"),
      @resp.Array([@resp.BulkString(b"title"), @resp.BulkString(b"alpha")]),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let result = client.ft_search("idx", "alpha", options={
    ..@moonredis.search_default,
    with_scores: true,
    with_sort_keys: true,
    return_fields: ["title"],
    limit: 1,
  })
  assert_eq(conn.sent()[0], [
    b"FT.SEARCH", b"idx", b"alpha", b"WITHSCORES", b"WITHSORTKEYS", b"RETURN", b"1",
    b"title", b"LIMIT", b"0", b"1",
  ])
  assert_eq(result.total, 1L)
  assert_eq(result.hits.length(), 1)
  assert_eq(result.hits[0].id, "d:1")
  assert_eq(result.hits[0].score, Some(0.5))
  assert_eq(result.hits[0].sort_key, Some("#1"))
  assert_eq(result.hits[0].field("title"), Some("alpha"))
}

///|
async test "search: resp3 reply keyed by result fields" {
  let conn = @moonredis.FakeConn::new([
    @resp.RespMap([
      (@resp.SimpleString("attributes"), @resp.Array([])),
      (@resp.SimpleString("format"), @resp.SimpleString("STRING")),
      (@resp.SimpleString("total_results"), @resp.Integer(7)),
      (
        @resp.SimpleString("results"),
        @resp.Array([
          @resp.RespMap([
            (@resp.SimpleString("id"), @resp.BulkString(b"d:2")),
            (@resp.SimpleString("score"), @resp.Double(0.25)),
            (
              @resp.SimpleString("extra_attributes"),
              @resp.RespMap([
                (@resp.BulkString(b"title"), @resp.BulkString(b"beta")),
              ]),
            ),
            (@resp.SimpleString("values"), @resp.Array([])),
          ]),
        ]),
      ),
      (@resp.SimpleString("warning"), @resp.Array([])),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let result = client.ft_search("idx", "*", options={
    ..@moonredis.search_default,
    with_scores: true,
    limit: 1,
  })
  assert_eq(result.total, 7L)
  assert_eq(result.hits[0].id, "d:2")
  assert_eq(result.hits[0].score, Some(0.25))
  assert_eq(result.hits[0].field("title"), Some("beta"))
}

///|
async test "search: nocontent returns ids only" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.Integer(2),
      @resp.BulkString(b"d:1"),
      @resp.BulkString(b"d:2"),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let result = client.ft_search("idx", "*", options={
    ..@moonredis.search_default,
    nocontent: true,
  })
  assert_eq(result.total, 2L)
  assert_eq(result.hits.map(hit => hit.id), ["d:1", "d:2"])
  assert_eq(result.hits[0].fields.length(), 0)
}

///|
async test "search: the sort, filters, params and dialect go out in order" {
  let conn = @moonredis.FakeConn::new([@resp.Array([@resp.Integer(0)])])
  let client = @moonredis.Client::new(conn)
  ignore(
    client.ft_search("idx", "@n:[1 9]", options={
      ..@moonredis.search_default,
      sort_by: Some({ field: "n", ascending: false, }),
      filter: Some({ field: "n", min: "1", max: "9", }),
      params: [("lo", b"1")],
      dialect: Some(2),
    }),
  )
  assert_eq(conn.sent()[0], [
    b"FT.SEARCH", b"idx", b"@n:[1 9]", b"SORTBY", b"n", b"DESC", b"FILTER", b"n",
    b"1", b"9", b"PARAMS", b"2", b"lo", b"1", b"DIALECT", b"2",
  ])
}

///|
async test "search: create writes the schema it was given" {
  let conn = @moonredis.FakeConn::new([@resp.SimpleString("OK")])
  let client = @moonredis.Client::new(conn)
  let schema = {
    ..@moonredis.Schema::new([
      @moonredis.SchemaField::text("title", sortable=true, weight=2.0),
      @moonredis.SchemaField::tag("tags", separator=","),
      @moonredis.SchemaField::numeric("price", sortable=true),
    ]),
    prefixes: ["d:"],
  }
  client.ft_create("idx", schema)
  assert_eq(conn.sent()[0], [
    b"FT.CREATE", b"idx", b"ON", b"HASH", b"PREFIX", b"1", b"d:", b"SCHEMA", b"title",
    b"TEXT", b"WEIGHT", b"2", b"SORTABLE", b"tags", b"TAG", b"SEPARATOR", b",", b"price",
    b"NUMERIC", b"SORTABLE",
  ])
}

///|
async test "search: create writes a vector field with its parameter count" {
  let conn = @moonredis.FakeConn::new([@resp.SimpleString("OK")])
  let client = @moonredis.Client::new(conn)
  let spec = @moonredis.VectorSpec::hnsw(2, distance="COSINE", m=16)
  client.ft_create("vidx", {
    ..@moonredis.Schema::new([
      @moonredis.SchemaField::vector("vec", spec, as_="embedding"),
    ]),
    on: @moonredis.Json,
  })
  assert_eq(conn.sent()[0], [
    b"FT.CREATE", b"vidx", b"ON", b"JSON", b"SCHEMA", b"vec", b"AS", b"embedding",
    b"VECTOR", b"HNSW", b"8", b"TYPE", b"FLOAT32", b"DIM", b"2", b"DISTANCE_METRIC",
    b"COSINE", b"M", b"16",
  ])
}

///|
async test "search: aggregate reads rows and the cursor of both protocols" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.Integer(2),
      @resp.Array([
        @resp.BulkString(b"tag"),
        @resp.BulkString(b"x"),
        @resp.BulkString(b"c"),
        @resp.BulkString(b"1"),
      ]),
    ]),
    @resp.Array([@resp.Array([@resp.Integer(1)]), @resp.Integer(42)]),
  ])
  let client = @moonredis.Client::new(conn)
  let result = client.ft_aggregate("idx", "*")
  assert_eq(result.total, 2L)
  assert_eq(
    @moonredis.aggregate_field(result.rows[0], "tag").unwrap().text(),
    Some("x"),
  )
  assert_eq(result.cursor, None)
  let paged = client.ft_aggregate("idx", "*", options={
    ..@moonredis.aggregate_default,
    group_by: ["@tag"],
    reducers: [{ function: "COUNT", args: [], as_: Some("c"), }],
    cursor_count: Some(1),
  })
  assert_eq(paged.cursor, Some(42L))
  assert_eq(conn.sent()[1], [
    b"FT.AGGREGATE", b"idx", b"*", b"GROUPBY", b"1", b"@tag", b"REDUCE", b"COUNT",
    b"0", b"AS", b"c", b"WITHCURSOR", b"COUNT", b"1",
  ])
}

///|
async test "search: aggregate reads the resp3 rows under extra_attributes" {
  let conn = @moonredis.FakeConn::new([
    @resp.RespMap([
      (@resp.SimpleString("total_results"), @resp.Integer(1)),
      (
        @resp.SimpleString("results"),
        @resp.Array([
          @resp.RespMap([
            (
              @resp.SimpleString("extra_attributes"),
              @resp.RespMap([
                (@resp.BulkString(b"tag"), @resp.BulkString(b"y")),
                (@resp.BulkString(b"c"), @resp.BulkString(b"3")),
              ]),
            ),
            (@resp.SimpleString("values"), @resp.Array([])),
          ]),
        ]),
      ),
      (@resp.SimpleString("warning"), @resp.Array([])),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let result = client.ft_aggregate("idx", "*")
  assert_eq(result.rows.length(), 1)
  assert_eq(result.rows[0].length(), 2)
  assert_eq(
    @moonredis.aggregate_field(result.rows[0], "c").unwrap().int(),
    Some(3L),
  )
}

///|
async test "search: info reads the flat resp2 reply and its attributes" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.SimpleString("index_name"),
      @resp.SimpleString("idx"),
      @resp.SimpleString("num_docs"),
      @resp.Integer(3),
      @resp.SimpleString("index_definition"),
      @resp.Array([
        @resp.SimpleString("key_type"),
        @resp.SimpleString("HASH"),
        @resp.SimpleString("prefixes"),
        @resp.Array([@resp.SimpleString("d:")]),
        @resp.SimpleString("default_score"),
        @resp.BulkString(b"1"),
      ]),
      @resp.SimpleString("attributes"),
      @resp.Array([
        @resp.Array([
          @resp.SimpleString("identifier"),
          @resp.SimpleString("title"),
          @resp.SimpleString("attribute"),
          @resp.SimpleString("title"),
          @resp.SimpleString("type"),
          @resp.SimpleString("TEXT"),
          @resp.SimpleString("WEIGHT"),
          @resp.BulkString(b"2"),
          @resp.SimpleString("SORTABLE"),
          @resp.SimpleString("UNF"),
        ]),
      ]),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let info = client.ft_info("idx")
  assert_eq(info.name, "idx")
  assert_eq(info.num_docs, 3L)
  assert_eq(info.prefixes, ["d:"])
  assert_eq(info.attributes.length(), 1)
  assert_eq(info.attributes[0].attribute, "title")
  assert_eq(info.attributes[0].weight, 2.0)
  assert_true(info.attributes[0].sortable)
  assert_true(info.attributes[0].unf)
}

///|
async test "search: spellcheck reads both wire shapes" {
  let resp2 = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.Array([
        @resp.SimpleString("TERM"),
        @resp.BulkString(b"helo"),
        @resp.Array([
          @resp.Array([@resp.BulkString(b"0.5"), @resp.BulkString(b"hello")]),
        ]),
      ]),
    ]),
  ])
  let first = @moonredis.Client::new(resp2).ft_spellcheck("idx", "helo")
  assert_eq(first[0].term, "helo")
  assert_eq(first[0].suggestions, [(0.5, "hello")])

  let resp3 = @moonredis.FakeConn::new([
    @resp.RespMap([
      (
        @resp.SimpleString("results"),
        @resp.RespMap([
          (
            @resp.BulkString(b"helo"),
            @resp.Array([
              @resp.RespMap([(@resp.BulkString(b"hello"), @resp.Double(0.5))]),
            ]),
          ),
        ]),
      ),
    ]),
  ])
  let second = @moonredis.Client::new(resp3).ft_spellcheck("idx", "helo")
  assert_eq(second[0].term, "helo")
  assert_eq(second[0].suggestions, [(0.5, "hello")])
}

///|
async test "search: suggestions carry their scores" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.BulkString(b"hello"),
      @resp.BulkString(b"0.5773502588272095"),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let suggestions = client.ft_sugget_scored("sug", "hel")
  assert_eq(conn.sent()[0], [b"FT.SUGGET", b"sug", b"hel", b"WITHSCORES"])
  assert_eq(suggestions.length(), 1)
  assert_eq(suggestions[0].0, "hello")
  assert_true(suggestions[0].1 > 0.57 && suggestions[0].1 < 0.58)
}
