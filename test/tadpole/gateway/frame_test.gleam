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

pub fn parse_json_without_opcode_is_error_test() {
  frame.parse("{\"d\":{}}") |> should.be_error
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
