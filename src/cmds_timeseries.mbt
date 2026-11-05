// The time series commands. A key holds a stream of (timestamp, value) samples with
// retention, labels for filtering, and optional compaction rules that roll samples into
// another series. A sample crosses the wire as text under RESP2 and as a double under
// RESP3; both arrive as a `Sample` here.
// https://redis.io/docs/latest/commands/?group=timeseries

///|
/// One sample: when it was recorded, and what it measured.
#derive(Eq, Debug)
pub(all) struct Sample {
  timestamp : Int64
  value : Double
}

///|
pub extend Sample with Debug::{to_repr}

///|
pub extend Sample with Eq::{not_equal, equal}

///|
/// One series of a multi-series reply: its key, its labels, and the samples the query
/// selected.
pub(all) struct Series {
  key : String
  labels : Array[(String, String)]
  samples : Array[Sample]
}

///|
/// One row of a reply pivoted by timestamp: the timestamp and one value per key, `None`
/// where that key has no sample there.
pub(all) struct PivotRow {
  timestamp : Int64
  values : Array[Double?]
}

///|
/// A point in a range query: the earliest sample the series has, the latest, or a
/// timestamp.
#derive(Eq, Debug)
pub(all) enum TimeBound {
  Min
  Max
  At(Int64)
}

///|
pub extend TimeBound with Debug::{to_repr}

///|
pub extend TimeBound with Eq::{not_equal, equal}

///|
/// The `-`, `+` or decimal text a range query writes for this bound.
pub fn TimeBound::text(self : TimeBound) -> String {
  match self {
    Min => "-"
    Max => "+"
    At(t) => t.to_string()
  }
}

///|
/// The options a range query takes: paging, filtering, and how to bucket the samples.
pub(all) struct RangeOptions {
  /// Report the compacted value of a partial bucket at the end.
  latest : Bool
  /// Keep only these timestamps.
  filter_by_ts : Array[Int64]
  /// Keep only samples in this value range.
  filter_by_value : (Double, Double)?
  /// The most samples to return; 0 returns them all.
  count : Int64
  /// `avg`, `sum`, `min`, `max`, `range`, `count`, `first`, `last`, `std.p`, `std.s`,
  /// `var.p`, `var.s` or `twa`.
  aggregation : String?
  /// The width of each aggregation bucket, in milliseconds.
  bucket : Int64
  /// Where buckets start: a timestamp, `-` (the range start) or `+` (the range end).
  align : String?
  /// How a bucket is stamped: `-`, `+` or `~`.
  bucket_timestamp : String?
  /// Report buckets with no samples as well.
  empty : Bool
}

///|
/// Range options at their documented defaults.
pub let range_default : RangeOptions = RangeOptions::{
  latest: false,
  filter_by_ts: [],
  filter_by_value: None,
  count: 0,
  aggregation: None,
  bucket: 0,
  align: None,
  bucket_timestamp: None,
  empty: false,
}

///|
/// The options a multi-series query adds: which labels to carry, and how to group.
pub(all) struct MultiRangeOptions {
  range : RangeOptions
  /// Carry each series' labels into the reply.
  with_labels : Bool
  /// Carry only these labels.
  select_labels : Array[String]
  /// Group the series by this label instead of returning each on its own.
  group_by : String?
  /// The reducer the grouped series share.
  reduce : String?
  /// Leave out a series whose sample list came back empty.
  exclude_empty : Bool
}

///|
/// Multi-series range options at their documented defaults.
pub let multi_range_default : MultiRangeOptions = MultiRangeOptions::{
  range: range_default,
  with_labels: false,
  select_labels: [],
  group_by: None,
  reduce: None,
  exclude_empty: false,
}

///|
/// The options a multi-series point query takes.
pub(all) struct MultiGetOptions {
  with_labels : Bool
  select_labels : Array[String]
  latest : Bool
}

///|
/// Multi-series get options at their documented defaults.
pub let multi_get_default : MultiGetOptions = MultiGetOptions::{
  with_labels: false,
  select_labels: [],
  latest: false,
}

///|
/// A compaction rule: the series this one rolls into, how wide each bucket is, and how the
/// bucket is reduced.
pub(all) struct CompactionRule {
  destination : String
  bucket : Int64
  aggregator : String
}

///|
/// What `TS.INFO` reports about a series.
pub(all) struct TsInfo {
  total_samples : Int64
  memory_usage : Int64
  first_timestamp : Int64
  last_timestamp : Int64
  retention_millis : Int64
  chunk_count : Int64
  chunk_size : Int64
  /// `compressed` or `uncompressed`.
  chunk_type : String
  duplicate_policy : String
  labels : Array[(String, String)]
  /// The series this one compacts from, when it is a compaction target.
  source_key : String?
  rules : Array[CompactionRule]
  ignore_max_time_diff : Int64
  ignore_max_val_diff : Double
}

///|
/// One `[timestamp, value]` pair.
fn decode_sample(reply : @resp.RespValue) -> Sample raise RedisError {
  let pair = expect_array(reply)
  guard pair.length() >= 2 else { raise Protocol("unexpected sample") }
  { timestamp: expect_int64(pair[0]), value: numeric_value(pair[1]), }
}

///|
/// A list of `[timestamp, value]` pairs.
fn decode_samples(reply : @resp.RespValue) -> Array[Sample] raise RedisError {
  expect_array(reply).map(decode_sample)
}

///|
/// The `[name, value]` pairs of a label set, from the map RESP3 sends or the array RESP2
/// sends.
fn decode_labels(
  reply : @resp.RespValue,
) -> Array[(String, String)] raise RedisError {
  let out : Array[(String, String)] = []
  match reply {
    @resp.RespMap(pairs) =>
      for (name, value) in pairs {
        out.push((expect_text(name), expect_text(value)))
      }
    other =>
      for item in expect_array(other) {
        let pair = expect_array(item)
        guard pair.length() >= 2 else { raise Protocol("unexpected label") }
        out.push((expect_text(pair[0]), expect_text(pair[1])))
      }
  }
  out
}

///|
/// Append the range options both the single and multi-series queries share.
fn push_range_options(args : Array[Bytes], options : RangeOptions) -> Unit {
  if options.latest {
    args.push(b"LATEST")
  }
  if options.filter_by_ts.length() > 0 {
    args.push(b"FILTER_BY_TS")
    for ts in options.filter_by_ts {
      args.push(arg_int64(ts))
    }
  }
  match options.filter_by_value {
    Some((min, max)) => {
      args.push(b"FILTER_BY_VALUE")
      args.push(arg_double(min))
      args.push(arg_double(max))
    }
    None => ()
  }
  if options.count > 0 {
    args.push(b"COUNT")
    args.push(arg_int64(options.count))
  }
  match options.aggregation {
    Some(aggregator) => {
      match options.align {
        Some(align) => {
          args.push(b"ALIGN")
          args.push(arg_string(align))
        }
        None => ()
      }
      args.push(b"AGGREGATION")
      args.push(arg_string(aggregator))
      args.push(arg_int64(options.bucket))
      match options.bucket_timestamp {
        Some(stamp) => {
          args.push(b"BUCKETTIMESTAMP")
          args.push(arg_string(stamp))
        }
        None => ()
      }
      if options.empty {
        args.push(b"EMPTY")
      }
    }
    None => ()
  }
}

///|
/// Append the label options a multi-series query takes.
fn push_label_options(
  args : Array[Bytes],
  with_labels : Bool,
  select_labels : Array[String],
) -> Unit {
  if select_labels.length() > 0 {
    args.push(b"SELECTED_LABELS")
    for label in select_labels {
      args.push(arg_string(label))
    }
  } else if with_labels {
    args.push(b"WITHLABELS")
  }
}

///|
/// Append the `LABELS` block `TS.CREATE` and its kin take.
fn push_ts_labels(
  args : Array[Bytes],
  labels : Array[(String, String)]?,
) -> Unit {
  match labels {
    Some(pairs) =>
      if pairs.length() > 0 {
        args.push(b"LABELS")
        for (name, value) in pairs {
          args.push(arg_string(name))
          args.push(arg_string(value))
        }
      }
    None => ()
  }
}

///|
/// `TS.CREATE key [RETENTION ms] [ENCODING COMPRESSED|UNCOMPRESSED] [CHUNK_SIZE bytes]
/// [DUPLICATE_POLICY policy] [IGNORE max_time_diff max_val_diff] [LABELS ...]`: create a
/// series, optionally dropping samples older than `retention`.
pub async fn Client::ts_create(
  self : Client,
  key : String,
  retention? : Int64,
  uncompressed? : Bool,
  chunk_size? : Int64,
  duplicate_policy? : String,
  ignore_max_time_diff? : Int64,
  ignore_max_val_diff? : Double,
  labels? : Array[(String, String)],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"TS.CREATE", arg_string(key)]
  push_some(args, b"RETENTION", retention.map(arg_int64))
  if uncompressed.unwrap_or(false) {
    args.push(b"ENCODING")
    args.push(b"UNCOMPRESSED")
  }
  push_some(args, b"CHUNK_SIZE", chunk_size.map(arg_int64))
  push_some(args, b"DUPLICATE_POLICY", duplicate_policy.map(arg_string))
  match (ignore_max_time_diff, ignore_max_val_diff) {
    (Some(time), Some(value)) => {
      args.push(b"IGNORE")
      args.push(arg_int64(time))
      args.push(arg_double(value))
    }
    _ => ()
  }
  push_ts_labels(args, labels)
  status_ok(self.command(args))
}

///|
/// `TS.ALTER key [RETENTION ms] [CHUNK_SIZE bytes] [DUPLICATE_POLICY policy]
/// [IGNORE ...] [LABELS ...]`: change a series' settings; `LABELS` replaces the label set.
pub async fn Client::ts_alter(
  self : Client,
  key : String,
  retention? : Int64,
  chunk_size? : Int64,
  duplicate_policy? : String,
  ignore_max_time_diff? : Int64,
  ignore_max_val_diff? : Double,
  labels? : Array[(String, String)],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"TS.ALTER", arg_string(key)]
  push_some(args, b"RETENTION", retention.map(arg_int64))
  push_some(args, b"CHUNK_SIZE", chunk_size.map(arg_int64))
  push_some(args, b"DUPLICATE_POLICY", duplicate_policy.map(arg_string))
  match (ignore_max_time_diff, ignore_max_val_diff) {
    (Some(time), Some(value)) => {
      args.push(b"IGNORE")
      args.push(arg_int64(time))
      args.push(arg_double(value))
    }
    _ => ()
  }
  push_ts_labels(args, labels)
  status_ok(self.command(args))
}

///|
/// `TS.ADD key timestamp value [RETENTION ms] [ENCODING ...] [CHUNK_SIZE bytes]
/// [ON_DUPLICATE policy] [LABELS ...]`: append one sample, returning its timestamp.
pub async fn Client::ts_add(
  self : Client,
  key : String,
  timestamp : Int64,
  value : Double,
  retention? : Int64,
  uncompressed? : Bool,
  chunk_size? : Int64,
  on_duplicate? : String,
  labels? : Array[(String, String)],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [
    b"TS.ADD",
    arg_string(key),
    arg_int64(timestamp),
    arg_double(value),
  ]
  push_some(args, b"RETENTION", retention.map(arg_int64))
  if uncompressed.unwrap_or(false) {
    args.push(b"ENCODING")
    args.push(b"UNCOMPRESSED")
  }
  push_some(args, b"CHUNK_SIZE", chunk_size.map(arg_int64))
  push_some(args, b"ON_DUPLICATE", on_duplicate.map(arg_string))
  push_ts_labels(args, labels)
  expect_int64(self.command(args))
}

///|
/// `TS.MADD key timestamp value [key timestamp value ...]`: append several samples at once,
/// returning each timestamp, `None` where that sample was refused.
pub async fn Client::ts_madd(
  self : Client,
  samples : Array[(String, Int64, Double)],
) -> Array[Int64?] raise RedisError {
  let args : Array[Bytes] = [b"TS.MADD"]
  for (key, timestamp, value) in samples {
    args.push(arg_string(key))
    args.push(arg_int64(timestamp))
    args.push(arg_double(value))
  }
  let out : Array[Int64?] = []
  for item in expect_array(self.command(args)) {
    match item {
      @resp.Error(_) | @resp.BulkError(_) => out.push(None)
      other => out.push(Some(expect_int64(other)))
    }
  }
  out
}

///|
/// `TS.INCRBY key value [TIMESTAMP ts] [RETENTION ms] [ENCODING ...] [CHUNK_SIZE bytes]
/// [DUPLICATE_POLICY policy] [LABELS ...]`: add `value` to the sample at `timestamp`,
/// creating the sample when there is none, and return the timestamp.
pub async fn Client::ts_incrby(
  self : Client,
  key : String,
  value : Double,
  timestamp? : Int64,
  retention? : Int64,
  uncompressed? : Bool,
  chunk_size? : Int64,
  duplicate_policy? : String,
  labels? : Array[(String, String)],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"TS.INCRBY", arg_string(key), arg_double(value)]
  push_some(args, b"TIMESTAMP", timestamp.map(arg_int64))
  push_some(args, b"RETENTION", retention.map(arg_int64))
  if uncompressed.unwrap_or(false) {
    args.push(b"ENCODING")
    args.push(b"UNCOMPRESSED")
  }
  push_some(args, b"CHUNK_SIZE", chunk_size.map(arg_int64))
  push_some(args, b"DUPLICATE_POLICY", duplicate_policy.map(arg_string))
  push_ts_labels(args, labels)
  expect_int64(self.command(args))
}

///|
/// `TS.DECRBY key value [TIMESTAMP ts] ...`: subtract `value` from the sample at
/// `timestamp`, returning the timestamp.
pub async fn Client::ts_decrby(
  self : Client,
  key : String,
  value : Double,
  timestamp? : Int64,
  retention? : Int64,
  uncompressed? : Bool,
  chunk_size? : Int64,
  duplicate_policy? : String,
  labels? : Array[(String, String)],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"TS.DECRBY", arg_string(key), arg_double(value)]
  push_some(args, b"TIMESTAMP", timestamp.map(arg_int64))
  push_some(args, b"RETENTION", retention.map(arg_int64))
  if uncompressed.unwrap_or(false) {
    args.push(b"ENCODING")
    args.push(b"UNCOMPRESSED")
  }
  push_some(args, b"CHUNK_SIZE", chunk_size.map(arg_int64))
  push_some(args, b"DUPLICATE_POLICY", duplicate_policy.map(arg_string))
  push_ts_labels(args, labels)
  expect_int64(self.command(args))
}

///|
/// `TS.DEL key fromTimestamp toTimestamp`: delete the samples in the range, returning how
/// many were removed.
pub async fn Client::ts_del(
  self : Client,
  key : String,
  from_ : String,
  to : String,
) -> Int64 raise RedisError {
  expect_int64(
    self.command([b"TS.DEL", arg_string(key), arg_string(from_), arg_string(to)]),
  )
}

///|
/// `TS.CREATERULE source destination AGGREGATION aggregator bucketDuration
/// [alignTimestamp]`: compact `source` into `destination` in buckets of `bucket` ms.
pub async fn Client::ts_createrule(
  self : Client,
  source : String,
  destination : String,
  aggregator : String,
  bucket : Int64,
  align_timestamp? : Int64,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [
    b"TS.CREATERULE",
    arg_string(source),
    arg_string(destination),
    b"AGGREGATION",
    arg_string(aggregator),
    arg_int64(bucket),
  ]
  push_some(args, b"", align_timestamp.map(arg_int64))
  status_ok(self.command(args))
}

///|
/// `TS.DELETERULE source destination`: stop compacting `source` into `destination`.
pub async fn Client::ts_deleterule(
  self : Client,
  source : String,
  destination : String,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"TS.DELETERULE", arg_string(source), arg_string(destination)]),
  )
}

///|
/// `TS.RANGE key fromTimestamp toTimestamp [options]`: the samples in the range, oldest
/// first.
pub async fn Client::ts_range(
  self : Client,
  key : String,
  from_ : TimeBound,
  to : TimeBound,
  options? : RangeOptions,
) -> Array[Sample] raise RedisError {
  let args : Array[Bytes] = [
    b"TS.RANGE",
    arg_string(key),
    arg_string(from_.text()),
    arg_string(to.text()),
  ]
  push_range_options(args, options.unwrap_or(range_default))
  decode_samples(self.command(args))
}

///|
/// `TS.REVRANGE key fromTimestamp toTimestamp [options]`: the samples in the range, newest
/// first. The bounds keep the order `TS.RANGE` uses; only the reply is reversed.
pub async fn Client::ts_revrange(
  self : Client,
  key : String,
  from_ : TimeBound,
  to : TimeBound,
  options? : RangeOptions,
) -> Array[Sample] raise RedisError {
  let args : Array[Bytes] = [
    b"TS.REVRANGE",
    arg_string(key),
    arg_string(from_.text()),
    arg_string(to.text()),
  ]
  push_range_options(args, options.unwrap_or(range_default))
  decode_samples(self.command(args))
}

///|
/// `TS.MRANGE fromTimestamp toTimestamp [options] FILTER filter...`: the samples of every
/// series whose labels match, oldest first.
pub async fn Client::ts_mrange(
  self : Client,
  from_ : TimeBound,
  to : TimeBound,
  filters : Array[String],
  options? : MultiRangeOptions,
) -> Array[Series] raise RedisError {
  let args : Array[Bytes] = [
    b"TS.MRANGE",
    arg_string(from_.text()),
    arg_string(to.text()),
  ]
  let options = options.unwrap_or(multi_range_default)
  push_multi_range_options(args, options)
  args.push(b"FILTER")
  for filter in filters {
    args.push(arg_string(filter))
  }
  decode_series(self.command(args))
}

///|
/// `TS.MREVRANGE fromTimestamp toTimestamp [options] FILTER filter...`: the same, newest
/// first. The bounds keep the order `TS.MRANGE` uses.
pub async fn Client::ts_mrevrange(
  self : Client,
  from_ : TimeBound,
  to : TimeBound,
  filters : Array[String],
  options? : MultiRangeOptions,
) -> Array[Series] raise RedisError {
  let args : Array[Bytes] = [
    b"TS.MREVRANGE",
    arg_string(from_.text()),
    arg_string(to.text()),
  ]
  let options = options.unwrap_or(multi_range_default)
  push_multi_range_options(args, options)
  args.push(b"FILTER")
  for filter in filters {
    args.push(arg_string(filter))
  }
  decode_series(self.command(args))
}

///|
/// Append what a multi-series range query takes before its `FILTER`.
fn push_multi_range_options(
  args : Array[Bytes],
  options : MultiRangeOptions,
) -> Unit {
  push_label_options(args, options.with_labels, options.select_labels)
  push_range_options(args, options.range)
  match (options.group_by, options.reduce) {
    (Some(label), Some(reducer)) => {
      args.push(b"GROUPBY")
      args.push(arg_string(label))
      args.push(b"REDUCE")
      args.push(arg_string(reducer))
    }
    _ => ()
  }
  if options.exclude_empty {
    args.push(b"EXCLUDEEMPTY")
  }
}

///|
/// `TS.MGET [options] FILTER filter...`: the latest sample of every series whose labels
/// match.
pub async fn Client::ts_mget(
  self : Client,
  filters : Array[String],
  options? : MultiGetOptions,
) -> Array[Series] raise RedisError {
  let options = options.unwrap_or(multi_get_default)
  let args : Array[Bytes] = [b"TS.MGET"]
  push_label_options(args, options.with_labels, options.select_labels)
  if options.latest {
    args.push(b"LATEST")
  }
  args.push(b"FILTER")
  for filter in filters {
    args.push(arg_string(filter))
  }
  decode_series_points(self.command(args))
}

///|
/// A multi-series range reply as `Series` entries.
fn decode_series(reply : @resp.RespValue) -> Array[Series] raise RedisError {
  decode_series_impl(reply, false)
}

///|
/// A multi-series point reply, whose samples list holds at most one sample.
fn decode_series_points(
  reply : @resp.RespValue,
) -> Array[Series] raise RedisError {
  decode_series_impl(reply, true)
}

///|
/// A multi-series reply as `Series` entries. RESP2 writes `[key, labels, samples]` per
/// series; RESP3 keys a map by name and writes `[labels, aggregators, samples]`. `single`
/// says whether the last element is one sample rather than a list of them.
fn decode_series_impl(
  reply : @resp.RespValue,
  single : Bool,
) -> Array[Series] raise RedisError {
  let out : Array[Series] = []
  match reply {
    @resp.RespMap(pairs) =>
      for (name, value) in pairs {
        let parts = expect_array(value)
        guard parts.length() >= 2 else { raise Protocol("unexpected series") }
        out.push({
          key: expect_text(name),
          labels: decode_labels(parts[0]),
          samples: decode_last_samples(parts[parts.length() - 1], single),
        })
      }
    other =>
      for item in expect_array(other) {
        let parts = expect_array(item)
        guard parts.length() >= 3 else { raise Protocol("unexpected series") }
        out.push({
          key: expect_text(parts[0]),
          labels: decode_labels(parts[1]),
          samples: decode_last_samples(parts[2], single),
        })
      }
  }
  out
}

///|
/// The samples at the end of a series: a list of them, or the one a point query returns.
fn decode_last_samples(
  reply : @resp.RespValue,
  single : Bool,
) -> Array[Sample] raise RedisError {
  if !single {
    return decode_samples(reply)
  }
  let items = expect_array(reply)
  if items.length() == 0 {
    []
  } else {
    [decode_sample(reply)]
  }
}

///|
/// `TS.GET key [LATEST]`: the newest sample, or `None` when the series is empty.
pub async fn Client::ts_get(
  self : Client,
  key : String,
  latest? : Bool,
) -> Sample? raise RedisError {
  let args : Array[Bytes] = [b"TS.GET", arg_string(key)]
  if latest.unwrap_or(false) {
    args.push(b"LATEST")
  }
  match self.command(args) {
    @resp.Null => None
    other => Some(decode_sample(other))
  }
}

///|
/// `TS.INFO key`: the series' size, settings, labels and compaction rules.
pub async fn Client::ts_info(
  self : Client,
  key : String,
) -> TsInfo raise RedisError {
  let reply = self.command([b"TS.INFO", arg_string(key)])
  let info = decode_info(reply)
  let mut labels : Array[(String, String)] = []
  let mut rules : Array[CompactionRule] = []
  // Labels and rules are nested lists, which the flat `Info` view drops, so they are read
  // from the reply itself.
  for (name, value) in field_pairs(reply) {
    match name {
      "labels" => labels = decode_labels(value)
      "rules" => rules = decode_rules(value)
      _ => ()
    }
  }
  {
    total_samples: info.int("totalSamples").unwrap_or(0),
    memory_usage: info.int("memoryUsage").unwrap_or(0),
    first_timestamp: info.int("firstTimestamp").unwrap_or(0),
    last_timestamp: info.int("lastTimestamp").unwrap_or(0),
    retention_millis: info.int("retentionTime").unwrap_or(0),
    chunk_count: info.int("chunkCount").unwrap_or(0),
    chunk_size: info.int("chunkSize").unwrap_or(0),
    chunk_type: info.text("chunkType").unwrap_or(""),
    duplicate_policy: info.text("duplicatePolicy").unwrap_or(""),
    labels,
    source_key: info.text("sourceKey"),
    rules,
    ignore_max_time_diff: info.int("ignoreMaxTimeDiff").unwrap_or(0),
    ignore_max_val_diff: info.double("ignoreMaxValDiff").unwrap_or(0.0),
  }
}

///|
/// The compaction rules of a series: a list of `[destination, bucket, aggregator, align]`
/// under RESP2, a map keyed by destination under RESP3.
fn decode_rules(
  reply : @resp.RespValue,
) -> Array[CompactionRule] raise RedisError {
  let rules : Array[CompactionRule] = []
  match reply {
    @resp.RespMap(pairs) =>
      for (destination, body) in pairs {
        let parts = expect_array(body)
        guard parts.length() >= 2 else {
          raise Protocol("unexpected compaction rule body")
        }
        rules.push({
          destination: expect_text(destination),
          bucket: expect_int64(parts[0]),
          aggregator: expect_text(parts[1]),
        })
      }
    @resp.Array(items) =>
      for item in items {
        let parts = expect_array(item)
        guard parts.length() >= 3 else {
          raise Protocol("unexpected compaction rule")
        }
        rules.push({
          destination: expect_text(parts[0]),
          bucket: expect_int64(parts[1]),
          aggregator: expect_text(parts[2]),
        })
      }
    @resp.Null => ()
    other =>
      raise Protocol("expected compaction rules, got " + @resp.resp_kind(other))
  }
  rules
}

///|
/// `TS.QUERYINDEX filter...`: the keys whose labels match every filter.
pub async fn Client::ts_queryindex(
  self : Client,
  filters : Array[String],
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"TS.QUERYINDEX"]
  for filter in filters {
    args.push(arg_string(filter))
  }
  expect_text_list(self.command(args))
}

///|
/// `TS.QUERYLABELS [FILTER filter...]`: every label name in use.
pub async fn Client::ts_querylabels(
  self : Client,
  filters? : Array[String],
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"TS.QUERYLABELS", b"LABELS"]
  match filters {
    Some(filters) =>
      if filters.length() > 0 {
        args.push(b"FILTER")
        for filter in filters {
          args.push(arg_string(filter))
        }
      }
    None => ()
  }
  expect_text_list(self.command(args))
}

///|
/// `TS.QUERYLABELS VALUES label [FILTER filter...]`: every value of one label in use.
pub async fn Client::ts_querylabel_values(
  self : Client,
  label : String,
  filters? : Array[String],
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"TS.QUERYLABELS", b"VALUES", arg_string(label)]
  match filters {
    Some(filters) =>
      if filters.length() > 0 {
        args.push(b"FILTER")
        for filter in filters {
          args.push(arg_string(filter))
        }
      }
    None => ()
  }
  expect_text_list(self.command(args))
}

///|
/// `TS.READ key timestamp [BLOCK ms count] [MAX_COUNT n]`: up to `max_count` samples from
/// `timestamp` on, waiting for at least `block`'s count when it is given.
pub async fn Client::ts_read(
  self : Client,
  key : String,
  timestamp : Int64,
  block? : (Int64, Int64),
  max_count? : Int64,
) -> Array[Sample] raise RedisError {
  let args : Array[Bytes] = [b"TS.READ", arg_string(key), arg_int64(timestamp)]
  match block {
    Some((milliseconds, min_count)) => {
      args.push(b"BLOCK")
      args.push(arg_int64(milliseconds))
      args.push(arg_int64(min_count))
    }
    None => ()
  }
  push_some(args, b"MAX_COUNT", max_count.map(arg_int64))
  decode_samples(self.command(args))
}

///|
/// `TS.NRANGE numkeys key... fromTimestamp toTimestamp [options]`: the samples of several
/// series pivoted by timestamp, one value column per key in the order the keys are given.
pub async fn Client::ts_nrange(
  self : Client,
  keys : Array[String],
  from_ : TimeBound,
  to : TimeBound,
  options? : RangeOptions,
) -> Array[PivotRow] raise RedisError {
  let args : Array[Bytes] = [b"TS.NRANGE", arg_int(keys.length())]
  for key in keys {
    args.push(arg_string(key))
  }
  args.push(arg_string(from_.text()))
  args.push(arg_string(to.text()))
  push_range_options(args, options.unwrap_or(range_default))
  decode_pivot(self.command(args))
}

///|
/// `TS.NREVRANGE numkeys key... fromTimestamp toTimestamp [options]`: the same, newest
/// first. The bounds keep the order `TS.NRANGE` uses.
pub async fn Client::ts_nrevrange(
  self : Client,
  keys : Array[String],
  from_ : TimeBound,
  to : TimeBound,
  options? : RangeOptions,
) -> Array[PivotRow] raise RedisError {
  let args : Array[Bytes] = [b"TS.NREVRANGE", arg_int(keys.length())]
  for key in keys {
    args.push(arg_string(key))
  }
  args.push(arg_string(from_.text()))
  args.push(arg_string(to.text()))
  push_range_options(args, options.unwrap_or(range_default))
  decode_pivot(self.command(args))
}

///|
/// A pivoted reply: `[timestamp, [value per key]]`, with `NaN` where a key has no sample.
fn decode_pivot(reply : @resp.RespValue) -> Array[PivotRow] raise RedisError {
  let out : Array[PivotRow] = []
  for item in expect_array(reply) {
    let parts = expect_array(item)
    guard parts.length() >= 2 else { raise Protocol("unexpected pivoted row") }
    let values : Array[Double?] = []
    for value in expect_array(parts[1]) {
      let sample = numeric_value(value)
      values.push(if sample.is_nan() { None } else { Some(sample) })
    }
    out.push({ timestamp: expect_int64(parts[0]), values, })
  }
  out
}
