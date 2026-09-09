//// Tests for typed gateway event decoding, against synthetic fixtures.
//// No network: every payload is invented JSON in Discord's documented
//// shape.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/error.{DecodeFailed}
import tadpole/gateway/events
import tadpole/gateway/frame
import tadpole/types/ids

// fixtures

const ready = "{\"user\":{\"id\":\"900001\",\"username\":\"polly\",\"global_name\":null,\"avatar\":null,\"bot\":true,\"system\":false},\"guilds\":[{\"id\":\"700001\"},{\"id\":\"700002\"}],\"session_id\":\"session-1\",\"resume_gateway_url\":\"wss://gateway.discord.gg\"}"

const message_create = "{\"id\":\"100001\",\"channel_id\":\"200001\",\"guild_id\":\"300001\",\"author\":{\"id\":\"900001\",\"username\":\"polly\",\"global_name\":null,\"avatar\":null,\"bot\":false,\"system\":false},\"content\":\"hello pond\",\"timestamp\":\"2026-09-07T12:00:00.000000+00:00\",\"edited_timestamp\":null,\"tts\":false,\"mention_everyone\":false,\"mentions\":[],\"mention_roles\":[],\"attachments\":[],\"pinned\":false,\"type\":0}"

const message_update = "{\"id\":\"100001\",\"channel_id\":\"200001\",\"content\":\"edited pond\"}"

const message_delete = "{\"id\":\"100002\",\"channel_id\":\"200001\",\"guild_id\":\"300001\"}"

const guild_create = "{\"id\":\"300001\",\"name\":\"Pond\",\"member_count\":12}"

const guild_delete = "{\"id\":\"300001\",\"unavailable\":true}"

pub fn ready_decodes_user_and_guild_count_test() {
  let assert Ok(events.Ready(user, count)) = events.decode("READY", ready)
  user.username |> should.equal("polly")
  count |> should.equal(2)
}

pub fn ready_decode_failure_names_the_event_test() {
  let assert Error(DecodeFailed(Some("READY"), _, _, _)) =
    events.decode("READY", "{\"guilds\":[]}")
}

pub fn message_create_decodes_to_typed_message_test() {
  let assert Ok(events.MessageCreate(message)) =
    events.decode("MESSAGE_CREATE", message_create)
  ids.message_to_string(message.id) |> should.equal("100001")
  message.content |> should.equal("hello pond")
  message.author.username |> should.equal("polly")
}

pub fn message_create_malformed_payload_is_decode_failed_test() {
  // Missing the required `timestamp` field.
  let bad =
    "{\"id\":\"100001\",\"channel_id\":\"200001\",\"author\":{\"id\":\"900001\",\"username\":\"polly\"},\"content\":\"\"}"
  let assert Error(DecodeFailed(Some("MESSAGE_CREATE"), _, _, _)) =
    events.decode("MESSAGE_CREATE", bad)
}

pub fn message_create_non_snowflake_id_is_decode_failed_test() {
  let bad =
    "{\"id\":\"not-a-snowflake\",\"channel_id\":\"200001\",\"author\":{\"id\":\"900001\",\"username\":\"polly\"},\"content\":\"\",\"timestamp\":\"t\"}"
  let assert Error(DecodeFailed(Some("MESSAGE_CREATE"), _, _, _)) =
    events.decode("MESSAGE_CREATE", bad)
}

pub fn message_create_not_json_at_all_is_decode_failed_test() {
  let assert Error(DecodeFailed(Some("MESSAGE_CREATE"), _, _, _)) =
    events.decode("MESSAGE_CREATE", "definitely not json")
}

pub fn message_update_decodes_partial_object_test() {
  let assert Ok(events.MessageUpdate(update)) =
    events.decode("MESSAGE_UPDATE", message_update)
  ids.message_to_string(update.id) |> should.equal("100001")
  update.content |> should.equal(Some("edited pond"))
  update.author |> should.equal(None)
  update.pinned |> should.equal(None)
}

pub fn message_update_malformed_is_decode_failed_test() {
  let assert Error(DecodeFailed(Some("MESSAGE_UPDATE"), _, _, _)) =
    events.decode("MESSAGE_UPDATE", "{\"id\":\"x\",\"channel_id\":\"200001\"}")
}

pub fn message_delete_decodes_with_guild_test() {
  let assert Ok(events.MessageDelete(id, channel_id, guild_id)) =
    events.decode("MESSAGE_DELETE", message_delete)
  ids.message_to_string(id) |> should.equal("100002")
  ids.channel_to_string(channel_id) |> should.equal("200001")
  let assert Some(guild) = guild_id
  ids.guild_to_string(guild) |> should.equal("300001")
}

pub fn message_delete_without_guild_decodes_dm_shape_test() {
  let dm_delete = "{\"id\":\"100002\",\"channel_id\":\"200001\"}"
  let assert Ok(events.MessageDelete(_, _, guild_id)) =
    events.decode("MESSAGE_DELETE", dm_delete)
  guild_id |> should.equal(None)
}

pub fn message_delete_malformed_is_decode_failed_test() {
  let assert Error(DecodeFailed(Some("MESSAGE_DELETE"), _, _, _)) =
    events.decode("MESSAGE_DELETE", "{\"id\":\"100002\"}")
}

pub fn resumed_decodes_regardless_of_payload_test() {
  events.decode("RESUMED", "{}") |> should.equal(Ok(events.Resumed))
  events.decode("RESUMED", "{\"_trace\":[\"gateway\"]}")
  |> should.equal(Ok(events.Resumed))
}

pub fn guild_create_decodes_test() {
  let assert Ok(events.GuildCreate(guild)) =
    events.decode("GUILD_CREATE", guild_create)
  guild.name |> should.equal("Pond")
  guild.member_count |> should.equal(Some(12))
}

pub fn guild_create_malformed_is_decode_failed_test() {
  let assert Error(DecodeFailed(Some("GUILD_CREATE"), _, _, _)) =
    events.decode("GUILD_CREATE", "{\"name\":\"Pond\"}")
}

pub fn guild_delete_decodes_unavailable_shape_test() {
  let assert Ok(events.GuildDelete(unavailable)) =
    events.decode("GUILD_DELETE", guild_delete)
  ids.guild_to_string(unavailable.id) |> should.equal("300001")
}

pub fn guild_delete_malformed_is_decode_failed_test() {
  let assert Error(DecodeFailed(Some("GUILD_DELETE"), _, _, _)) =
    events.decode("GUILD_DELETE", "{\"unavailable\":true}")
}

pub fn unmodeled_known_event_is_unknown_test() {
  let payload = "{\"user\":{}}"
  events.decode("GUILD_BAN_ADD", payload)
  |> should.equal(Ok(events.Unknown("GUILD_BAN_ADD", payload)))
}

// The shard feeds events.decode exactly what frame.parse produced: the
// full envelope, op and s and t and d. These tests pin that wiring, not
// just the bare d objects above.

pub fn ready_in_full_envelope_decodes_through_frame_parse_test() {
  let envelope = "{\"t\":\"READY\",\"s\":7,\"op\":0,\"d\":" <> ready <> "}"
  let assert Ok(frame) = frame.parse(envelope)
  let assert Some("READY") = frame.event_name

  let assert Ok(events.Ready(user, count)) = events.decode("READY", frame.raw)
  user.username |> should.equal("polly")
  count |> should.equal(2)
}

pub fn message_create_in_full_envelope_decodes_through_frame_parse_test() {
  let envelope =
    "{\"t\":\"MESSAGE_CREATE\",\"s\":8,\"op\":0,\"d\":" <> message_create <> "}"
  let assert Ok(frame) = frame.parse(envelope)

  let assert Ok(events.MessageCreate(message)) =
    events.decode("MESSAGE_CREATE", frame.raw)
  message.content |> should.equal("hello pond")
}

pub fn envelope_decode_failure_reports_path_inside_d_test() {
  // A bad id under d must be reported at author.id, not d.author.id:
  // callers think in event objects, not envelopes.
  let envelope =
    "{\"t\":\"MESSAGE_CREATE\",\"s\":9,\"op\":0,\"d\":{\"id\":\"not-a-snowflake\",\"channel_id\":\"200001\",\"author\":{\"id\":\"900001\",\"username\":\"polly\"},\"content\":\"\",\"timestamp\":\"t\"}}"
  let assert Error(DecodeFailed(_, path, _, _)) =
    events.decode("MESSAGE_CREATE", envelope)
  path |> should.equal("id")
}

pub fn bare_object_still_decodes_test() {
  // Direct callers and tests replay bare d objects; that shape stays.
  let assert Ok(events.Ready(user, _)) = events.decode("READY", ready)
  user.username |> should.equal("polly")
}

pub fn invented_event_name_is_unknown_test() {
  let payload = "{\"anything\":true}"
  events.decode("SOMETHING_DISCORD_ADDED_TOMORROW", payload)
  |> should.equal(
    Ok(events.Unknown("SOMETHING_DISCORD_ADDED_TOMORROW", payload)),
  )
}

pub fn unknown_never_fails_for_any_name_test() {
  ["", "ready", "MESSAGE_CREATE_BULK", "X"]
  |> list.each(fn(name) {
    let assert Ok(events.Unknown(_, _)) = events.decode(name, "{}")
  })
}
