//// The Discord message object for MESSAGE_CREATE, plus the partial
//// object MESSAGE_UPDATE sends. Attachments are kept to a skeleton:
//// bots that need them fetch the message again anyway.
//// message_type is Discord's raw integer; naming a sum type now would
//// freeze it against Discord's growing list.
////
//// ## When you reach for this
////
//// Through [`tadpole/gateway/events`](../gateway/events.html) as
//// `MessageCreate`'s payload and `MessageUpdate`'s partial; also from
//// [`tadpole/rest/endpoints`](../rest/endpoints.html)'s send/reply
//// responses. The `Message` record carries channel_id, author, content,
//// and the fields a bot reads out of events.
////
//// ## Two records, two payloads:
////
//// - `Message` — the full object MESSAGE_CREATE carries. Consumed by
////   [`tadpole/gateway/events`](../gateway/events.html)' MessageCreate
////   and by [`tadpole/rest/endpoints`](../rest/endpoints.html)'s
////   send/reply responses.
//// - `MessageUpdate` — the PARTIAL object MESSAGE_UPDATE carries. Only
////   the ids are guaranteed; every other field may be absent, and
////   absent reads as `None` rather than falling back to a cached
////   message — merging old and new state is the caller's job.
////
//// ## Why fields are Option
////
//// An `Option` means Discord omits the key or nulls it in the payloads
//// this record models: `guild_id` in DMs, `edited_timestamp` before the
//// first edit, `webhook_id` for non-webhook authors. Defaults differ by
//// field: `content` arrives as `""` for embed-only posts, `tts` /
//// `mention_everyone` / `pinned` default to False, `message_type` to 0
//// — those are documented Discord semantics, not guesses. Unknown
//// fields are ignored.
////
//// ## Why some fields are String, not IDs
////
//// `Attachment.id` is a plain String: attachments are rare in this
//// milestone and snowflake validation would only add a failure mode
//// without buying type safety anyone uses yet. Every field the library
//// itself dereferences — `id`, `channel_id`, `guild_id`, `webhook_id`,
//// mention role ids — is a typed ID that fails the decode if it is not
//// a snowflake.

import gleam/dynamic/decode as d
import gleam/option.{type Option, None}
import tadpole/error.{type TadpoleError}
import tadpole/model/decode
import tadpole/model/user.{type User}
import tadpole/types/ids.{
  type ChannelId, type GuildId, type MessageId, type RoleId, type WebhookId,
}

pub type Message {
  Message(
    id: MessageId,
    channel_id: ChannelId,
    /// None in DMs.
    guild_id: Option(GuildId),
    author: User,
    /// Empty when the message is an embed-only or attachment-only post.
    content: String,
    /// ISO8601 timestamp, passed through exactly as Discord sent it
    /// (always UTC, e.g. 2026-09-07T12:00:00.000000+00:00).
    timestamp: String,
    /// Stays None until the first edit; then it is Discord's ISO8601
    /// edit time.
    edited_timestamp: Option(String),
    tts: Bool,
    mention_everyone: Bool,
    mentions: List(User),
    mention_role_ids: List(RoleId),
    attachments: List(Attachment),
    pinned: Bool,
    /// Set when a webhook sent the message.
    webhook_id: Option(WebhookId),
    /// Discord's raw MESSAGE type integer: 0 DEFAULT, 1 RECIPIENT_ADD,
    /// 19 REPLY, 20 APPLICATION_COMMAND, and so on. Kept raw because
    /// Discord adds types faster than libraries track them.
    message_type: Int,
  )
}

pub type Attachment {
  Attachment(
    /// Deliberately String, not a typed ID: attachments are rare in this
    /// milestone and the snowflake validation buys nothing here yet.
    id: String,
    filename: String,
    size: Int,
    url: String,
  )
}

/// Decoder for the full message object MESSAGE_CREATE carries.
/// Discord sends IDs as strings; a non-snowflake string in `id`,
/// `channel_id`, `guild_id`, `webhook_id`, or a mention role fails the
/// decode. Fields Discord reserves for rarely used features are optional
/// here and default sensibly: tts False, mention_everyone False,
/// pinned False. Unknown fields are ignored.
pub fn decoder() -> d.Decoder(Message) {
  use id <- d.field("id", decode.snowflake_id(ids.message_id))
  use channel_id <- d.field("channel_id", decode.snowflake_id(ids.channel_id))
  use guild_id <- d.optional_field(
    "guild_id",
    None,
    d.optional(decode.snowflake_id(ids.guild_id)),
  )
  use author <- d.field("author", user.decoder())
  use content <- d.field("content", d.string)
  use timestamp <- d.field("timestamp", d.string)
  use edited_timestamp <- d.optional_field(
    "edited_timestamp",
    None,
    d.optional(d.string),
  )
  use tts <- d.optional_field("tts", False, d.bool)
  use mention_everyone <- d.optional_field("mention_everyone", False, d.bool)
  use mentions <- d.optional_field("mentions", [], d.list(user.decoder()))
  use mention_role_ids <- d.optional_field(
    "mention_roles",
    [],
    d.list(decode.snowflake_id(ids.role_id)),
  )
  use attachments <- d.optional_field(
    "attachments",
    [],
    d.list(attachment_decoder()),
  )
  use pinned <- d.optional_field("pinned", False, d.bool)
  use webhook_id <- d.optional_field(
    "webhook_id",
    None,
    d.optional(decode.snowflake_id(ids.webhook_id)),
  )
  use message_type <- d.optional_field("type", 0, d.int)
  d.success(Message(
    id: id,
    channel_id: channel_id,
    guild_id: guild_id,
    author: author,
    content: content,
    timestamp: timestamp,
    edited_timestamp: edited_timestamp,
    tts: tts,
    mention_everyone: mention_everyone,
    mentions: mentions,
    mention_role_ids: mention_role_ids,
    attachments: attachments,
    pinned: pinned,
    webhook_id: webhook_id,
    message_type: message_type,
  ))
}

/// Decoder for the partial message object MESSAGE_UPDATE carries: the
/// IDs are always present, every other field may be absent. Absent
/// fields read as None rather than falling back to a cached message —
/// merging old and new state is the caller's job, not the decoder's.
pub type MessageUpdate {
  MessageUpdate(
    id: MessageId,
    channel_id: ChannelId,
    content: Option(String),
    author: Option(User),
    edited_timestamp: Option(String),
    pinned: Option(Bool),
  )
}

/// Decoder for MESSAGE_UPDATE's `d`. Fails the same way as the full
/// message decoder when the payload is not JSON or an ID is not a
/// snowflake.
pub fn update_decoder() -> d.Decoder(MessageUpdate) {
  use id <- d.field("id", decode.snowflake_id(ids.message_id))
  use channel_id <- d.field("channel_id", decode.snowflake_id(ids.channel_id))
  use content <- d.optional_field("content", None, d.optional(d.string))
  use author <- d.optional_field("author", None, d.optional(user.decoder()))
  use edited_timestamp <- d.optional_field(
    "edited_timestamp",
    None,
    d.optional(d.string),
  )
  use pinned <- d.optional_field("pinned", None, d.optional(d.bool))
  d.success(MessageUpdate(
    id: id,
    channel_id: channel_id,
    content: content,
    author: author,
    edited_timestamp: edited_timestamp,
    pinned: pinned,
  ))
}

/// Decode a MESSAGE_CREATE payload: the message object, not a gateway
/// frame. Fails with error.DecodeFailed when the payload is not valid
/// JSON, a required field is missing or mistyped, or an ID is not a
/// snowflake. The error's `event` field stays None; wiring that knows
/// the event name fills it in.
pub fn from_json(payload: String) -> Result(Message, TadpoleError) {
  decode.from_json(None, payload, decoder())
}

/// Decode a MESSAGE_UPDATE payload: the partial message object, not a
/// gateway frame. Fails with error.DecodeFailed when the payload is not
/// valid JSON or one of the always-present IDs is not a snowflake.
pub fn update_from_json(
  payload: String,
) -> Result(MessageUpdate, TadpoleError) {
  decode.from_json(None, payload, update_decoder())
}

/// Attachment decoder, exposed for later modules that meet attachments
/// outside a message payload.
pub fn attachment_decoder() -> d.Decoder(Attachment) {
  use id <- d.optional_field("id", "", d.string)
  use filename <- d.optional_field("filename", "", d.string)
  use size <- d.optional_field("size", 0, d.int)
  use url <- d.optional_field("url", "", d.string)
  d.success(Attachment(id: id, filename: filename, size: size, url: url))
}
