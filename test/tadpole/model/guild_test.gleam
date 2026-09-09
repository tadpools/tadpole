//// Tests for guild and unavailable-guild decoding. Fixtures are
//// synthetic: IDs and names invented for these tests, never copied from
//// Discord.

import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error.{DecodeFailed}
import tadpole/model/guild
import tadpole/types/ids

const full_guild = "{\"id\":\"140000000000000001\",\"name\":\"Pond Test Guild\",\"member_count\":42}"

const sparse_guild = "{\"id\":\"140000000000000002\",\"name\":\"Small Pond\"}"

const ready_guild_entry = "{\"id\":\"140000000000000003\",\"unavailable\":true}"

pub fn from_json_full_guild_test() {
  let assert Ok(parsed) = guild.from_json(full_guild)
  ids.guild_to_string(parsed.id) |> should.equal("140000000000000001")
  parsed.name |> should.equal("Pond Test Guild")
  parsed.member_count |> should.equal(Some(42))
}

pub fn from_json_missing_member_count_is_none_test() {
  let assert Ok(parsed) = guild.from_json(sparse_guild)
  parsed.name |> should.equal("Small Pond")
  parsed.member_count |> should.equal(None)
}

pub fn from_json_null_member_count_is_none_test() {
  let payload =
    "{\"id\":\"140000000000000004\",\"name\":\"Dry Pond\",\"member_count\":null}"

  let assert Ok(parsed) = guild.from_json(payload)
  parsed.name |> should.equal("Dry Pond")
  parsed.member_count |> should.equal(None)
}

pub fn from_json_garbage_snowflake_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    guild.from_json("{\"id\":\"not-a-snowflake\",\"name\":\"x\"}")

  path |> should.equal("id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("not-a-snowflake")
}

pub fn from_json_missing_id_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    guild.from_json("{\"name\":\"no id here\"}")

  path |> should.equal("id")
  expected |> should.equal("a value for this field")
  got |> should.equal("the field is absent")
}

pub fn unavailable_from_json_test() {
  let assert Ok(parsed) = guild.unavailable_from_json(ready_guild_entry)
  ids.guild_to_string(parsed.id) |> should.equal("140000000000000003")
}

pub fn unavailable_from_json_ignores_extra_fields_test() {
  let assert Ok(parsed) =
    guild.unavailable_from_json(
      "{\"id\":\"140000000000000005\",\"unavailable\":true,\"name\":\"ignored\"}",
    )

  ids.guild_to_string(parsed.id) |> should.equal("140000000000000005")
}

pub fn unavailable_from_json_garbage_snowflake_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, _, got)) =
    guild.unavailable_from_json("{\"id\":\"glub\"}")

  path |> should.equal("id")
  got |> should.equal("glub")
}

pub fn unavailable_from_json_missing_id_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, _, _)) =
    guild.unavailable_from_json("{}")

  path |> should.equal("id")
}
