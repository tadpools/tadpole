//// Tests for channel decoding. Fixtures are synthetic: IDs and names
//// invented for these tests, never copied from Discord.

import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error.{DecodeFailed}
import tadpole/model/channel
import tadpole/types/ids

const guild_text_channel = "{\"id\":\"130000000000000001\",\"type\":0,\"name\":\"general\",\"guild_id\":\"140000000000000001\",\"topic\":\"pond talk\",\"last_message_id\":\"120000000000000001\"}"

const dm_channel = "{\"id\":\"130000000000000002\",\"type\":1}"

pub fn from_json_guild_text_channel_test() {
  let assert Ok(parsed) = channel.from_json(guild_text_channel)
  ids.channel_to_string(parsed.id) |> should.equal("130000000000000001")
  parsed.channel_type |> should.equal(0)
  parsed.name |> should.equal(Some("general"))
  let assert Ok(guild_id) = ids.guild_id("140000000000000001")
  parsed.guild_id |> should.equal(Some(guild_id))
  parsed.topic |> should.equal(Some("pond talk"))
  parsed.last_message_id |> should.equal(Some("120000000000000001"))
}

pub fn from_json_dm_channel_defaults_test() {
  let assert Ok(parsed) = channel.from_json(dm_channel)
  ids.channel_to_string(parsed.id) |> should.equal("130000000000000002")
  parsed.channel_type |> should.equal(1)
  parsed.name |> should.equal(None)
  parsed.guild_id |> should.equal(None)
  parsed.topic |> should.equal(None)
  parsed.last_message_id |> should.equal(None)
}

pub fn from_json_null_optionals_read_as_none_test() {
  let payload =
    "{\"id\":\"130000000000000003\",\"type\":0,\"name\":null,"
    <> "\"guild_id\":null,\"topic\":null,\"last_message_id\":null}"

  let assert Ok(parsed) = channel.from_json(payload)
  parsed.name |> should.equal(None)
  parsed.guild_id |> should.equal(None)
  parsed.topic |> should.equal(None)
  parsed.last_message_id |> should.equal(None)
}

pub fn from_json_missing_id_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    channel.from_json("{\"type\":0}")

  path |> should.equal("id")
  expected |> should.equal("a value for this field")
  got |> should.equal("the field is absent")
}

pub fn from_json_garbage_snowflake_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    channel.from_json("{\"id\":\"ribbit\"}")

  path |> should.equal("id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("ribbit")
}

pub fn from_json_garbage_guild_snowflake_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    channel.from_json("{\"id\":\"130000000000000004\",\"guild_id\":\"quack\"}")

  path |> should.equal("guild_id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("quack")
}

pub fn from_json_wrong_type_field_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    channel.from_json("{\"id\":\"130000000000000005\",\"type\":\"voice\"}")

  path |> should.equal("type")
  expected |> should.equal("Int")
  got |> should.equal("String")
}
