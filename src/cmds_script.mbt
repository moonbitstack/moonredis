// The Lua-scripting and function commands, named as in redis-py. A script runs atomically
// on the server; because it can return any RESP type, the eval/function-call methods hand
// back the raw `RespValue` for the caller to decode.

///|
/// `EVAL script numkeys key... arg...`: run `script`, declaring how many of the leading
/// arguments are keys. Returns the script's (arbitrary) reply.
pub async fn Client::eval(
  self : Client,
  script : String,
  keys : Array[String],
  args : Array[String],
) -> @resp.RespValue raise RedisError {
  let cmd : Array[Bytes] = [b"EVAL", arg_string(script), arg_int(keys.length())]
  for k in keys {
    cmd.push(arg_string(k))
  }
  for a in args {
    cmd.push(arg_string(a))
  }
  self.command(cmd)
}

///|
/// `EVALSHA sha numkeys key... arg...`: run a script by its `SCRIPT LOAD` digest.
pub async fn Client::evalsha(
  self : Client,
  sha : String,
  keys : Array[String],
  args : Array[String],
) -> @resp.RespValue raise RedisError {
  let cmd : Array[Bytes] = [b"EVALSHA", arg_string(sha), arg_int(keys.length())]
  for k in keys {
    cmd.push(arg_string(k))
  }
  for a in args {
    cmd.push(arg_string(a))
  }
  self.command(cmd)
}

///|
/// `SCRIPT LOAD script`: register `script` and return its SHA-1 digest for later `EVALSHA`.
pub async fn Client::script_load(
  self : Client,
  script : String,
) -> String raise RedisError {
  expect_string_value(self.command([b"SCRIPT", b"LOAD", arg_string(script)]))
}

///|
/// `SCRIPT EXISTS sha...`: whether each digest is loaded, in order.
pub async fn Client::script_exists(
  self : Client,
  shas : Array[String],
) -> Array[Bool] raise RedisError {
  let args : Array[Bytes] = [b"SCRIPT", b"EXISTS"]
  for s in shas {
    args.push(arg_string(s))
  }
  let items = expect_array(self.command(args))
  items.map(x => expect_int64(x) != 0)
}

///|
/// `SCRIPT FLUSH`: discard every loaded script.
pub async fn Client::script_flush(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"SCRIPT", b"FLUSH"]))
}

///|
/// `FUNCTION LOAD [REPLACE] code`: register a functions library, returning its name.
pub async fn Client::function_load(
  self : Client,
  code : String,
  replace? : Bool,
) -> String raise RedisError {
  let args : Array[Bytes] = [b"FUNCTION", b"LOAD"]
  if replace.unwrap_or(false) {
    args.push(b"REPLACE")
  }
  args.push(arg_string(code))
  expect_string_value(self.command(args))
}

///|
/// `FCALL function numkeys key... arg...`: call a registered function.
pub async fn Client::function_call(
  self : Client,
  function : String,
  keys : Array[String],
  args : Array[String],
) -> @resp.RespValue raise RedisError {
  let cmd : Array[Bytes] = [
    b"FCALL",
    arg_string(function),
    arg_int(keys.length()),
  ]
  for k in keys {
    cmd.push(arg_string(k))
  }
  for a in args {
    cmd.push(arg_string(a))
  }
  self.command(cmd)
}

///|
/// `FUNCTION FLUSH`: discard every registered function library.
pub async fn Client::function_flush(self : Client) -> Unit raise RedisError {
  status_ok(self.command([b"FUNCTION", b"FLUSH"]))
}

///|
/// `FUNCTION DELETE name`: delete a function library by name.
pub async fn Client::function_delete(
  self : Client,
  name : String,
) -> Unit raise RedisError {
  status_ok(self.command([b"FUNCTION", b"DELETE", arg_string(name)]))
}
