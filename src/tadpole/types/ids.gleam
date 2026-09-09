//// Opaque ID types so a UserId can never be passed where a GuildId goes.
//// Every ID wraps a validated snowflake; nothing outside this module can
//// build one from thin air or read the integer back out.
////
//// ## When you reach for this
////
//// Events hand you typed IDs already — `message.channel_id` is a
//// ChannelId, ready for `bot.send_message` — so most code never calls a
//// constructor. You construct when an id arrives as text: config, a
//// command argument, a URL. The constructor validates it as a snowflake
//// before it can go anywhere near Discord.
////
//// ## The types
////
//// UserId, GuildId, ChannelId, MessageId, RoleId, ApplicationId,
//// WebhookId — one per Discord object kind this slice touches, all
//// opaque, all built the same way:
////
//// ```gleam
//// import tadpole/types/ids
////
//// // "123456789012345678" -> Ok(channel id)
//// // "nope"              -> Error(InvalidId("nope", NotANumber))
//// ids.channel_id("123456789012345678")
//// ```
////
//// Reading back: `user_to_string`, `user_to_int`, `guild_to_string`,
//// `channel_to_string`, `message_to_string`, `role_to_string` — the
//// explicit accessors this slice needs. Missing accessors get added
//// when a milestone dereferences the ID, with a reason in their doc.
////
//// ## Failure modes
////
//// Constructors fail with `InvalidId(value, reason)` when the string is
//// not a number, is negative, or embeds a timestamp past ~2090 — see
//// [`tadpole/types/snowflake`](snowflake.html) for the rules. Decoding
//// Discord payloads validates through the same constructors, so a
//// payload with a garbage id fails as `DecodeFailed`, not with a broken
//// ID in hand. Conversions cannot fail.
////
//// ## See also
////
//// - [`tadpole/types/snowflake`](snowflake.html) — the value underneath
//// - [`tadpole/model/message`](../model/message.html) — typed IDs straight out of payloads

import tadpole/types/snowflake.{type Snowflake}

pub type InvalidId {
  InvalidId(value: String, reason: snowflake.InvalidSnowflakeReason)
}

pub opaque type UserId {
  UserId(Snowflake)
}

pub opaque type GuildId {
  GuildId(Snowflake)
}

pub opaque type ChannelId {
  ChannelId(Snowflake)
}

pub opaque type MessageId {
  MessageId(Snowflake)
}

pub opaque type RoleId {
  RoleId(Snowflake)
}

pub opaque type ApplicationId {
  ApplicationId(Snowflake)
}

pub opaque type WebhookId {
  WebhookId(Snowflake)
}

pub fn user_id(value: String) -> Result(UserId, InvalidId) {
  snowflake(value) |> wrap(UserId)
}

pub fn guild_id(value: String) -> Result(GuildId, InvalidId) {
  snowflake(value) |> wrap(GuildId)
}

pub fn channel_id(value: String) -> Result(ChannelId, InvalidId) {
  snowflake(value) |> wrap(ChannelId)
}

pub fn message_id(value: String) -> Result(MessageId, InvalidId) {
  snowflake(value) |> wrap(MessageId)
}

pub fn role_id(value: String) -> Result(RoleId, InvalidId) {
  snowflake(value) |> wrap(RoleId)
}

pub fn application_id(value: String) -> Result(ApplicationId, InvalidId) {
  snowflake(value) |> wrap(ApplicationId)
}

pub fn webhook_id(value: String) -> Result(WebhookId, InvalidId) {
  snowflake(value) |> wrap(WebhookId)
}

pub fn user_to_string(id: UserId) -> String {
  let UserId(sf) = id
  snowflake.to_string(sf)
}

pub fn user_to_int(id: UserId) -> Int {
  let UserId(sf) = id
  snowflake.to_int(sf)
}

pub fn guild_to_string(id: GuildId) -> String {
  let GuildId(sf) = id
  snowflake.to_string(sf)
}

pub fn channel_to_string(id: ChannelId) -> String {
  let ChannelId(sf) = id
  snowflake.to_string(sf)
}

pub fn message_to_string(id: MessageId) -> String {
  let MessageId(sf) = id
  snowflake.to_string(sf)
}

pub fn role_to_string(id: RoleId) -> String {
  let RoleId(sf) = id
  snowflake.to_string(sf)
}

fn snowflake(value: String) -> Result(Snowflake, InvalidId) {
  case snowflake.from_string(value) {
    Ok(sf) -> Ok(sf)
    Error(snowflake.InvalidSnowflake(value, reason)) ->
      Error(InvalidId(value, reason))
  }
}

fn wrap(
  inner: Result(Snowflake, InvalidId),
  constructor: fn(Snowflake) -> a,
) -> Result(a, InvalidId) {
  case inner {
    Ok(sf) -> Ok(constructor(sf))
    Error(e) -> Error(e)
  }
}
