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
