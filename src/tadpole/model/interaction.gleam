//// Interaction model: the payload Discord sends when a user invokes a
//// slash command or component. Only the fields this milestone needs to
//// reply to an interaction are modeled; everything else lands as the raw
//// JSON on the event.
//// Stability: Experimental.

import gleam/dynamic/decode as d
import gleam/option.{type Option, None, Some}
import tadpole/model/decode
import tadpole/types/ids.{
  type ApplicationId, type ChannelId, type GuildId, type InteractionId,
  type UserId,
}

pub type InteractionType {
  Ping
  ApplicationCommand
  MessageComponent
  ApplicationCommandAutocomplete
  ModalSubmit
  UnknownInteractionType(Int)
}

pub fn interaction_type_from_int(value: Int) -> InteractionType {
  case value {
    1 -> Ping
    2 -> ApplicationCommand
    3 -> MessageComponent
    4 -> ApplicationCommandAutocomplete
    5 -> ModalSubmit
    _ -> UnknownInteractionType(value)
  }
}

pub type InteractionOption {
  InteractionOption(name: String, value: d.Dynamic)
}

pub type InteractionData {
  InteractionData(name: String, options: List(InteractionOption))
}

pub type Interaction {
  Interaction(
    id: InteractionId,
    application_id: ApplicationId,
    interaction_type: InteractionType,
    token: String,
    channel_id: Option(ChannelId),
    guild_id: Option(GuildId),
    user_id: Option(UserId),
    data: Option(InteractionData),
  )
}

fn option_decoder() -> d.Decoder(InteractionOption) {
  use name <- d.field("name", d.string)
  use value <- d.field("value", d.dynamic)
  d.success(InteractionOption(name: name, value: value))
}

fn data_decoder() -> d.Decoder(InteractionData) {
  use name <- d.field("name", d.string)
  use options <- d.optional_field("options", [], d.list(option_decoder()))
  d.success(InteractionData(name: name, options: options))
}

pub fn decoder() -> d.Decoder(Interaction) {
  use id <- d.field("id", decode.snowflake_id(ids.interaction_id))
  use application_id <- d.field(
    "application_id",
    decode.snowflake_id(ids.application_id),
  )
  use interaction_type <- d.field("type", d.int)
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
  use direct_user <- d.optional_field(
    "user",
    None,
    d.optional(d.at(["id"], decode.snowflake_id(ids.user_id))),
  )
  use member_user <- d.optional_field(
    "member",
    None,
    d.optional(d.at(["user", "id"], decode.snowflake_id(ids.user_id))),
  )
  let user_id = case direct_user {
    Some(_) -> direct_user
    None -> member_user
  }
  use data <- d.optional_field("data", None, d.optional(data_decoder()))
  d.success(Interaction(
    id: id,
    application_id: application_id,
    interaction_type: interaction_type_from_int(interaction_type),
    token: token,
    channel_id: channel_id,
    guild_id: guild_id,
    user_id: user_id,
    data: data,
  ))
}
