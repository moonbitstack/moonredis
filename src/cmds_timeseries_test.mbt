// The time series commands through the in-memory `FakeConn`, over both wire shapes: RESP2
// writes a sample value as text, RESP3 as a double, and a multi-series reply is an array
// under RESP2 but a map under RESP3.

///|
async test "timeseries: range sends the aggregation and reads text values" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.Array([@resp.Integer(0), @resp.SimpleString("1.5")]),
      @resp.Array([@resp.Integer(2000), @resp.SimpleString("3")]),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let samples = client.ts_range("t", @moonredis.Min, @moonredis.Max, options={
    ..@moonredis.range_default,
    aggregation: Some("avg"),
    bucket: 2000,
    count: 2,
  })
  assert_eq(conn.sent()[0], [
    b"TS.RANGE", b"t", b"-", b"+", b"COUNT", b"2", b"AGGREGATION", b"avg", b"2000",
  ])
  assert_eq(samples.length(), 2)
  assert_eq(samples[0].timestamp, 0L)
  assert_eq(samples[0].value, 1.5)
  assert_eq(samples[1].value, 3.0)
}

///|
async test "timeseries: range reads the doubles resp3 sends" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Array([@resp.Integer(1000), @resp.Double(2.5)])]),
  ])
  let client = @moonredis.Client::new(conn)
  let samples = client.ts_range("t", @moonredis.At(1000), @moonredis.Max)
  assert_eq(conn.sent()[0], [b"TS.RANGE", b"t", b"1000", b"+"])
  assert_eq(samples[0].value, 2.5)
}

///|
async test "timeseries: add and madd return the timestamps" {
  let conn = @moonredis.FakeConn::new([
    @resp.Integer(1000),
    @resp.Array([
      @resp.Integer(2000),
      @resp.Error("ERR TSDB: wrong fromTimestamp"),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  assert_eq(client.ts_add("t", 1000, 1.5, labels=[("sensor", "s1")]), 1000L)
  assert_eq(conn.sent()[0], [
    b"TS.ADD", b"t", b"1000", b"1.5", b"LABELS", b"sensor", b"s1",
  ])
  let added = client.ts_madd([("t", 2000, 2.5), ("t", 3000, 3.5)])
  assert_eq(added, [Some(2000L), None])
}

///|
async test "timeseries: mrange reads the flat resp2 reply" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.Array([
        @resp.BulkString(b"t1"),
        @resp.Array([
          @resp.Array([@resp.BulkString(b"sensor"), @resp.BulkString(b"s1")]),
        ]),
        @resp.Array([
          @resp.Array([@resp.Integer(1000), @resp.SimpleString("1")]),
        ]),
      ]),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let series = client.ts_mrange(@moonredis.Min, @moonredis.Max, ["sensor=s1"], options={
    ..@moonredis.multi_range_default,
    with_labels: true,
  })
  assert_eq(conn.sent()[0], [
    b"TS.MRANGE", b"-", b"+", b"WITHLABELS", b"FILTER", b"sensor=s1",
  ])
  assert_eq(series.length(), 1)
  assert_eq(series[0].key, "t1")
  assert_eq(series[0].labels, [("sensor", "s1")])
  assert_eq(series[0].samples[0].value, 1.0)
}

///|
async test "timeseries: mrange reads the map resp3 reply" {
  let conn = @moonredis.FakeConn::new([
    @resp.RespMap([
      (
        @resp.BulkString(b"t1"),
        @resp.Array([
          @resp.RespMap([(@resp.BulkString(b"sensor"), @resp.BulkString(b"s1"))]),
          @resp.RespMap([(@resp.BulkString(b"aggregators"), @resp.Array([]))]),
          @resp.Array([@resp.Array([@resp.Integer(1000), @resp.Double(1.0)])]),
        ]),
      ),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let series = client.ts_mrange(@moonredis.Min, @moonredis.Max, ["sensor=s1"])
  assert_eq(series[0].key, "t1")
  assert_eq(series[0].labels, [("sensor", "s1")])
  assert_eq(series[0].samples[0].value, 1.0)
}

///|
async test "timeseries: info reads the flat reply and its labels" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.SimpleString("totalSamples"),
      @resp.Integer(6),
      @resp.SimpleString("memoryUsage"),
      @resp.Integer(5224),
      @resp.SimpleString("firstTimestamp"),
      @resp.Integer(1000),
      @resp.SimpleString("lastTimestamp"),
      @resp.Integer(6000),
      @resp.SimpleString("chunkType"),
      @resp.SimpleString("compressed"),
      @resp.SimpleString("labels"),
      @resp.Array([
        @resp.Array([@resp.BulkString(b"sensor"), @resp.BulkString(b"s1")]),
      ]),
      @resp.SimpleString("sourceKey"),
      @resp.Null,
      @resp.SimpleString("rules"),
      @resp.Array([]),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let info = client.ts_info("t")
  assert_eq(info.total_samples, 6L)
  assert_eq(info.memory_usage, 5224L)
  assert_eq(info.first_timestamp, 1000L)
  assert_eq(info.chunk_type, "compressed")
  assert_eq(info.labels, [("sensor", "s1")])
  assert_eq(info.source_key, None)
  assert_eq(info.rules.length(), 0)
}

///|
async test "timeseries: nrange pivots rows and marks a gap" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([
      @resp.Array([
        @resp.Integer(1000),
        @resp.Array([@resp.SimpleString("1"), @resp.SimpleString("NaN")]),
      ]),
      @resp.Array([
        @resp.Integer(2000),
        @resp.Array([@resp.SimpleString("2"), @resp.SimpleString("20")]),
      ]),
    ]),
  ])
  let client = @moonredis.Client::new(conn)
  let rows = client.ts_nrange(["n1", "n2"], @moonredis.Min, @moonredis.Max)
  assert_eq(conn.sent()[0], [b"TS.NRANGE", b"2", b"n1", b"n2", b"-", b"+"])
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].values, [Some(1.0), None])
  assert_eq(rows[1].values, [Some(2.0), Some(20.0)])
}

///|
async test "timeseries: get answers nothing for an empty series" {
  let conn = @moonredis.FakeConn::new([
    @resp.Array([@resp.Integer(6000), @resp.SimpleString("7.5")]),
    @resp.Null,
  ])
  let client = @moonredis.Client::new(conn)
  let sample = client.ts_get("t").unwrap()
  assert_eq(sample.timestamp, 6000L)
  assert_eq(sample.value, 7.5)
  assert_eq(client.ts_get("empty"), None)
}
