// The search commands. An index names a set of documents — hash keys or JSON documents
// under a prefix — and a schema says which fields are searchable, sortable, or a vector.
// `FT.SEARCH` answers with documents, `FT.AGGREGATE` with computed rows, and `FT.HYBRID`
// fuses a text search and a vector search into one ranking.
// https://redis.io/docs/latest/commands/?group=search

///|
/// One value in a search or aggregate reply: the fields of a document as text, and the
/// computed values of an aggregation as the type the server sent.
#derive(Eq, Debug)
pub(all) enum FieldValue {
  Text(String)
  Integer(Int64)
  Number(Double)
  Null
}

///|
pub extend FieldValue with Debug::{to_repr}

///|
pub extend FieldValue with Eq::{not_equal, equal}

///|
/// A reply value as a `FieldValue`.
pub fn field_value(reply : @resp.RespValue) -> FieldValue {
  match reply {
    @resp.Integer(n) => Integer(n)
    @resp.Double(d) => Number(d)
    @resp.SimpleString(s) => Text(s)
    @resp.BulkString(b) | @resp.VerbatimString(_, b) =>
      Text(@utf8.decode_lossy(b[:]))
    _ => Null
  }
}

///|
/// A value as text, for the callers that only ever see text.
pub fn FieldValue::text(self : FieldValue) -> String? {
  match self {
    Text(s) => Some(s)
    Integer(n) => Some(n.to_string())
    Number(d) => Some(d.to_string())
    Null => None
  }
}

///|
/// A value as an integer, when it holds one.
pub fn FieldValue::int(self : FieldValue) -> Int64? {
  match self {
    Integer(n) => Some(n)
    Number(d) => Some(d.to_int64())
    Text(s) => {
      let n = @string.parse_int64(s) catch { _ => return None }
      Some(n)
    }
    Null => None
  }
}

///|
/// A value as a double, when it holds one.
pub fn FieldValue::double(self : FieldValue) -> Double? {
  match self {
    Integer(n) => Some(n.to_double())
    Number(d) => Some(d)
    Text(s) => {
      let d = @string.parse_double(s) catch { _ => return None }
      Some(d)
    }
    Null => None
  }
}

///|
/// One document a query returned: its key, the fields asked for, and the score, payload or
/// sort key when the query asked for them.
pub(all) struct SearchHit {
  id : String
  fields : Array[(String, @resp.RespValue)]
  score : Double?
  payload : Bytes?
  sort_key : String?
}

///|
/// The field `name` of a hit as text, or `None` when the query did not return it.
pub fn SearchHit::field(self : SearchHit, name : String) -> String? {
  for (field, value) in self.fields {
    if field == name {
      return field_value(value).text()
    }
  }
  None
}

///|
/// What `FT.SEARCH` and `FT.HYBRID` answer: how many documents matched, the ones this page
/// returned, and any warning the query raised.
pub(all) struct SearchResult {
  /// The total number of matches, before `LIMIT`.
  total : Int64
  hits : Array[SearchHit]
  warnings : Array[String]
}

///|
/// What `FT.AGGREGATE` and `FT.CURSOR READ` answer: the rows, and the cursor id to read
/// more with.
pub(all) struct AggregateResult {
  total : Int64
  /// Each row is the field/value pairs in the order the server produced them.
  rows : Array[Array[(String, FieldValue)]]
  /// The id to read more with `ft_cursor_read`, or `None` when the reply came whole.
  cursor : Int64?
}

///|
/// The value of `name` in an aggregate row.
pub fn aggregate_field(
  row : Array[(String, FieldValue)],
  name : String,
) -> FieldValue? {
  for (field, value) in row {
    if field == name {
      return Some(value)
    }
  }
  None
}

///|
/// A field to sort by and the direction.
pub(all) struct SortKey {
  field : String
  /// True for `ASC`, false for `DESC`.
  ascending : Bool
}

///|
/// Which fragments of each field `SUMMARIZE` returns, and with what separator.
pub(all) struct Summarize {
  fields : Array[String]
  /// The number of fragments per field; the server picks 3 by default.
  fragments : Int64?
  /// The length of each fragment in words.
  length : Int64?
  separator : String?
}

///|
/// A numeric range a document's field must fall in.
pub(all) struct NumericFilter {
  field : String
  /// The lower bound as text, so `-inf`, `+inf` and the exclusive `(1` can be written.
  min : String
  /// The upper bound as text.
  max : String
}

///|
/// A distance a document's geo field must fall within.
pub(all) struct GeoFilter {
  field : String
  longitude : Double
  latitude : Double
  radius : Double
  /// `m`, `km`, `mi` or `ft`.
  unit : String
}

///|
/// The options `FT.SEARCH` takes besides the index and the query.
pub(all) struct SearchOptions {
  /// Return only the ids.
  nocontent : Bool
  /// Do not stem the query terms.
  verbatim : Bool
  with_scores : Bool
  with_payloads : Bool
  with_sort_keys : Bool
  /// The fields to return; empty returns them all.
  return_fields : Array[String]
  /// The fields to wrap matches in `<b>` tags in; empty leaves them alone.
  highlight : Array[String]
  summarize : Summarize?
  sort_by : SortKey?
  /// How many matches to skip; sent only with `limit`.
  offset : Int64
  /// How many matches to return; 0 leaves the server's default of 10.
  limit : Int64
  /// The query dialect, 1 to 4; `None` leaves the server default.
  dialect : Int32?
  /// `PARAMS` values, by the name the query refers to. A vector is raw bytes.
  params : Array[(String, Bytes)]
  timeout : Int64?
  /// Restrict the search to these keys.
  in_keys : Array[String]
  /// Restrict the search to these fields.
  in_fields : Array[String]
  filter : NumericFilter?
  geo_filter : GeoFilter?
  /// `TFIDF`, `BM25STD`, `DISMAX` or a scorer a module registered.
  scorer : String?
  /// How far apart the query terms may be, in words.
  slop : Int64?
  language : String?
  /// Return the score breakdown alongside each hit.
  explain_score : Bool
}

///|
/// `FT.SEARCH`'s options at their documented defaults.
pub let search_default : SearchOptions = SearchOptions::{
  nocontent: false,
  verbatim: false,
  with_scores: false,
  with_payloads: false,
  with_sort_keys: false,
  return_fields: [],
  highlight: [],
  summarize: None,
  sort_by: None,
  offset: 0,
  limit: 0,
  dialect: None,
  params: [],
  timeout: None,
  in_keys: [],
  in_fields: [],
  filter: None,
  geo_filter: None,
  scorer: None,
  slop: None,
  language: None,
  explain_score: false,
}

///|
/// One `REDUCE` of an aggregation: a function, its arguments, and the name its result
/// takes.
pub(all) struct Reducer {
  /// `COUNT`, `COUNT_DISTINCT`, `SUM`, `AVG`, `MIN`, `MAX`, `QUANTILE`, `STDDEV`,
  /// `TOLIST`, `FIRST_VALUE` or `RANDOM_SAMPLE`.
  function : String
  /// The arguments as the query language writes them: `0` for `COUNT`, `@price` for `SUM`,
  /// `2 @price 0.5` for `QUANTILE`.
  args : Array[String]
  as_ : String?
}

///|
/// The options `FT.AGGREGATE` takes besides the index and the query.
pub(all) struct AggregateOptions {
  verbatim : Bool
  /// The fields to carry into the result; `["*"]` loads all of them.
  load : Array[String]
  group_by : Array[String]
  reducers : Array[Reducer]
  /// `APPLY` steps: an expression and the name its result takes.
  apply : Array[(String, String)]
  sort_by : Array[SortKey]
  offset : Int64
  /// 0 leaves the server's default of 10.
  limit : Int64
  /// A post-aggregation filter expression.
  filter : String?
  params : Array[(String, Bytes)]
  dialect : Int32?
  timeout : Int64?
  /// Ask for a cursor holding this many rows per read.
  cursor_count : Int64?
  /// Close an idle cursor after this many milliseconds.
  max_idle : Int64?
}

///|
/// `FT.AGGREGATE`'s options at their documented defaults.
pub let aggregate_default : AggregateOptions = AggregateOptions::{
  verbatim: false,
  load: [],
  group_by: [],
  reducers: [],
  apply: [],
  sort_by: [],
  offset: 0,
  limit: 0,
  filter: None,
  params: [],
  dialect: None,
  timeout: None,
  cursor_count: None,
  max_idle: None,
}

///|
/// What an index is built over.
#derive(Eq, Debug)
pub(all) enum IndexKind {
  Hash
  Json
}

///|
pub extend IndexKind with Debug::{to_repr}

///|
pub extend IndexKind with Eq::{not_equal, equal}

///|
/// The type of one schema field.
#derive(Eq, Debug)
pub(all) enum SchemaKind {
  Text
  Tag
  Numeric
  Geo
  Vector
}

///|
pub extend SchemaKind with Debug::{to_repr}

///|
pub extend SchemaKind with Eq::{not_equal, equal}

///|
/// How a vector field is indexed: `Flat` scans every vector, `Hnsw` builds a navigable
/// small-world graph over them.
#derive(Eq, Debug)
pub(all) enum VectorAlgorithm {
  Flat
  Hnsw
}

///|
pub extend VectorAlgorithm with Debug::{to_repr}

///|
pub extend VectorAlgorithm with Eq::{not_equal, equal}

///|
/// The parameters a `VECTOR` field takes.
pub(all) struct VectorSpec {
  algorithm : VectorAlgorithm
  /// How many dimensions each vector has.
  dim : Int32
  /// `FLOAT32`, `FLOAT64`, `BFLOAT16`, `FLOAT16`, `INT8` or `UINT8`.
  element : String
  /// `L2`, `IP` or `COSINE`.
  distance : String
  initial_cap : Int64?
  block_size : Int64?
  /// `HNSW` only: edges per node.
  m : Int64?
  /// `HNSW` only: the candidate list size during construction.
  ef_construction : Int64?
  /// `HNSW` only: the candidate list size during a query.
  ef_runtime : Int64?
  /// `HNSW` only: the range query precision.
  epsilon : Double?
}

///|
/// A flat (brute force) vector index over `dim` dimensions.
pub fn VectorSpec::flat(
  dim : Int32,
  element? : String,
  distance? : String,
  initial_cap? : Int64,
  block_size? : Int64,
) -> VectorSpec {
  {
    algorithm: Flat,
    dim,
    element: element.unwrap_or("FLOAT32"),
    distance: distance.unwrap_or("L2"),
    initial_cap,
    block_size,
    m: None,
    ef_construction: None,
    ef_runtime: None,
    epsilon: None,
  }
}

///|
/// An HNSW vector index over `dim` dimensions.
pub fn VectorSpec::hnsw(
  dim : Int32,
  element? : String,
  distance? : String,
  initial_cap? : Int64,
  m? : Int64,
  ef_construction? : Int64,
  ef_runtime? : Int64,
  epsilon? : Double,
) -> VectorSpec {
  {
    algorithm: Hnsw,
    dim,
    element: element.unwrap_or("FLOAT32"),
    distance: distance.unwrap_or("L2"),
    initial_cap,
    block_size: None,
    m,
    ef_construction,
    ef_runtime,
    epsilon,
  }
}

///|
/// One field of a schema: the document field it reads, the name queries use, and the
/// options its type takes.
pub(all) struct SchemaField {
  /// The hash field, or the JSONPath for a JSON index.
  name : String
  kind : SchemaKind
  /// The name the field takes in queries, when it differs from `name`.
  as_ : String?
  sortable : Bool
  /// Sort by the raw value rather than a normalized one.
  unf : Bool
  noindex : Bool
  /// `TEXT` only: the term weight.
  weight : Double?
  /// `TAG` only: the separator between tags, `,` by default.
  separator : String?
  /// `TAG` only: match tags case-sensitively.
  case_sensitive : Bool
  /// `TEXT` only: the phonetic matcher, `dm:en` or `dm:fr`.
  phonetic : String?
  /// `TEXT` only: index the term without stemming it.
  no_stem : Bool
  with_suffix_trie : Bool
  index_empty : Bool
  index_missing : Bool
  /// `VECTOR` only: the algorithm and its parameters.
  vector : VectorSpec?
}

///|
/// A field of the given kind with every option off.
fn schema_field(name : String, kind : SchemaKind, as_ : String?) -> SchemaField {
  {
    name,
    kind,
    as_,
    sortable: false,
    unf: false,
    noindex: false,
    weight: None,
    separator: None,
    case_sensitive: false,
    phonetic: None,
    no_stem: false,
    with_suffix_trie: false,
    index_empty: false,
    index_missing: false,
    vector: None,
  }
}

///|
/// A `TEXT` field.
pub fn SchemaField::text(
  name : String,
  as_? : String,
  sortable? : Bool,
  unf? : Bool,
  noindex? : Bool,
  weight? : Double,
  phonetic? : String,
  no_stem? : Bool,
  with_suffix_trie? : Bool,
  index_empty? : Bool,
  index_missing? : Bool,
) -> SchemaField {
  {
    ..schema_field(name, Text, as_),
    sortable: sortable.unwrap_or(false),
    unf: unf.unwrap_or(false),
    noindex: noindex.unwrap_or(false),
    weight,
    phonetic,
    no_stem: no_stem.unwrap_or(false),
    with_suffix_trie: with_suffix_trie.unwrap_or(false),
    index_empty: index_empty.unwrap_or(false),
    index_missing: index_missing.unwrap_or(false),
  }
}

///|
/// A `TAG` field.
pub fn SchemaField::tag(
  name : String,
  as_? : String,
  separator? : String,
  case_sensitive? : Bool,
  sortable? : Bool,
  unf? : Bool,
  noindex? : Bool,
  with_suffix_trie? : Bool,
  index_empty? : Bool,
  index_missing? : Bool,
) -> SchemaField {
  {
    ..schema_field(name, Tag, as_),
    separator,
    case_sensitive: case_sensitive.unwrap_or(false),
    sortable: sortable.unwrap_or(false),
    unf: unf.unwrap_or(false),
    noindex: noindex.unwrap_or(false),
    with_suffix_trie: with_suffix_trie.unwrap_or(false),
    index_empty: index_empty.unwrap_or(false),
    index_missing: index_missing.unwrap_or(false),
  }
}

///|
/// A `NUMERIC` field.
pub fn SchemaField::numeric(
  name : String,
  as_? : String,
  sortable? : Bool,
  unf? : Bool,
  noindex? : Bool,
  index_empty? : Bool,
  index_missing? : Bool,
) -> SchemaField {
  {
    ..schema_field(name, Numeric, as_),
    sortable: sortable.unwrap_or(false),
    unf: unf.unwrap_or(false),
    noindex: noindex.unwrap_or(false),
    index_empty: index_empty.unwrap_or(false),
    index_missing: index_missing.unwrap_or(false),
  }
}

///|
/// A `GEO` field.
pub fn SchemaField::geo(
  name : String,
  as_? : String,
  sortable? : Bool,
  unf? : Bool,
  noindex? : Bool,
  index_empty? : Bool,
  index_missing? : Bool,
) -> SchemaField {
  {
    ..schema_field(name, Geo, as_),
    sortable: sortable.unwrap_or(false),
    unf: unf.unwrap_or(false),
    noindex: noindex.unwrap_or(false),
    index_empty: index_empty.unwrap_or(false),
    index_missing: index_missing.unwrap_or(false),
  }
}

///|
/// A `VECTOR` field.
pub fn SchemaField::vector(
  name : String,
  spec : VectorSpec,
  as_? : String,
  sortable? : Bool,
  noindex? : Bool,
) -> SchemaField {
  {
    ..schema_field(name, Vector, as_),
    sortable: sortable.unwrap_or(false),
    noindex: noindex.unwrap_or(false),
    vector: Some(spec),
  }
}

///|
/// What `FT.CREATE` builds: the documents it reads and the fields it indexes.
pub(all) struct Schema {
  /// Hash keys or JSON documents.
  on : IndexKind
  /// The key prefixes the index reads; empty indexes every key.
  prefixes : Array[String]
  /// A filter expression a document must match to be indexed.
  filter : String?
  language : String?
  language_field : String?
  score : Double?
  score_field : String?
  /// Build a temporary index that expires after this many seconds.
  temporary : Int64?
  /// The stop words; `None` leaves the server's list, an empty array disables them.
  stopwords : Array[String]?
  fields : Array[SchemaField]
}

///|
/// A schema over `fields` with the default index options.
pub fn Schema::new(fields : Array[SchemaField]) -> Schema {
  {
    on: Hash,
    prefixes: [],
    filter: None,
    language: None,
    language_field: None,
    score: None,
    score_field: None,
    temporary: None,
    stopwords: None,
    fields,
  }
}

///|
/// Append the keywords that describe one field.
fn encode_schema_field(args : Array[Bytes], field : SchemaField) -> Unit {
  args.push(arg_string(field.name))
  push_some(args, b"AS", field.as_.map(arg_string))
  match field.kind {
    Text => {
      args.push(b"TEXT")
      push_some(args, b"WEIGHT", field.weight.map(arg_double))
      if field.no_stem {
        args.push(b"NOSTEM")
      }
      push_some(args, b"PHONETIC", field.phonetic.map(arg_string))
    }
    Tag => {
      args.push(b"TAG")
      push_some(args, b"SEPARATOR", field.separator.map(arg_string))
      if field.case_sensitive {
        args.push(b"CASESENSITIVE")
      }
    }
    Numeric => args.push(b"NUMERIC")
    Geo => args.push(b"GEO")
    Vector => {
      args.push(b"VECTOR")
      match field.vector {
        Some(spec) => encode_vector_spec(args, spec)
        None => ()
      }
    }
  }
  if field.with_suffix_trie {
    args.push(b"WITHSUFFIXTRIE")
  }
  if field.index_empty {
    args.push(b"INDEXEMPTY")
  }
  if field.index_missing {
    args.push(b"INDEXMISSING")
  }
  if field.sortable {
    args.push(b"SORTABLE")
    if field.unf {
      args.push(b"UNF")
    }
  }
  if field.noindex {
    args.push(b"NOINDEX")
  }
}

///|
/// Append `FLAT|HNSW <count> TYPE ... DIM ... DISTANCE_METRIC ...`, the count being the
/// number of tokens that follow the algorithm.
fn encode_vector_spec(args : Array[Bytes], spec : VectorSpec) -> Unit {
  let pairs : Array[Bytes] = [
    b"TYPE",
    arg_string(spec.element),
    b"DIM",
    arg_int(spec.dim),
    b"DISTANCE_METRIC",
    arg_string(spec.distance),
  ]
  match spec.initial_cap {
    Some(n) => {
      pairs.push(b"INITIAL_CAP")
      pairs.push(arg_int64(n))
    }
    None => ()
  }
  match spec.algorithm {
    Flat => {
      match spec.block_size {
        Some(n) => {
          pairs.push(b"BLOCK_SIZE")
          pairs.push(arg_int64(n))
        }
        None => ()
      }
      args.push(b"FLAT")
      args.push(arg_int(pairs.length()))
      for pair in pairs {
        args.push(pair)
      }
    }
    Hnsw => {
      match spec.m {
        Some(n) => {
          pairs.push(b"M")
          pairs.push(arg_int64(n))
        }
        None => ()
      }
      match spec.ef_construction {
        Some(n) => {
          pairs.push(b"EF_CONSTRUCTION")
          pairs.push(arg_int64(n))
        }
        None => ()
      }
      match spec.ef_runtime {
        Some(n) => {
          pairs.push(b"EF_RUNTIME")
          pairs.push(arg_int64(n))
        }
        None => ()
      }
      match spec.epsilon {
        Some(d) => {
          pairs.push(b"EPSILON")
          pairs.push(arg_double(d))
        }
        None => ()
      }
      args.push(b"HNSW")
      args.push(arg_int(pairs.length()))
      for pair in pairs {
        args.push(pair)
      }
    }
  }
}

///|
/// `FT.CREATE index [ON HASH|JSON] [PREFIX n ...] [FILTER expr] [LANGUAGE l]
/// [LANGUAGE_FIELD f] [SCORE s] [SCORE_FIELD f] [TEMPORARY secs] [STOPWORDS n ...]
/// SCHEMA field...`: build an index over the documents `schema` describes.
pub async fn Client::ft_create(
  self : Client,
  index : String,
  schema : Schema,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"FT.CREATE", arg_string(index)]
  args.push(b"ON")
  args.push(
    match schema.on {
      Hash => b"HASH"
      Json => b"JSON"
    },
  )
  if schema.prefixes.length() > 0 {
    args.push(b"PREFIX")
    args.push(arg_int(schema.prefixes.length()))
    for prefix in schema.prefixes {
      args.push(arg_string(prefix))
    }
  }
  push_some(args, b"FILTER", schema.filter.map(arg_string))
  push_some(args, b"LANGUAGE", schema.language.map(arg_string))
  push_some(args, b"LANGUAGE_FIELD", schema.language_field.map(arg_string))
  push_some(args, b"SCORE", schema.score.map(arg_double))
  push_some(args, b"SCORE_FIELD", schema.score_field.map(arg_string))
  push_some(args, b"TEMPORARY", schema.temporary.map(arg_int64))
  match schema.stopwords {
    Some(words) => {
      args.push(b"STOPWORDS")
      args.push(arg_int(words.length()))
      for word in words {
        args.push(arg_string(word))
      }
    }
    None => ()
  }
  args.push(b"SCHEMA")
  for field in schema.fields {
    encode_schema_field(args, field)
  }
  status_ok(self.command(args))
}

///|
/// `FT.ALTER index [SKIPINITIALSCAN] SCHEMA ADD field...`: add fields to a live index.
/// `skip_initial_scan` leaves the documents already indexed unbackfilled.
pub async fn Client::ft_alter(
  self : Client,
  index : String,
  fields : Array[SchemaField],
  skip_initial_scan? : Bool,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"FT.ALTER", arg_string(index)]
  if skip_initial_scan.unwrap_or(false) {
    args.push(b"SKIPINITIALSCAN")
  }
  args.push(b"SCHEMA")
  args.push(b"ADD")
  for field in fields {
    encode_schema_field(args, field)
  }
  status_ok(self.command(args))
}

///|
/// `FT.DROPINDEX index [DD]`: drop an index, and with `delete_documents` the documents it
/// indexed.
pub async fn Client::ft_dropindex(
  self : Client,
  index : String,
  delete_documents? : Bool,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [b"FT.DROPINDEX", arg_string(index)]
  if delete_documents.unwrap_or(false) {
    args.push(b"DD")
  }
  status_ok(self.command(args))
}

///|
/// `FT._LIST`: the names of the indexes.
pub async fn Client::ft_list(self : Client) -> Array[String] raise RedisError {
  expect_text_list(self.command([b"FT._LIST"]))
}

///|
/// `FT.ALIASADD alias index`: make `alias` another name for `index`.
pub async fn Client::ft_aliasadd(
  self : Client,
  alias_name : String,
  index : String,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"FT.ALIASADD", arg_string(alias_name), arg_string(index)]),
  )
}

///|
/// `FT.ALIASUPDATE alias index`: point an existing alias at another index.
pub async fn Client::ft_aliasupdate(
  self : Client,
  alias_name : String,
  index : String,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"FT.ALIASUPDATE", arg_string(alias_name), arg_string(index)]),
  )
}

///|
/// `FT.ALIASDEL alias`: drop an alias.
pub async fn Client::ft_aliasdel(
  self : Client,
  alias_name : String,
) -> Unit raise RedisError {
  status_ok(self.command([b"FT.ALIASDEL", arg_string(alias_name)]))
}

///|
/// Append `PARAMS` and `DIALECT`, which the query commands take last.
fn push_query_tail(
  args : Array[Bytes],
  params : Array[(String, Bytes)],
  dialect : Int32?,
) -> Unit {
  if params.length() > 0 {
    args.push(b"PARAMS")
    args.push(arg_int(params.length() * 2))
    for (name, value) in params {
      args.push(arg_string(name))
      args.push(value)
    }
  }
  push_some(args, b"DIALECT", dialect.map(arg_int))
}

///|
/// `FT.SEARCH index query [options]`: the documents that match `query`, with the scoring,
/// paging, sorting and projection `options` asks for.
pub async fn Client::ft_search(
  self : Client,
  index : String,
  query : String,
  options? : SearchOptions,
) -> SearchResult raise RedisError {
  let options = options.unwrap_or(search_default)
  let args : Array[Bytes] = [b"FT.SEARCH", arg_string(index), arg_string(query)]
  if options.nocontent {
    args.push(b"NOCONTENT")
  }
  if options.verbatim {
    args.push(b"VERBATIM")
  }
  if options.with_scores {
    args.push(b"WITHSCORES")
  }
  if options.with_payloads {
    args.push(b"WITHPAYLOADS")
  }
  if options.with_sort_keys {
    args.push(b"WITHSORTKEYS")
  }
  if options.return_fields.length() > 0 {
    args.push(b"RETURN")
    args.push(arg_int(options.return_fields.length()))
    for field in options.return_fields {
      args.push(arg_string(field))
    }
  }
  match options.summarize {
    Some(summarize) => {
      args.push(b"SUMMARIZE")
      if summarize.fields.length() > 0 {
        args.push(arg_int(summarize.fields.length()))
        for field in summarize.fields {
          args.push(arg_string(field))
        }
      }
      push_some(args, b"FRAGS", summarize.fragments.map(arg_int64))
      push_some(args, b"LEN", summarize.length.map(arg_int64))
      push_some(args, b"SEPARATOR", summarize.separator.map(arg_string))
    }
    None => ()
  }
  if options.highlight.length() > 0 {
    args.push(b"HIGHLIGHT")
    args.push(arg_int(options.highlight.length()))
    for field in options.highlight {
      args.push(arg_string(field))
    }
  }
  push_some(args, b"SLOP", options.slop.map(arg_int64))
  push_some(args, b"TIMEOUT", options.timeout.map(arg_int64))
  if options.in_keys.length() > 0 {
    args.push(b"INKEYS")
    args.push(arg_int(options.in_keys.length()))
    for key in options.in_keys {
      args.push(arg_string(key))
    }
  }
  if options.in_fields.length() > 0 {
    args.push(b"INFIELDS")
    args.push(arg_int(options.in_fields.length()))
    for field in options.in_fields {
      args.push(arg_string(field))
    }
  }
  match options.sort_by {
    Some(sort) => {
      args.push(b"SORTBY")
      args.push(arg_string(sort.field))
      args.push(if sort.ascending { b"ASC" } else { b"DESC" })
    }
    None => ()
  }
  match options.filter {
    Some(filter) => {
      args.push(b"FILTER")
      args.push(arg_string(filter.field))
      args.push(arg_string(filter.min))
      args.push(arg_string(filter.max))
    }
    None => ()
  }
  match options.geo_filter {
    Some(filter) => {
      args.push(b"GEOFILTER")
      args.push(arg_string(filter.field))
      args.push(arg_double(filter.longitude))
      args.push(arg_double(filter.latitude))
      args.push(arg_double(filter.radius))
      args.push(arg_string(filter.unit))
    }
    None => ()
  }
  if options.limit > 0 {
    args.push(b"LIMIT")
    args.push(arg_int64(options.offset))
    args.push(arg_int64(options.limit))
  }
  push_some(args, b"SCORER", options.scorer.map(arg_string))
  push_some(args, b"LANGUAGE", options.language.map(arg_string))
  if options.explain_score {
    args.push(b"EXPLAINSCORE")
  }
  push_query_tail(args, options.params, options.dialect)
  decode_search(self.command(args), options)
}

///|
/// The extras a search reply carries between the id and the fields, in the order the
/// server writes them.
priv struct HitShape {
  with_scores : Bool
  with_payloads : Bool
  with_sort_keys : Bool
  nocontent : Bool
}

///|
/// A search reply as a `SearchResult`, from either protocol.
fn decode_search(
  reply : @resp.RespValue,
  options : SearchOptions,
) -> SearchResult raise RedisError {
  let shape : HitShape = {
    with_scores: options.with_scores,
    with_payloads: options.with_payloads,
    with_sort_keys: options.with_sort_keys,
    nocontent: options.nocontent,
  }
  match reply {
    @resp.RespMap(_) => decode_search_resp3(reply)
    @resp.Array(items) => decode_search_resp2(items, shape)
    other =>
      raise Protocol("expected a search reply, got " + @resp.resp_kind(other))
  }
}

///|
/// RESP2: `[total, id, score?, payload?, sortkey?, [field, value...], ...]`.
fn decode_search_resp2(
  items : Array[@resp.RespValue],
  shape : HitShape,
) -> SearchResult raise RedisError {
  guard items.length() > 0 else { raise Protocol("empty search reply") }
  let total = expect_int64(items[0])
  let hits : Array[SearchHit] = []
  let mut at = 1
  while at < items.length() {
    let id = expect_text(items[at])
    at += 1
    let score = if shape.with_scores {
      let value = expect_double(items[at])
      at += 1
      Some(value)
    } else {
      None
    }
    let payload = if shape.with_payloads {
      let value = expect_bytes(items[at])
      at += 1
      value
    } else {
      None
    }
    let sort_key = if shape.with_sort_keys {
      let value = expect_text(items[at])
      at += 1
      Some(value)
    } else {
      None
    }
    let fields : Array[(String, @resp.RespValue)] = []
    if !shape.nocontent && at < items.length() {
      let flat = expect_array(items[at])
      at += 1
      let mut index = 0
      while index + 1 < flat.length() {
        fields.push((expect_text(flat[index]), flat[index + 1]))
        index += 2
      }
    }
    hits.push({ id, fields, score, payload, sort_key, })
  }
  { total, hits, warnings: [], }
}

///|
/// RESP3: a map with `total_results`, `results` (each a map of `id`, `score`, `payload`,
/// `sortkey` and `extra_attributes`) and `warning`.
fn decode_search_resp3(
  reply : @resp.RespValue,
) -> SearchResult raise RedisError {
  let mut total = 0L
  let hits : Array[SearchHit] = []
  let warnings : Array[String] = []
  for (key, value) in expect_map(reply) {
    match expect_text(key) {
      "total_results" => total = expect_int64(value)
      "warning" =>
        for item in expect_array(value) {
          warnings.push(expect_text(item))
        }
      "results" =>
        for item in expect_array(value) {
          hits.push(decode_hit_resp3(item))
        }
      _ => ()
    }
  }
  { total, hits, warnings, }
}

///|
/// One RESP3 result entry as a `SearchHit`.
fn decode_hit_resp3(reply : @resp.RespValue) -> SearchHit raise RedisError {
  let mut id = ""
  let mut score : Double? = None
  let mut payload : Bytes? = None
  let mut sort_key : String? = None
  let fields : Array[(String, @resp.RespValue)] = []
  for (key, value) in expect_map(reply) {
    match expect_text(key) {
      "id" => id = expect_text(value)
      "score" => score = Some(expect_double(value))
      "payload" => payload = expect_bytes(value)
      "sortkey" => sort_key = Some(expect_text(value))
      "extra_attributes" =>
        for (name, field) in expect_map(value) {
          fields.push((expect_text(name), field))
        }
      _ => ()
    }
  }
  { id, fields, score, payload, sort_key, }
}

///|
/// `FT.AGGREGATE index query [options]`: run the pipeline of loads, groupings, applies,
/// sorts and filters `options` describes over the matching documents.
pub async fn Client::ft_aggregate(
  self : Client,
  index : String,
  query : String,
  options? : AggregateOptions,
) -> AggregateResult raise RedisError {
  let options = options.unwrap_or(aggregate_default)
  let args : Array[Bytes] = [
    b"FT.AGGREGATE",
    arg_string(index),
    arg_string(query),
  ]
  if options.verbatim {
    args.push(b"VERBATIM")
  }
  if options.load.length() > 0 {
    args.push(b"LOAD")
    args.push(arg_int(options.load.length()))
    for field in options.load {
      args.push(arg_string(field))
    }
  }
  if options.group_by.length() > 0 {
    args.push(b"GROUPBY")
    args.push(arg_int(options.group_by.length()))
    for field in options.group_by {
      args.push(arg_string(field))
    }
    for reducer in options.reducers {
      args.push(b"REDUCE")
      args.push(arg_string(reducer.function))
      args.push(arg_int(reducer.args.length()))
      for arg in reducer.args {
        args.push(arg_string(arg))
      }
      push_some(args, b"AS", reducer.as_.map(arg_string))
    }
  }
  for (expression, name) in options.apply {
    args.push(b"APPLY")
    args.push(arg_string(expression))
    args.push(b"AS")
    args.push(arg_string(name))
  }
  if options.sort_by.length() > 0 {
    args.push(b"SORTBY")
    args.push(arg_int(options.sort_by.length() * 2))
    for sort in options.sort_by {
      args.push(arg_string(sort.field))
      args.push(if sort.ascending { b"ASC" } else { b"DESC" })
    }
  }
  if options.limit > 0 {
    args.push(b"LIMIT")
    args.push(arg_int64(options.offset))
    args.push(arg_int64(options.limit))
  }
  push_some(args, b"FILTER", options.filter.map(arg_string))
  push_some(args, b"TIMEOUT", options.timeout.map(arg_int64))
  match options.cursor_count {
    Some(count) => {
      args.push(b"WITHCURSOR")
      args.push(b"COUNT")
      args.push(arg_int64(count))
      push_some(args, b"MAXIDLE", options.max_idle.map(arg_int64))
    }
    None => ()
  }
  push_query_tail(args, options.params, options.dialect)
  decode_aggregate(self.command(args), options.cursor_count is Some(_))
}

///|
/// `FT.CURSOR READ index cursor [COUNT n]`: the next page of an aggregation.
pub async fn Client::ft_cursor_read(
  self : Client,
  index : String,
  cursor : Int64,
  count? : Int64,
) -> AggregateResult raise RedisError {
  let args : Array[Bytes] = [
    b"FT.CURSOR",
    b"READ",
    arg_string(index),
    arg_int64(cursor),
  ]
  push_some(args, b"COUNT", count.map(arg_int64))
  decode_aggregate(self.command(args), true)
}

///|
/// `FT.CURSOR DEL index cursor`: drop a cursor and the rows it still holds.
pub async fn Client::ft_cursor_del(
  self : Client,
  index : String,
  cursor : Int64,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"FT.CURSOR", b"DEL", arg_string(index), arg_int64(cursor)]),
  )
}

///|
/// An aggregation reply as an `AggregateResult`. Both protocols wrap the rows and the
/// cursor id in a two-element array when the query asked for a cursor.
fn decode_aggregate(
  reply : @resp.RespValue,
  with_cursor : Bool,
) -> AggregateResult raise RedisError {
  match reply {
    @resp.Array(items) => {
      let wrapped = with_cursor &&
        items.length() == 2 &&
        (items[0] is @resp.Array(_) || items[0] is @resp.RespMap(_))
      if wrapped {
        let body = decode_aggregate_body(items[0])
        {
          total: body.total,
          rows: body.rows,
          cursor: Some(expect_int64(items[1])),
        }
      } else {
        decode_aggregate_body(reply)
      }
    }
    other => decode_aggregate_body(other)
  }
}

///|
/// The rows of an aggregation reply, without the cursor wrapper.
fn decode_aggregate_body(
  reply : @resp.RespValue,
) -> AggregateResult raise RedisError {
  match reply {
    @resp.RespMap(_) => {
      let mut total = 0L
      let rows : Array[Array[(String, FieldValue)]] = []
      for (key, value) in expect_map(reply) {
        match expect_text(key) {
          "total_results" => total = expect_int64(value)
          "results" =>
            for item in expect_array(value) {
              rows.push(decode_row_resp3(item))
            }
          _ => ()
        }
      }
      { total, rows, cursor: None, }
    }
    @resp.Array(items) => {
      guard items.length() > 0 else { raise Protocol("empty aggregate reply") }
      {
        total: expect_int64(items[0]),
        rows: decode_rows_resp2(items[1:].to_owned()),
        cursor: None,
      }
    }
    other =>
      raise Protocol(
        "expected an aggregate reply, got " + @resp.resp_kind(other),
      )
  }
}

///|
/// RESP2 rows: each a flat array of field, value, field, value.
fn decode_rows_resp2(
  items : Array[@resp.RespValue],
) -> Array[Array[(String, FieldValue)]] raise RedisError {
  let rows : Array[Array[(String, FieldValue)]] = []
  for item in items {
    let flat = expect_array(item)
    let row : Array[(String, FieldValue)] = []
    let mut at = 0
    while at + 1 < flat.length() {
      row.push((expect_text(flat[at]), field_value(flat[at + 1])))
      at += 2
    }
    rows.push(row)
  }
  rows
}

///|
/// One RESP3 row, whose values live under `extra_attributes`.
fn decode_row_resp3(
  item : @resp.RespValue,
) -> Array[(String, FieldValue)] raise RedisError {
  let row : Array[(String, FieldValue)] = []
  for (key, value) in expect_map(item) {
    if expect_text(key) == "extra_attributes" {
      for (name, field) in expect_map(value) {
        row.push((expect_text(name), field_value(field)))
      }
    }
  }
  row
}

///|
/// `FT.TAGVALS index field`: the distinct values of a tag field.
pub async fn Client::ft_tagvals(
  self : Client,
  index : String,
  field : String,
) -> Array[String] raise RedisError {
  expect_text_list(
    self.command([b"FT.TAGVALS", arg_string(index), arg_string(field)]),
  )
}

///|
/// One term the index does not know, and what it suggests instead.
pub(all) struct SpellCheckTerm {
  term : String
  /// Each suggestion with its distance from the query term.
  suggestions : Array[(Double, String)]
}

///|
/// `FT.SPELLCHECK index query [DISTANCE d] [DIALECT d]`: the query terms the index knows
/// nothing about, and what it suggests instead.
pub async fn Client::ft_spellcheck(
  self : Client,
  index : String,
  query : String,
  distance? : Int32,
  dialect? : Int32,
) -> Array[SpellCheckTerm] raise RedisError {
  let args : Array[Bytes] = [
    b"FT.SPELLCHECK",
    arg_string(index),
    arg_string(query),
  ]
  push_some(args, b"DISTANCE", distance.map(arg_int))
  push_some(args, b"DIALECT", dialect.map(arg_int))
  // RESP3 keys the terms by name under `results`; RESP2 writes `[TERM, term, [...]]`.
  let terms : Array[(String, @resp.RespValue)] = []
  match self.command(args) {
    @resp.RespMap(map) =>
      for (key, value) in map {
        if expect_text(key) == "results" {
          for (name, suggestions) in expect_map(value) {
            terms.push((expect_text(name), suggestions))
          }
        }
      }
    other =>
      for entry in expect_array(other) {
        let fields = expect_array(entry)
        guard fields.length() >= 3 else {
          raise Protocol("unexpected FT.SPELLCHECK entry")
        }
        terms.push((expect_text(fields[1]), fields[2]))
      }
  }
  let out : Array[SpellCheckTerm] = []
  for (term, suggestions) in terms {
    let found : Array[(Double, String)] = []
    for item in expect_array(suggestions) {
      match item {
        @resp.Array(pair) => {
          guard pair.length() >= 2 else {
            raise Protocol("unexpected FT.SPELLCHECK suggestion")
          }
          found.push((expect_double(pair[0]), expect_text(pair[1])))
        }
        // RESP3 writes one `{suggestion: distance}` map per suggestion.
        @resp.RespMap(one) =>
          for (suggestion, distance) in one {
            found.push((expect_double(distance), expect_text(suggestion)))
          }
        _ => raise Protocol("unexpected FT.SPELLCHECK suggestion")
      }
    }
    out.push({ term, suggestions: found, })
  }
  out
}

///|
/// `FT.DICTADD dictionary term [term ...]`: add terms to a spelling dictionary, returning
/// how many were new.
pub async fn Client::ft_dictadd(
  self : Client,
  dictionary : String,
  terms : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"FT.DICTADD", arg_string(dictionary)]
  for term in terms {
    args.push(arg_string(term))
  }
  expect_int64(self.command(args))
}

///|
/// `FT.DICTDEL dictionary term [term ...]`: remove terms, returning how many existed.
pub async fn Client::ft_dictdel(
  self : Client,
  dictionary : String,
  terms : Array[String],
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [b"FT.DICTDEL", arg_string(dictionary)]
  for term in terms {
    args.push(arg_string(term))
  }
  expect_int64(self.command(args))
}

///|
/// `FT.DICTDUMP dictionary`: every term in a dictionary.
pub async fn Client::ft_dictdump(
  self : Client,
  dictionary : String,
) -> Array[String] raise RedisError {
  expect_text_list(self.command([b"FT.DICTDUMP", arg_string(dictionary)]))
}

///|
/// `FT.SYNUPDATE index group [SKIPINITIALSCAN] term [term ...]`: put the terms in one
/// synonym group.
pub async fn Client::ft_synupdate(
  self : Client,
  index : String,
  group : String,
  terms : Array[String],
  skip_initial_scan? : Bool,
) -> Unit raise RedisError {
  let args : Array[Bytes] = [
    b"FT.SYNUPDATE",
    arg_string(index),
    arg_string(group),
  ]
  if skip_initial_scan.unwrap_or(false) {
    args.push(b"SKIPINITIALSCAN")
  }
  for term in terms {
    args.push(arg_string(term))
  }
  status_ok(self.command(args))
}

///|
/// `FT.SYNDUMP index`: each term that has synonyms, and the groups it belongs to.
pub async fn Client::ft_syndump(
  self : Client,
  index : String,
) -> Array[(String, Array[String])] raise RedisError {
  let out : Array[(String, Array[String])] = []
  match self.command([b"FT.SYNDUMP", arg_string(index)]) {
    @resp.RespMap(pairs) =>
      for (term, groups) in pairs {
        out.push((expect_text(term), expect_text_list(groups)))
      }
    other => {
      let flat = expect_array(other)
      guard flat.length() % 2 == 0 else {
        raise Protocol("unexpected FT.SYNDUMP reply")
      }
      for at in 0..<(flat.length() / 2) {
        out.push(
          (expect_text(flat[at * 2]), expect_text_list(flat[at * 2 + 1])),
        )
      }
    }
  }
  out
}

///|
/// `FT.SUGADD key suggestion score [INCR] [PAYLOAD payload]`: add a completion, returning
/// how many suggestions the key holds.
pub async fn Client::ft_sugadd(
  self : Client,
  key : String,
  suggestion : String,
  score : Double,
  increment? : Bool,
  payload? : String,
) -> Int64 raise RedisError {
  let args : Array[Bytes] = [
    b"FT.SUGADD",
    arg_string(key),
    arg_string(suggestion),
    arg_double(score),
  ]
  if increment.unwrap_or(false) {
    args.push(b"INCR")
  }
  push_some(args, b"PAYLOAD", payload.map(arg_string))
  expect_int64(self.command(args))
}

///|
/// `FT.SUGGET key prefix [FUZZY] [MAX n]`: the completions starting with `prefix`.
pub async fn Client::ft_sugget(
  self : Client,
  key : String,
  prefix : String,
  fuzzy? : Bool,
  max? : Int64,
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [b"FT.SUGGET", arg_string(key), arg_string(prefix)]
  if fuzzy.unwrap_or(false) {
    args.push(b"FUZZY")
  }
  push_some(args, b"MAX", max.map(arg_int64))
  expect_text_list(self.command(args))
}

///|
/// `FT.SUGGET key prefix WITHSCORES`: the completions and their scores.
pub async fn Client::ft_sugget_scored(
  self : Client,
  key : String,
  prefix : String,
  fuzzy? : Bool,
  max? : Int64,
) -> Array[(String, Double)] raise RedisError {
  let args : Array[Bytes] = [
    b"FT.SUGGET",
    arg_string(key),
    arg_string(prefix),
    b"WITHSCORES",
  ]
  if fuzzy.unwrap_or(false) {
    args.push(b"FUZZY")
  }
  push_some(args, b"MAX", max.map(arg_int64))
  let flat = expect_array(self.command(args))
  let out : Array[(String, Double)] = []
  let mut at = 0
  while at + 1 < flat.length() {
    out.push((expect_text(flat[at]), expect_double(flat[at + 1])))
    at += 2
  }
  out
}

///|
/// `FT.SUGLEN key`: how many completions a key holds.
pub async fn Client::ft_suglen(
  self : Client,
  key : String,
) -> Int64 raise RedisError {
  expect_int64(self.command([b"FT.SUGLEN", arg_string(key)]))
}

///|
/// `FT.SUGDEL key suggestion`: remove a completion. True if it was there.
pub async fn Client::ft_sugdel(
  self : Client,
  key : String,
  suggestion : String,
) -> Bool raise RedisError {
  expect_bool(
    self.command([b"FT.SUGDEL", arg_string(key), arg_string(suggestion)]),
  )
}

///|
/// `FT.CONFIG GET pattern`: the settings whose names match.
pub async fn Client::ft_config_get(
  self : Client,
  pattern : String,
) -> Array[(String, String)] raise RedisError {
  let out : Array[(String, String)] = []
  match self.command([b"FT.CONFIG", b"GET", arg_string(pattern)]) {
    @resp.RespMap(pairs) =>
      for (name, value) in pairs {
        out.push((expect_text(name), expect_text(value)))
      }
    other =>
      for entry in expect_array(other) {
        let pair = expect_array(entry)
        guard pair.length() >= 2 else {
          raise Protocol("unexpected FT.CONFIG GET entry")
        }
        out.push((expect_text(pair[0]), expect_text(pair[1])))
      }
  }
  out
}

///|
/// `FT.CONFIG SET name value`: change a search setting.
pub async fn Client::ft_config_set(
  self : Client,
  name : String,
  value : String,
) -> Unit raise RedisError {
  status_ok(
    self.command([b"FT.CONFIG", b"SET", arg_string(name), arg_string(value)]),
  )
}

///|
/// `FT.EXPLAIN index query [DIALECT d]`: the query as the engine interprets it.
pub async fn Client::ft_explain(
  self : Client,
  index : String,
  query : String,
  dialect? : Int32,
) -> String raise RedisError {
  let args : Array[Bytes] = [
    b"FT.EXPLAIN",
    arg_string(index),
    arg_string(query),
  ]
  push_some(args, b"DIALECT", dialect.map(arg_int))
  expect_text(self.command(args))
}

///|
/// `FT.EXPLAINCLI index query [DIALECT d]`: the same, one line per node.
pub async fn Client::ft_explaincli(
  self : Client,
  index : String,
  query : String,
  dialect? : Int32,
) -> Array[String] raise RedisError {
  let args : Array[Bytes] = [
    b"FT.EXPLAINCLI",
    arg_string(index),
    arg_string(query),
  ]
  push_some(args, b"DIALECT", dialect.map(arg_int))
  expect_text_list(self.command(args))
}

///|
/// `FT.PROFILE index SEARCH|AGGREGATE [LIMITED] QUERY query`: the ordinary reply and the
/// timing breakdown beside it, as the protocol carries them. The second element is a
/// nested profile whose shape the search engine documents, so it stays as it arrives.
pub async fn Client::ft_profile(
  self : Client,
  index : String,
  aggregate : Bool,
  query : String,
  limited? : Bool,
) -> @resp.RespValue raise RedisError {
  let args : Array[Bytes] = [b"FT.PROFILE", arg_string(index)]
  args.push(if aggregate { b"AGGREGATE" } else { b"SEARCH" })
  if limited.unwrap_or(false) {
    args.push(b"LIMITED")
  }
  args.push(b"QUERY")
  args.push(arg_string(query))
  self.command(args)
}

///|
/// One indexed field as `FT.INFO` describes it.
pub(all) struct IndexField {
  /// The hash field or JSONPath.
  identifier : String
  /// The name queries use.
  attribute : String
  /// `TEXT`, `TAG`, `NUMERIC`, `GEO` or `VECTOR`.
  type_ : String
  sortable : Bool
  unf : Bool
  noindex : Bool
  weight : Double
}

///|
/// What `FT.INFO` reports about an index: its size, its schema and its settings.
pub(all) struct IndexInfo {
  name : String
  /// `HASH` or `JSON`.
  key_type : String
  prefixes : Array[String]
  filter : String?
  default_score : Double
  num_docs : Int64
  max_doc_id : Int64
  num_terms : Int64
  num_records : Int64
  /// Whether a background scan is still running.
  indexing : Bool
  percent_indexed : Double
  indexing_failures : Int64
  attributes : Array[IndexField]
}

///|
/// `FT.INFO index`: the index's size, schema and settings.
pub async fn Client::ft_info(
  self : Client,
  index : String,
) -> IndexInfo raise RedisError {
  let mut name = index
  let mut key_type = "HASH"
  let mut prefixes : Array[String] = []
  let mut filter : String? = None
  let mut default_score = 1.0
  let mut num_docs = 0L
  let mut max_doc_id = 0L
  let mut num_terms = 0L
  let mut num_records = 0L
  let mut indexing = false
  let mut percent_indexed = 0.0
  let mut indexing_failures = 0L
  let attributes : Array[IndexField] = []
  for (key, value) in field_pairs(self.command([b"FT.INFO", arg_string(index)])) {
    match key {
      "index_name" => name = expect_text(value)
      "num_docs" => num_docs = expect_int64(value)
      "max_doc_id" => max_doc_id = expect_int64(value)
      "num_terms" => num_terms = expect_int64(value)
      "num_records" => num_records = expect_int64(value)
      "indexing" => indexing = expect_int64(value) != 0
      "percent_indexed" => percent_indexed = expect_double(value)
      "hash_indexing_failures" => indexing_failures = expect_int64(value)
      "index_definition" =>
        for (definition_key, definition) in field_pairs(value) {
          match definition_key {
            "key_type" => key_type = expect_text(definition)
            "prefixes" => prefixes = expect_text_list(definition)
            "filter" => filter = Some(expect_text(definition))
            "default_score" => default_score = expect_double(definition)
            _ => ()
          }
        }
      "attributes" =>
        for field in expect_array(value) {
          attributes.push(decode_index_field(field))
        }
      _ => ()
    }
  }
  {
    name,
    key_type,
    prefixes,
    filter,
    default_score,
    num_docs,
    max_doc_id,
    num_terms,
    num_records,
    indexing,
    percent_indexed,
    indexing_failures,
    attributes,
  }
}

///|
/// One entry of `FT.INFO`'s `attributes`. RESP2 writes a flat list whose flags stand alone
/// (`SORTABLE`, then `UNF`); RESP3 writes a map with a `flags` array.
fn decode_index_field(reply : @resp.RespValue) -> IndexField raise RedisError {
  let mut identifier = ""
  let mut attribute = ""
  let mut type_ = ""
  let mut sortable = false
  let mut unf = false
  let mut noindex = false
  let mut weight = 1.0
  match reply {
    @resp.RespMap(pairs) =>
      for (key, value) in pairs {
        match expect_text(key) {
          "identifier" => identifier = expect_text(value)
          "attribute" => attribute = expect_text(value)
          "type" => type_ = expect_text(value)
          "WEIGHT" => weight = expect_double(value)
          "flags" =>
            for flag in expect_array(value) {
              match expect_text(flag) {
                "SORTABLE" => sortable = true
                "UNF" => unf = true
                "NOINDEX" => noindex = true
                _ => ()
              }
            }
          _ => ()
        }
      }
    other => {
      let items = expect_array(other)
      let mut at = 0
      while at < items.length() {
        let key = expect_text(items[at])
        match key {
          "SORTABLE" => {
            sortable = true
            at += 1
            if at < items.length() && expect_text(items[at]) == "UNF" {
              unf = true
              at += 1
            }
          }
          "UNF" => {
            unf = true
            at += 1
          }
          "NOINDEX" => {
            noindex = true
            at += 1
          }
          "NOSTEM"
          | "CASESENSITIVE"
          | "WITHSUFFIXTRIE"
          | "INDEXEMPTY"
          | "INDEXMISSING" => at += 1
          _ => {
            let value = if at + 1 < items.length() {
              items[at + 1]
            } else {
              @resp.Null
            }
            match key {
              "identifier" => identifier = expect_text(value)
              "attribute" => attribute = expect_text(value)
              "type" => type_ = expect_text(value)
              "WEIGHT" => weight = expect_double(value)
              _ => ()
            }
            at += 2
          }
        }
      }
    }
  }
  { identifier, attribute, type_, sortable, unf, noindex, weight, }
}

///|
/// How a hybrid query fuses the two branches.
#derive(Eq, Debug)
pub(all) enum Fusion {
  /// Reciprocal rank fusion, the default.
  Rrf
  /// A weighted sum of the two scores.
  Linear
}

///|
pub extend Fusion with Debug::{to_repr}

///|
pub extend Fusion with Eq::{not_equal, equal}

///|
/// The options `FT.HYBRID` takes besides the index, the text query and the vector.
pub(all) struct HybridOptions {
  /// How many nearest neighbours the vector branch considers.
  knn : Int64
  /// How hard the HNSW graph is searched; `None` leaves the server default.
  ef_runtime : Int64?
  /// Keep neighbours within this radius instead of the `knn` nearest, with this epsilon.
  radius : (Double, Double)?
  /// The fusion method; `None` leaves the server's `RRF`.
  fusion : Fusion?
  /// `RRF`'s (window, constant), or `LINEAR`'s (alpha, beta).
  fusion_params : (Double, Double)?
  /// The fields to return; `["*"]` returns the whole document.
  load : Array[String]
  sort_by : SortKey?
  offset : Int64
  /// 0 leaves the server's default of 10.
  limit : Int64
  /// A post-fusion filter expression.
  filter : String?
  /// Extra `PARAMS` values; the vector itself is added by `ft_hybrid`.
  params : Array[(String, Bytes)]
  timeout : Int64?
}

///|
/// `FT.HYBRID`'s options at their documented defaults.
pub let hybrid_default : HybridOptions = HybridOptions::{
  knn: 10,
  ef_runtime: None,
  radius: None,
  fusion: None,
  fusion_params: None,
  load: [],
  sort_by: None,
  offset: 0,
  limit: 0,
  filter: None,
  params: [],
  timeout: None,
}

///|
/// `FT.HYBRID index SEARCH query VSIM @field $vector [KNN ...] [COMBINE ...] [LOAD ...]
/// [SORTBY ...] [LIMIT ...] [FILTER ...] PARAMS ...`: rank documents by a text search and a
/// vector search at once. `vector` is the query vector as the field's element type writes
/// it, and `vector_field` the name of the schema field it is compared against.
pub async fn Client::ft_hybrid(
  self : Client,
  index : String,
  query : String,
  vector_field : String,
  vector : Bytes,
  options? : HybridOptions,
) -> SearchResult raise RedisError {
  let options = options.unwrap_or(hybrid_default)
  let args : Array[Bytes] = [b"FT.HYBRID", arg_string(index)]
  args.push(b"SEARCH")
  args.push(arg_string(query))
  args.push(b"VSIM")
  args.push(arg_string("@" + vector_field))
  args.push(b"$moonredis_vector")
  match options.radius {
    Some((radius, epsilon)) => {
      args.push(b"RANGE")
      args.push(b"4")
      args.push(b"RADIUS")
      args.push(arg_double(radius))
      args.push(b"EPSILON")
      args.push(arg_double(epsilon))
    }
    None => {
      let knn : Array[Bytes] = [b"K", arg_int64(options.knn)]
      match options.ef_runtime {
        Some(n) => {
          knn.push(b"EF_RUNTIME")
          knn.push(arg_int64(n))
        }
        None => ()
      }
      args.push(b"KNN")
      args.push(arg_int(knn.length()))
      for item in knn {
        args.push(item)
      }
    }
  }
  match options.fusion {
    Some(fusion) => {
      args.push(b"COMBINE")
      args.push(
        match fusion {
          Rrf => b"RRF"
          Linear => b"LINEAR"
        },
      )
      let params : Array[Bytes] = []
      match (fusion, options.fusion_params) {
        (Rrf, Some((window, constant))) => {
          params.push(b"WINDOW")
          params.push(arg_double(window))
          params.push(b"CONSTANT")
          params.push(arg_double(constant))
        }
        (Linear, Some((alpha, beta))) => {
          params.push(b"ALPHA")
          params.push(arg_double(alpha))
          params.push(b"BETA")
          params.push(arg_double(beta))
        }
        _ => ()
      }
      args.push(arg_int(params.length()))
      for item in params {
        args.push(item)
      }
    }
    None => ()
  }
  if options.load.length() > 0 {
    args.push(b"LOAD")
    args.push(arg_int(options.load.length()))
    for field in options.load {
      args.push(arg_string(field))
    }
  }
  push_some(args, b"FILTER", options.filter.map(arg_string))
  if options.limit > 0 {
    args.push(b"LIMIT")
    args.push(arg_int64(options.offset))
    args.push(arg_int64(options.limit))
  }
  match options.sort_by {
    Some(sort) => {
      args.push(b"SORTBY")
      args.push(b"2")
      args.push(arg_string(sort.field))
      args.push(if sort.ascending { b"ASC" } else { b"DESC" })
    }
    None => ()
  }
  push_some(args, b"TIMEOUT", options.timeout.map(arg_int64))
  let params : Array[(String, Bytes)] = [("moonredis_vector", vector)]
  for (name, value) in options.params {
    params.push((name, value))
  }
  push_query_tail(args, params, None)
  decode_search(self.command(args), search_default)
}
