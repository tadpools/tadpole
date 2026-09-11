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

/// A rejected ID parse: the original string and why it failed.
pub type InvalidId {
  InvalidId(value: String, reason: snowflake.InvalidSnowflakeReason)
}

/// An opaque user ID. Construct from a string with `user_id`.
pub opaque type UserId {
  UserId(Snowflake)
}

/// An opaque guild (server) ID. Construct from a string with `guild_id`.
pub opaque type GuildId {
  GuildId(Snowflake)
}

/// An opaque channel ID. Construct from a string with `channel_id`.
pub opaque type ChannelId {
  ChannelId(Snowflake)
}

/// An opaque message ID. Construct from a string with `message_id`.
pub opaque type MessageId {
  MessageId(Snowflake)
}

/// An opaque role ID. Construct from a string with `role_id`.
pub opaque type RoleId {
  RoleId(Snowflake)
}

/// An opaque application (bot) ID. Construct from a string with `application_id`.
pub opaque type ApplicationId {
  ApplicationId(Snowflake)
}

/// An opaque webhook ID. Construct from a string with `webhook_id`.
pub opaque type WebhookId {
  WebhookId(Snowflake)
}

/// Parse a string as a UserId. Fails with `InvalidId` if the string is
/// not a valid snowflake.
pub fn user_id(value: String) -> Result(UserId, InvalidId) {
  snowflake(value) |> wrap(UserId)
}

/// Parse a string as a GuildId. Fails with `InvalidId` if the string is
/// not a valid snowflake.
pub fn guild_id(value: String) -> Result(GuildId, InvalidId) {
  snowflake(value) |> wrap(GuildId)
}

/// Parse a string as a ChannelId. Fails with `InvalidId` if the string
/// is not a valid snowflake.
pub fn channel_id(value: String) -> Result(ChannelId, InvalidId) {
  snowflake(value) |> wrap(ChannelId)
}

/// Parse a string as a MessageId. Fails with `InvalidId` if the string
/// is not a valid snowflake.
pub fn message_id(value: String) -> Result(MessageId, InvalidId) {
  snowflake(value) |> wrap(MessageId)
}

/// Parse a string as a RoleId. Fails with `InvalidId` if the string is
/// not a valid snowflake.
pub fn role_id(value: String) -> Result(RoleId, InvalidId) {
  snowflake(value) |> wrap(RoleId)
}

/// Parse a string as an ApplicationId. Fails with `InvalidId` if the
/// string is not a valid snowflake.
pub fn application_id(value: String) -> Result(ApplicationId, InvalidId) {
  snowflake(value) |> wrap(ApplicationId)
}

/// Parse a string as a WebhookId. Fails with `InvalidId` if the string
/// is not a valid snowflake.
pub fn webhook_id(value: String) -> Result(WebhookId, InvalidId) {
  snowflake(value) |> wrap(WebhookId)
}

/// Decimal string form of the user ID, ready for URL paths and API calls.
pub fn user_to_string(id: UserId) -> String {
  let UserId(sf) = id
  snowflake.to_string(sf)
}

/// Integer form of the user ID, needed for bitfield operations and the
/// occasional numeric API field.
pub fn user_to_int(id: UserId) -> Int {
  let UserId(sf) = id
  snowflake.to_int(sf)
}

/// Decimal string form of the guild ID.
pub fn guild_to_string(id: GuildId) -> String {
  let GuildId(sf) = id
  snowflake.to_string(sf)
}

/// Decimal string form of the channel ID.
pub fn channel_to_string(id: ChannelId) -> String {
  let ChannelId(sf) = id
  snowflake.to_string(sf)
}

/// Decimal string form of the message ID.
pub fn message_to_string(id: MessageId) -> String {
  let MessageId(sf) = id
  snowflake.to_string(sf)
}

/// Decimal string form of the role ID.
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
