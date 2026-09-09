//// Tests for message and message-update decoding. Fixtures are
//// synthetic: IDs, names, and content invented for these tests, never
//// copied from Discord.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error.{DecodeFailed}
import tadpole/model/message
import tadpole/types/ids

const full_message = "{\"id\":\"120000000000000001\",\"channel_id\":\"130000000000000001\",\"guild_id\":\"140000000000000001\",\"author\":{\"id\":\"900000000000000001\",\"username\":\"tadpole_tester\"},\"content\":\"hello pond\",\"timestamp\":\"2026-09-07T12:00:00.000000+00:00\",\"edited_timestamp\":\"2026-09-07T12:05:00.000000+00:00\",\"tts\":false,\"mention_everyone\":false,\"mentions\":[{\"id\":\"900000000000000002\",\"username\":\"duck_friend\"}],\"mention_roles\":[\"150000000000000001\"],\"attachments\":[{\"id\":\"160000000000000001\",\"filename\":\"lily.png\",\"size\":2048,\"url\":\"https://cdn.example.test/lily.png\"}],\"pinned\":true,\"webhook_id\":\"170000000000000001\",\"type\":19}"

const lean_message = "{\"id\":\"120000000000000002\",\"channel_id\":\"130000000000000002\",\"author\":{\"id\":\"900000000000000003\",\"username\":\"lilypad\"},\"content\":\"\",\"timestamp\":\"2026-09-07T12:01:00.000000+00:00\",\"type\":0}"

pub fn from_json_full_message_test() {
  let assert Ok(parsed) = message.from_json(full_message)
  ids.message_to_string(parsed.id) |> should.equal("120000000000000001")
  ids.channel_to_string(parsed.channel_id)
  |> should.equal("130000000000000001")
  let assert Ok(guild_id) = ids.guild_id("140000000000000001")
  parsed.guild_id |> should.equal(Some(guild_id))
  parsed.author.username |> should.equal("tadpole_tester")
  parsed.content |> should.equal("hello pond")
  parsed.timestamp |> should.equal("2026-09-07T12:00:00.000000+00:00")
  parsed.edited_timestamp
  |> should.equal(Some("2026-09-07T12:05:00.000000+00:00"))
  parsed.tts |> should.equal(False)
  parsed.mention_everyone |> should.equal(False)
  list.length(parsed.mentions) |> should.equal(1)
  let assert [role_id] = parsed.mention_role_ids
  ids.role_to_string(role_id) |> should.equal("150000000000000001")
  list.length(parsed.attachments) |> should.equal(1)
  parsed.pinned |> should.equal(True)
  let assert Ok(webhook_id) = ids.webhook_id("170000000000000001")
  parsed.webhook_id |> should.equal(Some(webhook_id))
  parsed.message_type |> should.equal(19)
}

pub fn from_json_lean_message_defaults_test() {
  let assert Ok(parsed) = message.from_json(lean_message)
  parsed.guild_id |> should.equal(None)
  parsed.edited_timestamp |> should.equal(None)
  parsed.tts |> should.equal(False)
  parsed.mention_everyone |> should.equal(False)
  list.length(parsed.mentions) |> should.equal(0)
  list.length(parsed.mention_role_ids) |> should.equal(0)
  list.length(parsed.attachments) |> should.equal(0)
  parsed.pinned |> should.equal(False)
  parsed.webhook_id |> should.equal(None)
  parsed.message_type |> should.equal(0)
}

pub fn from_json_null_optionals_read_as_none_test() {
  let payload =
    "{\"id\":\"120000000000000003\",\"channel_id\":\"130000000000000003\","
    <> "\"author\":{\"id\":\"900000000000000004\",\"username\":\"x\"},"
    <> "\"content\":\"y\",\"timestamp\":\"2026-09-07T12:02:00.000000+00:00\","
    <> "\"guild_id\":null,\"edited_timestamp\":null,\"webhook_id\":null}"

  let assert Ok(parsed) = message.from_json(payload)
  parsed.guild_id |> should.equal(None)
  parsed.edited_timestamp |> should.equal(None)
  parsed.webhook_id |> should.equal(None)
}

pub fn from_json_missing_timestamp_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    message.from_json(
      "{\"id\":\"120000000000000004\",\"channel_id\":\"130000000000000004\","
      <> "\"author\":{\"id\":\"900000000000000005\",\"username\":\"x\"},"
      <> "\"content\":\"y\"}",
    )

  path |> should.equal("timestamp")
  expected |> should.equal("a value for this field")
  got |> should.equal("the field is absent")
}

pub fn from_json_garbage_guild_snowflake_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    message.from_json(
      "{\"id\":\"120000000000000005\",\"channel_id\":\"130000000000000005\","
      <> "\"guild_id\":\"###\",\"author\":{\"id\":\"900000000000000006\","
      <> "\"username\":\"x\"},\"content\":\"y\","
      <> "\"timestamp\":\"2026-09-07T12:00:00.000000+00:00\"}",
    )

  path |> should.equal("guild_id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("###")
}

pub fn from_json_bad_author_id_reports_nested_path_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    message.from_json(
      "{\"id\":\"120000000000000006\",\"channel_id\":\"130000000000000006\","
      <> "\"author\":{\"id\":\"oink\",\"username\":\"x\"},\"content\":\"y\","
      <> "\"timestamp\":\"2026-09-07T12:00:00.000000+00:00\"}",
    )

  path |> should.equal("author.id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("oink")
}

pub fn from_json_bad_mention_role_reports_list_index_path_test() {
  let assert Error(DecodeFailed(_, path, _, _)) =
    message.from_json(
      "{\"id\":\"120000000000000007\",\"channel_id\":\"130000000000000007\","
      <> "\"author\":{\"id\":\"900000000000000007\",\"username\":\"x\"},"
      <> "\"content\":\"y\",\"timestamp\":\"2026-09-07T12:00:00.000000+00:00\","
      <> "\"mention_roles\":[\"150000000000000002\",\"goop\"]}",
    )

  path |> should.equal("mention_roles[1]")
}

pub fn from_json_bad_mention_username_reports_nested_path_test() {
  let assert Error(DecodeFailed(_, path, _, _)) =
    message.from_json(
      "{\"id\":\"120000000000000008\",\"channel_id\":\"130000000000000008\","
      <> "\"author\":{\"id\":\"900000000000000008\",\"username\":\"x\"},"
      <> "\"content\":\"y\",\"timestamp\":\"2026-09-07T12:00:00.000000+00:00\","
      <> "\"mentions\":[{\"id\":\"900000000000000009\"}]}",
    )

  path |> should.equal("mentions[0].username")
}

pub fn from_json_attachment_fields_test() {
  let assert Ok(parsed) = message.from_json(full_message)
  let assert [attachment] = parsed.attachments
  attachment.id |> should.equal("160000000000000001")
  attachment.filename |> should.equal("lily.png")
  attachment.size |> should.equal(2048)
  attachment.url |> should.equal("https://cdn.example.test/lily.png")
}

pub fn update_from_json_full_partial_test() {
  let payload =
    "{\"id\":\"120000000000000009\",\"channel_id\":\"130000000000000009\","
    <> "\"content\":\"edited pond\",\"author\":{\"id\":\"900000000000000010\","
    <> "\"username\":\"frog_editor\"},\"edited_timestamp\":"
    <> "\"2026-09-07T13:00:00.000000+00:00\",\"pinned\":true}"

  let assert Ok(parsed) = message.update_from_json(payload)
  ids.message_to_string(parsed.id) |> should.equal("120000000000000009")
  ids.channel_to_string(parsed.channel_id)
  |> should.equal("130000000000000009")
  parsed.content |> should.equal(Some("edited pond"))
  let assert Some(author) = parsed.author
  author.username |> should.equal("frog_editor")
  parsed.edited_timestamp
  |> should.equal(Some("2026-09-07T13:00:00.000000+00:00"))
  parsed.pinned |> should.equal(Some(True))
}

pub fn update_from_json_ids_only_partial_test() {
  // MESSAGE_UPDATE can carry nothing but the two IDs.
  let payload =
    "{\"id\":\"120000000000000010\",\"channel_id\":\"130000000000000010\"}"

  let assert Ok(parsed) = message.update_from_json(payload)
  ids.message_to_string(parsed.id) |> should.equal("120000000000000010")
  parsed.content |> should.equal(None)
  parsed.author |> should.equal(None)
  parsed.edited_timestamp |> should.equal(None)
  parsed.pinned |> should.equal(None)
}

pub fn update_from_json_missing_id_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, _, _)) =
    message.update_from_json("{\"channel_id\":\"130000000000000011\"}")

  path |> should.equal("id")
}

pub fn update_from_json_garbage_id_is_decode_failed_test() {
  let assert Error(DecodeFailed(_, path, expected, got)) =
    message.update_from_json(
      "{\"id\":\"croak\",\"channel_id\":\"130000000000000012\"}",
    )

  path |> should.equal("id")
  expected |> should.equal("a Discord snowflake string")
  got |> should.equal("croak")
}
