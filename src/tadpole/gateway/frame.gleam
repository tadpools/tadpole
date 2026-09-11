//// Gateway frame parsing and payload building. The envelope is {op, d, s, t}.
//// `d` stays raw: per-event decoders consume it later, so new event
//// payloads can never break the envelope parser.
//// Optional fields use sentinel defaults (s = -1, t = "").
////
//// ## When you reach for this
////
//// Through [`tadpole/gateway/shard`](shard.html) — the shard actor calls
//// `parse` on every incoming payload, reads HELLO and InvalidSession
//// through the helpers, and builds IDENTIFY/RESUME/HEARTBEAT with the
//// payload helpers. Directly when you need `parse_gateway_bot` for the
//// initial websocket URL.
////
//// ## Internals
////
//// [`tadpole/gateway/transport`](transport.html) calls `parse` on
//// everything the gateway sends. `FrameError` covers the only two ways
//// an envelope can fail: not JSON at all (`FrameNotJson`), or valid JSON
//// carrying no integer `op` (`FrameMissingOpcode`). Everything after `op`
//// is someone else's decoder problem, so hostile payloads degrade to one
//// of those two values and never crash the connection. See also
//// [`tadpole/gateway/opcode`](opcode.html) for the `op` values.

import gleam/dynamic/decode as d
import gleam/json
import gleam/option.{type Option, None, Some}
import tadpole/gateway/opcode.{type Opcode}

/// Why a gateway payload failed to parse as a frame. Hostile input
/// degrades to one of these two; the shard never crashes on bad data.
pub type FrameError {
  FrameNotJson
  FrameMissingOpcode
}

/// A parsed gateway envelope: opcode, optional sequence number, optional
/// event name, and the raw JSON (passed to event-specific decoders).
pub type Frame {
  Frame(
    opcode: Opcode,
    sequence: Option(Int),
    event_name: Option(String),
    raw: String,
  )
}

/// Parse one gateway frame. Hostile input degrades to a Result, never a
/// crash: valid JSON without an integer op is FrameMissingOpcode, anything
/// that is not a decodable envelope is FrameNotJson. Unknown op values
/// still parse — they land in opcode.UnknownOpcode and the shard ignores
/// them, so a new Discord opcode is data, never a disconnect.
pub fn parse(payload: String) -> Result(Frame, FrameError) {
  let decoder = {
    // Discord nulls s and t on every non-dispatch frame (HELLO sends
    // "t": null, "s": null); d.optional turns absent and null alike
    // into None, which is exactly the Frame shape. op is checked after
    // the parse so a missing op is its own error, distinct from
    // payload that was never an envelope.
    use op <- d.optional_field("op", None, d.optional(d.int))
    use sequence <- d.optional_field("s", None, d.optional(d.int))
    use event_name <- d.optional_field("t", None, d.optional(d.string))
    d.success(#(op, sequence, event_name))
  }

  case json.parse(payload, decoder) {
    Ok(#(op, sequence, event_name)) ->
      case op {
        None -> Error(FrameMissingOpcode)
        Some(op) ->
          Ok(Frame(
            opcode: opcode.from_int(op),
            sequence: sequence,
            event_name: event_name,
            raw: payload,
          ))
      }
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

/// Build a HEARTBEAT payload. `sequence` is the last dispatch sequence
/// number, or null if none has been received yet.
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

/// Build a RESUME payload. The session_id and sequence are from the
/// last READY and the last dispatch event.
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

/// Parse the GET /gateway/bot response into the websocket URL and shard
/// count that a shard fleet needs.
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
