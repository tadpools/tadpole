//// Gateway frame parsing and payload building. The envelope is {op, d, s, t}.
//// `d` stays raw: per-event decoders consume it later, so new event
//// payloads can never break the envelope parser.
//// Optional fields use sentinel defaults (s = -1, t = "").
////
//// Internals: [`tadpole/gateway/transport`](transport.html) calls
//// `parse` on everything the gateway sends; [`tadpole/gateway/shard`](shard.html)
//// builds IDENTIFY/RESUME/HEARTBEAT payloads and reads HELLO and
//// InvalidSession through the helpers here. `FrameError` covers the only
//// two ways an envelope can fail — not JSON, or no `op`; everything
//// after `op` is someone else's decoder problem. See also
//// [`tadpole/gateway/opcode`](opcode.html) for the `op` values.

import gleam/dynamic/decode as d
import gleam/json
import gleam/option.{type Option, None, Some}
import tadpole/gateway/opcode.{type Opcode}

pub type FrameError {
  FrameNotJson
  FrameMissingOpcode
}

pub type Frame {
  Frame(
    opcode: Opcode,
    sequence: Option(Int),
    event_name: Option(String),
    raw: String,
  )
}

pub fn parse(payload: String) -> Result(Frame, FrameError) {
  let decoder = {
    use op <- d.field("op", d.int)
    use s_raw <- d.optional_field("s", -1, d.int)
    use t_raw <- d.optional_field("t", "", d.string)
    d.success(#(op, s_raw, t_raw))
  }

  case json.parse(payload, decoder) {
    Ok(#(op, s_raw, t_raw)) ->
      Ok(Frame(
        opcode: opcode.from_int(op),
        sequence: unsentinel_int(s_raw),
        event_name: unsentinel_string(t_raw),
        raw: payload,
      ))
    Error(_) -> Error(FrameNotJson)
  }
}

/// The first thing every shard reads after connecting.
pub fn hello_heartbeat_interval(payload: String) -> Result(Int, FrameError) {
  let interval_decoder = {
    use interval <- d.field("heartbeat_interval", d.int)
    d.success(interval)
  }
  let decoder = {
    use inner <- d.field("d", interval_decoder)
    d.success(inner)
  }

  case json.parse(payload, decoder) {
    Ok(interval) -> Ok(interval)
    Error(_) -> Error(FrameNotJson)
  }
}

/// True when Discord kept the session and RESUME may be attempted.
pub fn invalid_session_resumable(payload: String) -> Result(Bool, FrameError) {
  let decoder = {
    use inner <- d.field("d", d.bool)
    d.success(inner)
  }

  case json.parse(payload, decoder) {
    Ok(resumable) -> Ok(resumable)
    Error(_) -> Error(FrameNotJson)
  }
}

pub fn heartbeat_payload(sequence: Option(Int)) -> String {
  let data = case sequence {
    Some(seq) -> json.int(seq)
    None -> json.null()
  }
  framed(opcode.Heartbeat, data)
}

/// `shard` is #(shard_id, shard_count), Discord's documented order.
pub fn identify_payload(
  token: String,
  intents_value: Int,
  shard: #(Int, Int),
) -> String {
  let #(shard_id, shard_count) = shard
  framed(
    opcode.Identify,
    json.object([
      #("token", json.string(token)),
      #("intents", json.int(intents_value)),
      #("shard", json.array([shard_id, shard_count], json.int)),
      #(
        "properties",
        json.object([
          #("os", json.string("linux")),
          #("browser", json.string("tadpole")),
          #("device", json.string("tadpole")),
        ]),
      ),
    ]),
  )
}

pub fn resume_payload(
  token: String,
  session_id: String,
  sequence: Int,
) -> String {
  framed(
    opcode.Resume,
    json.object([
      #("token", json.string(token)),
      #("session_id", json.string(session_id)),
      #("seq", json.int(sequence)),
    ]),
  )
}

/// The fields of GET /gateway/bot that a shard fleet needs.
pub type GatewayBotInfo {
  GatewayBotInfo(url: String, shards: Int)
}

pub fn parse_gateway_bot(
  payload: String,
) -> Result(GatewayBotInfo, FrameError) {
  let decoder = {
    use url <- d.field("url", d.string)
    use shards <- d.field("shards", d.int)
    d.success(GatewayBotInfo(url: url, shards: shards))
  }

  case json.parse(payload, decoder) {
    Ok(info) -> Ok(info)
    Error(_) -> Error(FrameNotJson)
  }
}

fn framed(op: Opcode, data: json.Json) -> String {
  json.object([
    #("op", json.int(opcode.to_int(op))),
    #("d", data),
  ])
  |> json.to_string
}

fn unsentinel_int(raw: Int) -> Option(Int) {
  case raw {
    -1 -> None
    _ -> Some(raw)
  }
}

fn unsentinel_string(raw: String) -> Option(String) {
  case raw {
    "" -> None
    _ -> Some(raw)
  }
}
