//// Typed gateway events: the `Event` type a handler receives, one
//// variant per modeled Discord event plus `Unknown` for everything
//// else. `decode` maps a dispatch frame's name + raw payload to one
//// variant; anything tadpole does not model yet lands in `Unknown` with
//// the raw payload intact, so new Discord events degrade to data
//// instead of crashing a bot.
//// Stability: Growing.
////
//// ## When you reach for this
////
//// Indirectly, always: [`tadpole/bot`](../bot.html) delivers these to
//// your handler, and matching on the variants is how a bot reacts to
//// anything. Directly, when testing decoders or replaying captured
//// payloads: `decode` takes the event name and the raw frame JSON.
////
//// ## Variant to Discord event
////
//// | Variant | Discord event | What it carries, when it fires |
//// | --- | --- | --- |
//// | `Ready(user, guild_count)` | READY | the bot's own user; `guild_count` counts the guilds READY listed, which arrive as `GuildCreate` moments later |
//// | `MessageCreate(message)` | MESSAGE_CREATE | the full message object |
//// | `MessageUpdate(update)` | MESSAGE_UPDATE | the PARTIAL message: ids always present, other fields may be absent — see [`tadpole/model/message`](../model/message.html)'s `update_decoder` |
//// | `MessageDelete(id, channel_id, guild_id)` | MESSAGE_DELETE | ids only; `guild_id` is `None` in DMs |
//// | `Resumed` | RESUMED | no payload modeled: RESUMED's `d` is a trace list |
//// | `GuildCreate(guild)` | GUILD_CREATE | the full guild object |
//// | `GuildDelete(unavailable)` | GUILD_DELETE | the `unavailable: true` stub — only the id is guaranteed |
//// | `Unknown(name, raw)` | any other name | the event name and the raw frame JSON, untouched |
////
//// ## Nothing here crashes a bot
////
//// - Any name tadpole does not model — new Discord events included —
////   decodes to `Unknown` and `decode` succeeds. Known events this
////   slice does not model are also data, not errors.
//// - A modeled event whose payload no longer matches decodes to
////   `Error(DecodeFailed)` from `decode` — but the shard never forwards
////   that failure. It converts it to `Unknown(name, raw)` and keeps
////   running, so a handler sees `Unknown`, never a decode error.
//// - `decode` is public for direct callers (tests, replay tools), who
////   get the failure honestly instead: `DecodeFailed` names the event
////   and the JSON path, and only fires for the six modeled events —
////   `Resumed` and every unmodeled name cannot fail.
////
//// ## Example
////
//// ```gleam
//// import tadpole/gateway/events
////
//// fn describe(event: events.Event) -> String {
////   case event {
////     events.MessageCreate(message) -> message.content
////     events.Unknown(name, _raw) -> "unmodeled: " <> name
////     _ -> ""
////   }
//// }
//// ```
////
//// ## See also
////
//// - [`tadpole/bot`](../bot.html) — where events are delivered
//// - [`tadpole/model/message`](../model/message.html) — the two message shapes behind MESSAGE_CREATE/UPDATE
//// - [`tadpole/gateway/shard`](shard.html) — the actor that decodes and forwards

import gleam/dynamic/decode as d
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import tadpole/error.{type TadpoleError, DecodeFailed}
import tadpole/model/decode
import tadpole/model/guild.{type Guild, type UnavailableGuild}
import tadpole/model/message.{type Message, type MessageUpdate}
import tadpole/model/user.{type User}
import tadpole/types/ids.{type ChannelId, type GuildId, type MessageId}

pub type Event {
  /// The bot's own user plus how many guilds READY listed. Those guilds
  /// arrive as GUILD_CREATE moments later; until then they are
  /// unavailable.
  Ready(ready_user: User, guild_count: Int)
  /// MESSAGE_CREATE: a new message, decoded to the full model.
  MessageCreate(message: Message)
  /// MESSAGE_UPDATE: the partial payload — ids always present, most
  /// fields may be absent. See tadpole/model/message's MessageUpdate.
  MessageUpdate(update: MessageUpdate)
  /// MESSAGE_DELETE: ids only, no content. guild_id is None for DMs.
  MessageDelete(id: MessageId, channel_id: ChannelId, guild_id: Option(GuildId))
  /// RESUMED: the session resumed and replayed missed events. No payload
  /// worth modeling: RESUMED's `d` is a trace list.
  Resumed
  /// GUILD_CREATE: a guild the bot can see, delivered per guild after
  /// READY (and again on outages resolving).
  GuildCreate(guild: Guild)
  /// GUILD_DELETE: the payload shape is the `unavailable: true` object
  /// GUILD_DELETE carries; only the guild id is guaranteed.
  GuildDelete(unavailable: UnavailableGuild)
  /// Any event this version does not model, known or not. Name and raw
  /// payload are kept so callers can log, count, or hand-off; nothing
  /// here is ever a crash.
  Unknown(name: String, raw: String)
}

/// Decode one dispatched gateway event. `payload` is the full frame JSON
/// as `frame.parse` saw it — envelope and all, `d` included — because the
/// shard never re-parses.
///
/// Modeled events decode to their variant and fail with DecodeFailed
/// (event filled in) when Discord's payload does not match. Every other
/// name — including known events this slice does not model — decodes to
/// `Unknown` and never fails. RESUMED never fails either: it carries no
/// data, so any payload is accepted.
pub fn decode(
  event_name: String,
  payload: String,
) -> Result(Event, TadpoleError) {
  case event_name {
    "READY" -> decode_ready(payload)
    "MESSAGE_CREATE" ->
      case message.from_json(payload) {
        Ok(message) -> Ok(MessageCreate(message))
        Error(e) -> Error(with_event(event_name, e))
      }
    "MESSAGE_UPDATE" ->
      case message.update_from_json(payload) {
        Ok(update) -> Ok(MessageUpdate(update))
        Error(e) -> Error(with_event(event_name, e))
      }
    "MESSAGE_DELETE" -> decode_message_delete(payload)
    "RESUMED" -> Ok(Resumed)
    "GUILD_CREATE" ->
      case guild.from_json(payload) {
        Ok(guild) -> Ok(GuildCreate(guild))
        Error(e) -> Error(with_event(event_name, e))
      }
    "GUILD_DELETE" ->
      decode.from_json(Some(event_name), payload, guild.unavailable_decoder())
      |> result.map(GuildDelete)
    _ -> Ok(Unknown(name: event_name, raw: payload))
  }
}

/// Fill the event name into a model-level DecodeFailed so the rendered
/// error says MESSAGE_CREATE instead of "somewhere in a payload".
fn with_event(event: String, e: TadpoleError) -> TadpoleError {
  case e {
    DecodeFailed(_, path, expected, got) ->
      DecodeFailed(Some(event), path, expected, got)
    other -> other
  }
}

fn decode_ready(payload: String) -> Result(Event, TadpoleError) {
  let decoder = {
    use ready_user <- d.field("user", user.decoder())
    use guilds <- d.field("guilds", d.list(guild.unavailable_decoder()))
    d.success(#(ready_user, guilds))
  }

  case decode.from_json(Some("READY"), payload, decoder) {
    Ok(#(ready_user, guilds)) -> Ok(Ready(ready_user, list.length(guilds)))
    Error(e) -> Error(e)
  }
}

fn decode_message_delete(payload: String) -> Result(Event, TadpoleError) {
  let decoder = {
    use id <- d.field("id", decode.snowflake_id(ids.message_id))
    use channel_id <- d.field("channel_id", decode.snowflake_id(ids.channel_id))
    use guild_id <- d.optional_field(
      "guild_id",
      None,
      d.optional(decode.snowflake_id(ids.guild_id)),
    )
    d.success(MessageDelete(id: id, channel_id: channel_id, guild_id: guild_id))
  }

  decode.from_json(Some("MESSAGE_DELETE"), payload, decoder)
}
