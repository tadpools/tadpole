//// The Discord channel object, trimmed to what the first slice reads.
//// `type` is reserved in Gleam, so Discord's key lands as channel_type.
////
//// Option fields mean Discord omits or nulls them for some channel
//// kinds: `name` and `guild_id` are `None` for DMs and group DMs (which
//// have no name and no guild), and `topic` is null in most non-text
//// channels. `last_message_id` is a pointer to the most recent message
//// and deliberately a String, not a typed ID: tadpole never
//// dereferences it, so snowflake validation would only add a failure
//// mode. `channel_type` stays Discord's raw integer (0 GUILD_TEXT,
//// 1 DM, 2 GUILD_VOICE, ...) for the same reason message_type does —
//// Discord adds channel types faster than libraries track them.

import gleam/dynamic/decode as d
import gleam/option.{type Option, None}
import tadpole/error.{type TadpoleError}
import tadpole/model/decode
import tadpole/types/ids.{type ChannelId, type GuildId}

pub type Channel {
  Channel(
    id: ChannelId,
    /// Discord's raw channel type integer: 0 GUILD_TEXT, 1 DM,
    /// 2 GUILD_VOICE, and so on. Kept raw for the same reason message
    /// types are: Discord adds them faster than libraries track them.
    channel_type: Int,
    /// None for DMs and group DMs.
    name: Option(String),
    /// None for DMs and group DMs, which have no guild to belong to.
    guild_id: Option(GuildId),
    /// The channel topic; null in most non-text channels.
    topic: Option(String),
    /// Deliberately String, not a typed ID: it is an informational
    /// pointer to the most recent message and is never dereferenced
    /// here, so snowflake validation would only add a failure mode.
    last_message_id: Option(String),
  )
}

/// Decoder for Discord's channel object. Discord sends IDs as strings;
/// a non-snowflake string in `id` or `guild_id` fails the decode.
/// Unknown fields are ignored.
pub fn decoder() -> d.Decoder(Channel) {
  use id <- d.field("id", decode.snowflake_id(ids.channel_id))
  use channel_type <- d.optional_field("type", 0, d.int)
  use name <- d.optional_field("name", None, d.optional(d.string))
  use guild_id <- d.optional_field(
    "guild_id",
    None,
    d.optional(decode.snowflake_id(ids.guild_id)),
  )
  use topic <- d.optional_field("topic", None, d.optional(d.string))
  use last_message_id <- d.optional_field(
    "last_message_id",
    None,
    d.optional(d.string),
  )
  d.success(Channel(
    id: id,
    channel_type: channel_type,
    name: name,
    guild_id: guild_id,
    topic: topic,
    last_message_id: last_message_id,
  ))
}

/// Decode a channel from its JSON payload: the channel object, not a
/// gateway frame. Fails with error.DecodeFailed when the payload is not
/// valid JSON or an ID is not a snowflake. The error's `event` field
/// stays None; wiring that knows the event name fills it in.
pub fn from_json(payload: String) -> Result(Channel, TadpoleError) {
  decode.from_json(None, payload, decoder())
}
