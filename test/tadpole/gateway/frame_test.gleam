//// Tests for Gateway frame parsing and payload construction.
////
//// Fixture payloads follow Discord's documented envelope shape
//// . Contract fixtures:

import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import tadpole/gateway/frame
import tadpole/gateway/opcode

// fixtures

const hello = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}"

const dispatch_message = "{\"op\":0,\"s\":42,\"t\":\"MESSAGE_CREATE\",\"d\":{\"id\":\"1\"}}"

const dispatch_no_seq = "{\"op\":0,\"t\":\"READY\",\"d\":{}}"

const reconnect = "{\"op\":7}"

const invalid_session_resumable = "{\"op\":9,\"d\":true}"

const invalid_session_fatal = "{\"op\":9,\"d\":false}"

const heartbeat_ack = "{\"op\":11}"

pub fn parse_hello_test() {
  let assert Ok(parsed) = frame.parse(hello)
  parsed.opcode |> should.equal(opcode.Hello)
  parsed.sequence |> should.equal(None)
  parsed.event_name |> should.equal(None)
}

pub fn parse_hello_with_null_fields_test() {
  // Discord sends "t": null, "s": null on every non-dispatch frame.
  // The old sentinel-default parse rejected exactly this shape, so a
  // real connection dropped its first frame and never reached READY.
  let nulls =
    "{\"t\":null,\"s\":null,\"op\":10,\"d\":{\"heartbeat_interval\":41250}}"
  let assert Ok(parsed) = frame.parse(nulls)
  parsed.opcode |> should.equal(opcode.Hello)
  parsed.sequence |> should.equal(None)
  parsed.event_name |> should.equal(None)
}

pub fn parse_dispatch_keeps_all_fields_test() {
  let assert Ok(parsed) = frame.parse(dispatch_message)
  parsed.opcode |> should.equal(opcode.Dispatch)
  parsed.sequence |> should.equal(Some(42))
  parsed.event_name |> should.equal(Some("MESSAGE_CREATE"))
}

pub fn parse_dispatch_without_sequence_test() {
  let assert Ok(parsed) = frame.parse(dispatch_no_seq)
  parsed.opcode |> should.equal(opcode.Dispatch)
  parsed.sequence |> should.equal(None)
  parsed.event_name |> should.equal(Some("READY"))
}

pub fn parse_reconnect_test() {
  let assert Ok(parsed) = frame.parse(reconnect)
  parsed.opcode |> should.equal(opcode.Reconnect)
}

pub fn parse_heartbeat_ack_test() {
  let assert Ok(parsed) = frame.parse(heartbeat_ack)
  parsed.opcode |> should.equal(opcode.HeartbeatAck)
}

pub fn parse_garbage_is_frame_not_json_test() {
  frame.parse("not json at all") |> should.equal(Error(frame.FrameNotJson))
}

pub fn parse_json_without_opcode_test() {
  // Valid JSON, but not an envelope: its own failure, distinct from
  // payload that was never JSON at all.
  frame.parse("{\"d\":{}}") |> should.equal(Error(frame.FrameMissingOpcode))
}

// ---- hostile fixtures: degrade to a Result, never a crash --------------

pub fn parse_op_null_is_missing_opcode_test() {
  // Discord nulls s and t on non-dispatch frames; a null op is not a
  // frame Discord sends, and it is not an envelope either.
  frame.parse("{\"op\":null}") |> should.equal(Error(frame.FrameMissingOpcode))
}

pub fn parse_op_as_float_rejected_test() {
  // JSON allows 0.0 where the protocol demands 0. The contract is
  // strict: op is an integer or the frame does not parse.
  frame.parse("{\"op\":0.0,\"t\":\"MESSAGE_CREATE\",\"d\":{}}")
  |> should.equal(Error(frame.FrameNotJson))
}

pub fn parse_op_as_string_rejected_test() {
  frame.parse("{\"op\":\"0\",\"d\":{}}")
  |> should.equal(Error(frame.FrameNotJson))
}

pub fn parse_sequence_as_float_rejected_test() {
  frame.parse("{\"op\":0,\"s\":42.5,\"t\":\"READY\",\"d\":{}}")
  |> should.equal(Error(frame.FrameNotJson))
}

pub fn parse_event_name_as_number_rejected_test() {
  frame.parse("{\"op\":0,\"t\":42,\"d\":{}}")
  |> should.equal(Error(frame.FrameNotJson))
}

pub fn parse_array_payload_rejected_test() {
  frame.parse("[]") |> should.equal(Error(frame.FrameNotJson))
}

pub fn parse_scalar_payload_rejected_test() {
  frame.parse("42") |> should.equal(Error(frame.FrameNotJson))
  frame.parse("\"a string\"") |> should.equal(Error(frame.FrameNotJson))
  frame.parse("null") |> should.equal(Error(frame.FrameNotJson))
  frame.parse("true") |> should.equal(Error(frame.FrameNotJson))
}

pub fn parse_empty_string_rejected_test() {
  frame.parse("") |> should.equal(Error(frame.FrameNotJson))
}

pub fn parse_unknown_opcodes_still_parse_test() {
  // The unknown-safe contract: a new Discord opcode is data the shard
  // ignores, never a parse failure or a disconnect.
  let assert Ok(parsed) = frame.parse("{\"op\":99,\"d\":{}}")
  parsed.opcode |> should.equal(opcode.UnknownOpcode(99))

  let assert Ok(negative) = frame.parse("{\"op\":-1,\"d\":{}}")
  negative.opcode |> should.equal(opcode.UnknownOpcode(-1))
}

pub fn parse_extra_envelope_fields_ignored_test() {
  // Discord can extend the envelope; extra fields are not ours to
  // reject.
  let payload =
    "{\"op\":0,\"s\":7,\"t\":\"READY\",\"d\":{},\"future_field\":{\"x\":1}}"
  let assert Ok(parsed) = frame.parse(payload)
  parsed.opcode |> should.equal(opcode.Dispatch)
  parsed.sequence |> should.equal(Some(7))
}

pub fn parse_deeply_nested_payload_test() {
  // 64 nested objects in d; the envelope reader never descends into
  // d, so nesting depth is the event decoder's problem, not ours.
  let nested = string.repeat("{\"a\":", 64) <> "1" <> string.repeat("}", 64)
  let payload = "{\"op\":0,\"s\":1,\"t\":\"X\",\"d\":" <> nested <> "}"
  let assert Ok(parsed) = frame.parse(payload)
  parsed.opcode |> should.equal(opcode.Dispatch)
}

pub fn parse_huge_event_name_test() {
  // A megabyte-scale event name parses; sizes Discord will not send
  // but a broken proxy might must degrade, not crash.
  let huge = string.repeat("x", 100_000)
  let payload = "{\"op\":0,\"s\":1,\"t\":\"" <> huge <> "\",\"d\":{}}"
  let assert Ok(parsed) = frame.parse(payload)
  let assert Some(name) = parsed.event_name
  string.length(name) |> should.equal(100_000)
}

pub fn parse_unicode_event_name_test() {
  // Multi-byte, CJK, emoji, combining marks: t is bytes on the wire,
  // and none of them may crash the parser or mangle the name.
  let unicode = "メッセージ_🐸_écho"
  let payload = "{\"op\":0,\"s\":1,\"t\":\"" <> unicode <> "\",\"d\":{}}"
  let assert Ok(parsed) = frame.parse(payload)
  parsed.event_name |> should.equal(Some(unicode))
}

pub fn hello_interval_extraction_test() {
  frame.hello_heartbeat_interval(hello) |> should.equal(Ok(41_250))
}

pub fn hello_interval_missing_fails_test() {
  frame.hello_heartbeat_interval("{\"op\":10,\"d\":{}}")
  |> should.be_error
}

pub fn invalid_session_resumable_true_test() {
  frame.invalid_session_resumable(invalid_session_resumable)
  |> should.equal(Ok(True))
}

pub fn invalid_session_resumable_false_test() {
  frame.invalid_session_resumable(invalid_session_fatal)
  |> should.equal(Ok(False))
}

pub fn heartbeat_payload_with_sequence_test() {
  frame.heartbeat_payload(Some(1337)) |> should.equal("{\"op\":1,\"d\":1337}")
}

pub fn heartbeat_payload_without_sequence_test() {
  frame.heartbeat_payload(None) |> should.equal("{\"op\":1,\"d\":null}")
}

pub fn identify_payload_shape_test() {
  let payload = frame.identify_payload("TOKEN", 513, #(0, 1))

  // Contains every required field, in any order (JSON object order is not
  // contractual — we assert content, not layout).
  contains(payload, "\"op\":2") |> should.be_true
  contains(payload, "\"token\":\"TOKEN\"") |> should.be_true
  contains(payload, "\"intents\":513") |> should.be_true
  contains(payload, "\"shard\":[0,1]") |> should.be_true
  contains(payload, "\"properties\"") |> should.be_true
}

pub fn resume_payload_shape_test() {
  let payload = frame.resume_payload("TOKEN", "session-1", 99)

  contains(payload, "\"op\":6") |> should.be_true
  contains(payload, "\"token\":\"TOKEN\"") |> should.be_true
  contains(payload, "\"session_id\":\"session-1\"") |> should.be_true
  contains(payload, "\"seq\":99") |> should.be_true
}

pub fn parse_gateway_bot_response_test() {
  let payload =
    "{\"url\":\"wss://gateway.discord.gg\",\"shards\":4,\"session_start_limit\":{}}"

  let assert Ok(info) = frame.parse_gateway_bot(payload)
  info.url |> should.equal("wss://gateway.discord.gg")
  info.shards |> should.equal(4)
}

pub fn parse_gateway_bot_missing_fields_test() {
  frame.parse_gateway_bot("{}") |> should.be_error
}

fn contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
