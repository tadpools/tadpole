//// Interaction model: the payload Discord sends when a user invokes a
//// slash command or component. Only the fields this milestone needs to
//// reply to an interaction are modeled; everything else lands as the raw
//// JSON on the event.
//// Stability: Experimental.
////
//// ## See also
////
//// - [`tadpole/gateway/events`](../gateway/events.html) the `InteractionCreate` event

import gleam/dynamic/decode as d
import gleam/option.{type Option, None}
import tadpole/model/decode
import tadpole/types/ids.{
  type ApplicationId, type ChannelId, type GuildId, type InteractionId,
  type UserId,
}

pub type InteractionData {
  InteractionData(name: String)
}

pub type Interaction {
  Interaction(
    id: InteractionId,
    application_id: ApplicationId,
    token: String,
    channel_id: Option(ChannelId),
    guild_id: Option(GuildId),
    user_id: Option(UserId),
    data: Option(InteractionData),
  )
}

pub fn data_decoder() -> d.Decoder(InteractionData) {
  use name <- d.field("name", d.string)
  d.success(InteractionData(name: name))
}

pub fn decoder() -> d.Decoder(Interaction) {
  use id <- d.field("id", decode.snowflake_id(ids.interaction_id))
  use application_id <- d.field(
    "application_id",
    decode.snowflake_id(ids.application_id),
  )
  use token <- d.field("token", d.string)
  use channel_id <- d.optional_field(
    "channel_id",
    None,
    d.optional(decode.snowflake_id(ids.channel_id)),
  )
  use guild_id <- d.optional_field(
    "guild_id",
    None,
    d.optional(decode.snowflake_id(ids.guild_id)),
  )
  use user_id <- d.optional_field(
    "user_id",
    None,
    d.optional(decode.snowflake_id(ids.user_id)),
  )
  use data <- d.optional_field("data", None, d.optional(data_decoder()))
  d.success(Interaction(
    id: id,
    application_id: application_id,
    token: token,
    channel_id: channel_id,
    guild_id: guild_id,
    user_id: user_id,
    data: data,
  ))
}
