//// The Discord guild (server) object, trimmed to identification. Guild
//// payloads are enormous and vary by endpoint; later milestones widen
//// this record as REST wiring needs more of it.
////
//// ## When you reach for this
////
//// Through [`tadpole/gateway/events`](../gateway/events.html) as
//// `GuildCreate`'s payload (the full `Guild`) and `Ready`'s `guilds`
//// array (`UnavailableGuild`). A guild from `endpoints` is the same
//// `Guild` record.
////
//// ## Two records for two payloads:
////
//// - `Guild` — what GUILD_CREATE carries (see
////   [`tadpole/gateway/events`](../gateway/events.html)). `member_count`
////   is `Option` because payloads that omit the count — READY's stub
////   entries, for one — still decode; `name` defaults to "" when
////   Discord omits it rather than failing the whole event.
//// - `UnavailableGuild` — one entry of READY's `guilds` array or the
////   object GUILD_DELETE carries: a guild the bot has no live view of
////   yet (a technical outage, in Discord's vocabulary). Only the id is
////   guaranteed. The `unavailable` flag itself is not modeled —
////   everything in that position means the same thing.

import gleam/dynamic/decode as d
import gleam/option.{type Option, None}
import tadpole/error.{type TadpoleError}
import tadpole/model/decode
import tadpole/types/ids.{type GuildId}

pub type Guild {
  Guild(
    id: GuildId,
    name: String,
    /// None in payloads that omit the count, such as unavailable guilds
    /// arriving through READY.
    member_count: Option(Int),
  )
}

/// Guild on a READY payload that the bot has not received GUILD_CREATE
/// for yet (a technical outage). Only the id is guaranteed; everything
/// else waits for the real GUILD_CREATE.
pub type UnavailableGuild {
  UnavailableGuild(id: GuildId)
}

/// Decoder for Discord's guild object. Discord sends IDs as strings; a
/// non-snowflake string in `id` fails the decode. Unknown fields are
/// ignored.
pub fn decoder() -> d.Decoder(Guild) {
  use id <- d.field("id", decode.snowflake_id(ids.guild_id))
  use name <- d.optional_field("name", "", d.string)
  use member_count <- d.optional_field("member_count", None, d.optional(d.int))
  d.success(Guild(id: id, name: name, member_count: member_count))
}

/// Decoder for one entry in READY's `guilds` array. `unavailable` may be
/// absent, so it is not modeled as a field — everything READY lists here
/// starts unavailable until GUILD_CREATE lands.
pub fn unavailable_decoder() -> d.Decoder(UnavailableGuild) {
  use id <- d.field("id", decode.snowflake_id(ids.guild_id))
  d.success(UnavailableGuild(id: id))
}

/// Decode a guild from its JSON payload: the guild object, not a gateway
/// frame. Fails with error.DecodeFailed when the payload is not valid
/// JSON or the `id` is not a snowflake. The error's `event` field stays
/// None; wiring that knows the event name fills it in.
pub fn from_json(payload: String) -> Result(Guild, TadpoleError) {
  decode.from_json(None, payload, decoder())
}

/// Decode one entry of READY's `guilds` array. Fails with
/// error.DecodeFailed when the payload is not valid JSON or the `id` is
/// not a snowflake.
pub fn unavailable_from_json(
  payload: String,
) -> Result(UnavailableGuild, TadpoleError) {
  decode.from_json(None, payload, unavailable_decoder())
}
