//// Tests for the shared decoder plumbing: snowflake ID fields and the
//// parse-to-DecodeFailed wrapper.

import gleam/dynamic/decode as d
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error.{DecodeFailed}
import tadpole/model/decode
import tadpole/types/ids

type Box {
  Box(id: ids.UserId)
}

fn box_decoder() -> d.Decoder(Box) {
  use id <- d.field("id", decode.snowflake_id(ids.user_id))
  d.success(Box(id: id))
}

pub fn snowflake_field_parses_test() {
  let assert Ok(id) = ids.user_id("900000000000000001")
  decode.from_json(None, "{\"id\":\"900000000000000001\"}", box_decoder())
  |> should.equal(Ok(Box(id: id)))
}

pub fn snowflake_garbage_keeps_raw_string_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    decode.from_json(None, "{\"id\":\"blub\"}", box_decoder())

  path |> should.equal("id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("blub")
}

pub fn event_name_passes_through_test() {
  let assert Error(DecodeFailed(event, _, _, _)) =
    decode.from_json(Some("MESSAGE_CREATE"), "{\"id\":\"blub\"}", box_decoder())

  event |> should.equal(Some("MESSAGE_CREATE"))
}

pub fn truncated_json_reports_root_path_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    decode.from_json(None, "{\"id\":", box_decoder())

  path |> should.equal("$")
  expected |> should.equal("a JSON payload")
  got |> should.equal("truncated JSON")
}

pub fn non_object_payload_reports_root_path_test() {
  let assert Error(DecodeFailed(_, path, _, _)) =
    decode.from_json(None, "42", box_decoder())

  path |> should.equal("$")
}

pub fn missing_field_reads_plainly_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    decode.from_json(None, "{}", box_decoder())

  path |> should.equal("id")
  expected |> should.equal("a value for this field")
  got |> should.equal("the field is absent")
}

pub fn wrong_type_reports_classified_got_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    decode.from_json(None, "{\"id\":null}", box_decoder())

  path |> should.equal("id")
  expected |> should.equal("String")
  got |> should.equal("null")
}

// A REST body is whatever Discord sent. If it carries a top-level `d`
// key then `d` is a field of the object, not a wrapper, and peeling it
// would hand the caller a different object with no error at all.

const outer = "{\"id\":\"900000000000000001\",\"d\":{\"id\":\"900000000000000002\"}}"

pub fn from_json_reads_a_top_level_d_as_data_test() {
  let assert Ok(outer_box) = decode.from_json(None, outer, box_decoder())
  ids.user_to_string(outer_box.id) |> should.equal("900000000000000001")
}

pub fn from_frame_unwraps_the_same_payload_test() {
  // The gateway path is the one that knows it has an envelope, so this
  // is where the two differ. Same input, different stated shape.
  let assert Ok(inner_box) = decode.from_frame(None, outer, box_decoder())
  ids.user_to_string(inner_box.id) |> should.equal("900000000000000002")
}

pub fn from_frame_accepts_a_payload_with_no_d_test() {
  // What the typed event tests and any replay tool write by hand. The
  // leniency is deliberate and pinned, because removing it would be a
  // breaking change for anyone replaying captured payloads.
  let assert Ok(box) =
    decode.from_frame(None, "{\"id\":\"900000000000000003\"}", box_decoder())

  ids.user_to_string(box.id) |> should.equal("900000000000000003")
}

pub fn from_frame_reports_a_decode_failure_inside_d_test() {
  // The reported path is relative to the event object, so a failure
  // inside `d` still reads as the field that broke rather than "d.id".
  let payload = "{\"op\":0,\"d\":{\"id\":\"nope\"}}"
  let assert Error(DecodeFailed(_, path, _, got)) =
    decode.from_frame(Some("MESSAGE_CREATE"), payload, box_decoder())

  path |> should.equal("id")
  got |> should.equal("nope")
}

pub fn from_frame_still_reports_broken_json_test() {
  let assert Error(DecodeFailed(_, path, _, _)) =
    decode.from_frame(None, "{oops", box_decoder())

  path |> should.equal("$")
}
