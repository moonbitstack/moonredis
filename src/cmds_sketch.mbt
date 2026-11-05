// The three counting sketch modules: a count-min sketch counts how often each item was
// seen in bounded space, a top-k sketch keeps the heaviest items, and a t-digest estimates
// quantiles from a compressed sample. All three answer with numbers written as text under
// RESP2 and as doubles or integers under RESP3, and all three have an `INFO` reply.
// https://redis.io/docs/latest/commands/?group=cms
// https://redis.io/docs/latest/commands/?group=topk
// https://redis.io/docs/latest/commands/?group=tdigest

///|
/// `CMS.INITBYDIM key width depth`: create a count-min sketch of `width` counters per row
/// and `depth` rows. The error is about `1/width` of the total count, the failure
/// probability about `1/2^depth`.
pub async fn Client::cms_initbydim(
  self : Client,
  key : String,
  width : Int64,
  depth : Int64,
) -> Unit raise RedisError {
  status_ok(
    self.command([
      b"CMS.INITBYDIM",
      arg_string(key),
      arg_int64(width),
      arg_int64(depth),
    ]),
  )
}

///|
/// `CMS.INITBYPROB key error probability`: create a count-min sketch from the error it may
/// make relative to the total count, and the probability of exceeding it.
pub async fn Client::cms_initbyprob(
  self : Client,
  key : String,
  error_rate : Double,
  probability : Double,
) -> Unit raise RedisError {
  status_ok(
    self.command([
      b"CMS.INITBYPROB",
      arg_string(key),
      arg_double(error_rate),
      arg_double(probability),
    ]),
  )
}

///|
/// `CMS.INCRBY key item increment [item increment ...]`: add to the counts, returning the
/// new count of each item.
pub async fn Client::cms_incrby(
  self : Client,
  key : String,
  items : Array[(String, Int64)],
) -> Array[Int64] raise RedisError {
  let args : Array[Bytes] = [b"CMS.INCRBY", arg_string(key)]
  for (item, increment) in items {
    args.push(arg_string(item))
    args.push(arg_int64(increment))
  }
  expect_array(self.command(args)).map(expect_int64)
}

///|
/// `CMS.QUERY key item [item ...]`: the estimated count of each item.
pub async fn Client::cms_query(
  self : Client,
  key : String,
  items : Array[String],
) -> Array[Int64] raise RedisError {
  let args : Array[Bytes] = [b"CMS.QUERY", arg_string(key)]
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_int64)
}

///|
/// `CMS.MERGE destination numKeys source... [WEIGHTS w...]`: add several sketches into
/// `destination`, each scaled by its weight.
pub async fn Client::cms_merge(
  self : Client,
  destination : String,
  sources : Array[String],
  weights? : Array[Int64],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [
    b"CMS.MERGE",
    arg_string(destination),
    arg_int(sources.length()),
  ]
  for source in sources {
    args.push(arg_string(source))
  }
  match weights {
    Some(values) =>
      if values.length() > 0 {
        args.push(b"WEIGHTS")
        for weight in values {
          args.push(arg_int64(weight))
        }
      }
    None => ()
  }
  status_ok(self.command(args))
}

///|
/// `CMS.INFO key`: width, depth and total count.
pub async fn Client::cms_info(
  self : Client,
  key : String,
) -> Info raise RedisError {
  decode_info(self.command([b"CMS.INFO", arg_string(key)]))
}

///|
/// `TOPK.RESERVE key topk [width depth decay]`: create a sketch that keeps the `topk`
/// heaviest items.
pub async fn Client::topk_reserve(
  self : Client,
  key : String,
  topk : Int64,
  width? : Int64,
  depth? : Int64,
  decay? : Double,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"TOPK.RESERVE", arg_string(key), arg_int64(topk)]
  match (width, depth, decay) {
    (Some(w), Some(d), Some(value)) => {
      args.push(arg_int64(w))
      args.push(arg_int64(d))
      args.push(arg_double(value))
    }
    _ => ()
  }
  status_ok(self.command(args))
}

///|
/// `TOPK.ADD key item [item ...]`: count each item, returning the item it evicted from the
/// list at that position, or `None` when the list did not change.
pub async fn Client::topk_add(
  self : Client,
  key : String,
  items : Array[String],
) -> Array[String?] raise RedisError {
  let args : Array[Bytes] = [b"TOPK.ADD", arg_string(key)]
  for item in items {
    args.push(arg_string(item))
  }
  let out : Array[String?] = []
  for item in expect_array(self.command(args)) {
    match item {
      @resp.Null => out.push(None)
      other => out.push(Some(expect_text(other)))
    }
  }
  out
}

///|
/// `TOPK.INCRBY key item increment [item increment ...]`: add to the counts, returning the
/// evicted item per entry.
pub async fn Client::topk_incrby(
  self : Client,
  key : String,
  items : Array[(String, Int64)],
) -> Array[String?] raise RedisError {
  let args : Array[Bytes] = [b"TOPK.INCRBY", arg_string(key)]
  for (item, increment) in items {
    args.push(arg_string(item))
    args.push(arg_int64(increment))
  }
  let out : Array[String?] = []
  for item in expect_array(self.command(args)) {
    match item {
      @resp.Null => out.push(None)
      other => out.push(Some(expect_text(other)))
    }
  }
  out
}

///|
/// `TOPK.QUERY key item [item ...]`: whether each item is in the top-k list.
pub async fn Client::topk_query(
  self : Client,
  key : String,
  items : Array[String],
) -> Array[Bool] raise RedisError {
  let args : Array[Bytes] = [b"TOPK.QUERY", arg_string(key)]
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_bool)
}

///|
/// `TOPK.COUNT key item [item ...]`: the estimated count of each item.
pub async fn Client::topk_count(
  self : Client,
  key : String,
  items : Array[String],
) -> Array[Int64] raise RedisError {
  let args : Array[Bytes] = [b"TOPK.COUNT", arg_string(key)]
  for item in items {
    args.push(arg_string(item))
  }
  expect_array(self.command(args)).map(expect_int64)
}

///|
/// `TOPK.LIST key`: the items in the top-k list, heaviest first.
pub async fn Client::topk_list(
  self : Client,
  key : String,
) -> Array[String] raise RedisError {
  expect_text_list(self.command([b"TOPK.LIST", arg_string(key)]))
}

///|
/// `TOPK.LIST key WITHCOUNT`: the items in the top-k list with their counts.
pub async fn Client::topk_list_with_count(
  self : Client,
  key : String,
) -> Array[(String, Int64)] raise RedisError {
  let flat = expect_array(
    self.command([b"TOPK.LIST", arg_string(key), b"WITHCOUNT"]),
  )
  let out : Array[(String, Int64)] = []
  let mut at = 0
  while at + 1 < flat.length() {
    out.push((expect_text(flat[at]), expect_int64(flat[at + 1])))
    at += 2
  }
  out
}

///|
/// `TOPK.INFO key`: the sketch's size and decay.
pub async fn Client::topk_info(
  self : Client,
  key : String,
) -> Info raise RedisError {
  decode_info(self.command([b"TOPK.INFO", arg_string(key)]))
}

///|
/// `TDIGEST.CREATE key [COMPRESSION compression]`: create a t-digest. A higher compression
/// keeps more centroids and estimates the tails more precisely.
pub async fn Client::tdigest_create(
  self : Client,
  key : String,
  compression? : Int64,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"TDIGEST.CREATE", arg_string(key)]
  push_some(args, b"COMPRESSION", compression.map(arg_int64))
  status_ok(self.command(args))
}

///|
/// `TDIGEST.RESET key`: empty a t-digest without dropping the key.
pub async fn Client::tdigest_reset(
  self : Client,
  key : String,
) -> Unit raise RedisError {
  status_ok(self.command([b"TDIGEST.RESET", arg_string(key)]))
}

///|
/// `TDIGEST.ADD key value [value ...]`: add observations.
pub async fn Client::tdigest_add(
  self : Client,
  key : String,
  values : Array[Double],
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"TDIGEST.ADD", arg_string(key)]
  for value in values {
    args.push(arg_double(value))
  }
  status_ok(self.command(args))
}

///|
/// `TDIGEST.MERGE destination numKeys source... [COMPRESSION c] [OVERRIDE]`: merge
/// sketches into one; `overwrite` replaces the destination's contents instead of adding.
pub async fn Client::tdigest_merge(
  self : Client,
  destination : String,
  sources : Array[String],
  compression? : Int64,
  overwrite? : Bool,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [
    b"TDIGEST.MERGE",
    arg_string(destination),
    arg_int(sources.length()),
  ]
  for source in sources {
    args.push(arg_string(source))
  }
  push_some(args, b"COMPRESSION", compression.map(arg_int64))
  if overwrite.unwrap_or(false) {
    args.push(b"OVERRIDE")
  }
  status_ok(self.command(args))
}

///|
/// `TDIGEST.MIN key`: the smallest observation, or `NaN` when the sketch is empty.
pub async fn Client::tdigest_min(
  self : Client,
  key : String,
) -> Double raise RedisError {
  numeric_value(self.command([b"TDIGEST.MIN", arg_string(key)]))
}

///|
/// `TDIGEST.MAX key`: the largest observation, or `NaN` when the sketch is empty.
pub async fn Client::tdigest_max(
  self : Client,
  key : String,
) -> Double raise RedisError {
  numeric_value(self.command([b"TDIGEST.MAX", arg_string(key)]))
}

///|
/// `TDIGEST.QUANTILE key quantile [quantile ...]`: the value at each quantile, 0 to 1.
pub async fn Client::tdigest_quantile(
  self : Client,
  key : String,
  quantiles : Array[Double],
) -> Array[Double] raise RedisError {
  let args : Array[Bytes] = [b"TDIGEST.QUANTILE", arg_string(key)]
  for quantile in quantiles {
    args.push(arg_double(quantile))
  }
  expect_array(self.command(args)).map(numeric_value)
}

///|
/// `TDIGEST.CDF key value [value ...]`: the fraction of observations at or below each
/// value.
pub async fn Client::tdigest_cdf(
  self : Client,
  key : String,
  values : Array[Double],
) -> Array[Double] raise RedisError {
  let args : Array[Bytes] = [b"TDIGEST.CDF", arg_string(key)]
  for value in values {
    args.push(arg_double(value))
  }
  expect_array(self.command(args)).map(numeric_value)
}

///|
/// `TDIGEST.RANK key value [value ...]`: how many observations are below each value.
pub async fn Client::tdigest_rank(
  self : Client,
  key : String,
  values : Array[Double],
) -> Array[Int64] raise RedisError {
  let args : Array[Bytes] = [b"TDIGEST.RANK", arg_string(key)]
  for value in values {
    args.push(arg_double(value))
  }
  expect_array(self.command(args)).map(expect_int64)
}

///|
/// `TDIGEST.REVRANK key value [value ...]`: how many observations are above each value.
pub async fn Client::tdigest_revrank(
  self : Client,
  key : String,
  values : Array[Double],
) -> Array[Int64] raise RedisError {
  let args : Array[Bytes] = [b"TDIGEST.REVRANK", arg_string(key)]
  for value in values {
    args.push(arg_double(value))
  }
  expect_array(self.command(args)).map(expect_int64)
}

///|
/// `TDIGEST.BYRANK key rank [rank ...]`: the value at each rank.
pub async fn Client::tdigest_byrank(
  self : Client,
  key : String,
  ranks : Array[Int64],
) -> Array[Double] raise RedisError {
  let args : Array[Bytes] = [b"TDIGEST.BYRANK", arg_string(key)]
  for rank in ranks {
    args.push(arg_int64(rank))
  }
  expect_array(self.command(args)).map(numeric_value)
}

///|
/// `TDIGEST.BYREVRANK key rank [rank ...]`: the value at each reverse rank.
pub async fn Client::tdigest_byrevrank(
  self : Client,
  key : String,
  ranks : Array[Int64],
) -> Array[Double] raise RedisError {
  let args : Array[Bytes] = [b"TDIGEST.BYREVRANK", arg_string(key)]
  for rank in ranks {
    args.push(arg_int64(rank))
  }
  expect_array(self.command(args)).map(numeric_value)
}

///|
/// `TDIGEST.TRIMMED_MEAN key low_cut high_cut`: the mean after dropping the observations
/// below `low_cut` and above `high_cut`, both quantiles from 0 to 1.
pub async fn Client::tdigest_trimmed_mean(
  self : Client,
  key : String,
  low_cut : Double,
  high_cut : Double,
) -> Double raise RedisError {
  numeric_value(
    self.command([
      b"TDIGEST.TRIMMED_MEAN",
      arg_string(key),
      arg_double(low_cut),
      arg_double(high_cut),
    ]),
  )
}

///|
/// `TDIGEST.INFO key`: compression, capacity, and how many observations were merged.
pub async fn Client::tdigest_info(
  self : Client,
  key : String,
) -> Info raise RedisError {
  decode_info(self.command([b"TDIGEST.INFO", arg_string(key)]))
}
