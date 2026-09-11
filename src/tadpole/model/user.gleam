//// The Discord user object, trimmed to what a bot reads out of events.
//// No discriminator field: modern accounts do not have one and Discord
//// stopped sending it. global_name is the display name Discord keeps now.
////
//// ## When you reach for this
////
//// Through [`tadpole/gateway/events`](../gateway/events.html) as
//// `message.author`, `Ready`'s user, and mention entries; a bare user
//// also comes from `endpoints.get_current_user`. `global_name` is `None`
//// until the user sets a display name, and `avatar` is Discord's avatar
//// hash — not a URL — with `None` meaning the default avatar. `bot` and
//// `system` default to False: Discord omits both for ordinary users.

import gleam/dynamic/decode as d
import gleam/option.{type Option, None}
import tadpole/error.{type TadpoleError}
import tadpole/model/decode
import tadpole/types/ids.{type UserId}

pub type User {
  User(
    id: UserId,
    username: String,
    /// Display name; null in Discord's payload until the user sets one.
    global_name: Option(String),
    /// Discord's avatar hash, not a URL. None means the default avatar.
    avatar: Option(String),
    bot: Bool,
    system: Bool,
  )
}

/// Decoder for Discord's user object. Discord omits `bot` and `system`
/// for ordinary users, so both default to False when absent; `global_name`
/// and `avatar` can arrive as null as well as absent, and both read as
/// None either way. Unknown fields are ignored.
pub fn decoder() -> d.Decoder(User) {
  use id <- d.field("id", decode.snowflake_id(ids.user_id))
  use username <- d.field("username", d.string)
  use global_name <- d.optional_field("global_name", None, d.optional(d.string))
  use avatar <- d.optional_field("avatar", None, d.optional(d.string))
  use bot <- d.optional_field("bot", False, d.bool)
  use system <- d.optional_field("system", False, d.bool)
  d.success(User(
    id: id,
    username: username,
    global_name: global_name,
    avatar: avatar,
    bot: bot,
    system: system,
  ))
}

/// Decode a user from its JSON payload: the user object itself, not a
/// gateway frame. Fails with error.DecodeFailed when the payload is not
/// valid JSON, a required field is missing or mistyped, or the `id` is
/// not a snowflake. The error's `event` field stays None; wiring that
/// knows the event name fills it in.
pub fn from_json(payload: String) -> Result(User, TadpoleError) {
  decode.from_json(None, payload, decoder())
}
