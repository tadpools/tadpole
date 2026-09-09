//// Tests for user decoding. Fixtures are synthetic: the IDs are valid
//// snowflakes with values invented for these tests, never copied from
//// Discord.

import gleam/json
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error.{DecodeFailed}
import tadpole/model/user
import tadpole/types/ids

const full_user = "{\"id\":\"900000000000000001\",\"username\":\"tadpole_tester\",\"global_name\":\"Tadpole Tester\",\"avatar\":\"a9f8e7d6c5b4a3f2e1d0c\",\"bot\":true,\"system\":false}"

const minimal_user = "{\"id\":\"900000000000000002\",\"username\":\"pond_watcher\"}"

pub fn from_json_full_user_test() {
  let assert Ok(parsed) = user.from_json(full_user)
  ids.user_to_string(parsed.id) |> should.equal("900000000000000001")
  parsed.username |> should.equal("tadpole_tester")
  parsed.global_name |> should.equal(Some("Tadpole Tester"))
  parsed.avatar |> should.equal(Some("a9f8e7d6c5b4a3f2e1d0c"))
  parsed.bot |> should.equal(True)
  parsed.system |> should.equal(False)
}

pub fn from_json_optional_fields_default_when_absent_test() {
  let assert Ok(parsed) = user.from_json(minimal_user)
  parsed.global_name |> should.equal(None)
  parsed.avatar |> should.equal(None)
  parsed.bot |> should.equal(False)
  parsed.system |> should.equal(False)
}

pub fn from_json_null_optionals_read_as_none_test() {
  let null_optionals =
    "{\"id\":\"900000000000000003\",\"username\":\"ghost\",\"global_name\":null,\"avatar\":null}"

  let assert Ok(parsed) = user.from_json(null_optionals)
  parsed.global_name |> should.equal(None)
  parsed.avatar |> should.equal(None)
}

pub fn from_json_missing_username_is_decode_failed_test() {
  let assert Error(DecodeFailed(event, path, expected, got)) =
    user.from_json("{\"id\":\"900000000000000004\"}")

  event |> should.equal(None)
  path |> should.equal("username")
  expected |> should.equal("a value for this field")
  got |> should.equal("the field is absent")
}

pub fn from_json_garbage_snowflake_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    user.from_json("{\"id\":\"not-a-snowflake\",\"username\":\"x\"}")

  path |> should.equal("id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("not-a-snowflake")
}

pub fn from_json_non_string_id_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    user.from_json("{\"id\":900000000000000005,\"username\":\"x\"}")

  path |> should.equal("id")
  expected |> should.equal("String")
  got |> should.equal("Int")
}

pub fn from_json_non_json_payload_reports_root_path_test() {
  let assert Error(DecodeFailed(_, path, _, _)) = user.from_json("{oops")
  path |> should.equal("$")
}

pub fn decoder_composes_with_json_parse_test() {
  // The raw decoder is public so event modules can nest it; prove it
  // runs directly under gleam/json.
  let assert Ok(parsed) = json.parse(minimal_user, user.decoder())
  ids.user_to_string(parsed.id) |> should.equal("900000000000000002")
  parsed.username |> should.equal("pond_watcher")
}
