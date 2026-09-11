//// Gateway event dispatch table: event name to category and required
//// intents. Unknown names fall through as unknown, never a crash.
////
//// ## When you reach for this
////
//// Through [`tadpole/gateway/events`](gateway/events.html) — the typed
//// event layer uses `category` to decide which decoder to run. Directly
//// when you need a specific event's required intent bits
//// (`required_intents`) or the full list of known event names
//// (`all_known_names`).
////
//// ## Internals
////
//// A lookup table plus `all_known_names`, so tests can pin every known
//// name against the real Discord list. The bits `required_intents` names
//// come from [`tadpole/intent`](intent.html).

import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

pub type Category {
  Lifecycle
  ChannelEvents
  GuildEvents
  MessageEvents
  InteractionEvents
  PresenceEvents
  AutoModerationEvents
  EntitlementEvents
  PollEvents
  VoiceEvents
  Other
}

/// Map a gateway event name to its category. Unknown names land in
/// `Other` — never a crash.
pub fn category(event_name: String) -> Category {
  case event_name {
    "READY" -> Lifecycle
    "RESUMED" -> Lifecycle

    "CHANNEL_CREATE" -> ChannelEvents
    "CHANNEL_UPDATE" -> ChannelEvents
    "CHANNEL_DELETE" -> ChannelEvents
    "CHANNEL_PINS_UPDATE" -> ChannelEvents
    "THREAD_CREATE" -> ChannelEvents
    "THREAD_UPDATE" -> ChannelEvents
    "THREAD_DELETE" -> ChannelEvents
    "THREAD_LIST_SYNC" -> ChannelEvents
    "THREAD_MEMBER_UPDATE" -> ChannelEvents
    "THREAD_MEMBERS_UPDATE" -> ChannelEvents
    "STAGE_INSTANCE_CREATE" -> ChannelEvents
    "STAGE_INSTANCE_UPDATE" -> ChannelEvents
    "STAGE_INSTANCE_DELETE" -> ChannelEvents

    "GUILD_CREATE" -> GuildEvents
    "GUILD_UPDATE" -> GuildEvents
    "GUILD_DELETE" -> GuildEvents
    "GUILD_BAN_ADD" -> GuildEvents
    "GUILD_BAN_REMOVE" -> GuildEvents
    "GUILD_EMOJIS_UPDATE" -> GuildEvents
    "GUILD_STICKERS_UPDATE" -> GuildEvents
    "GUILD_INTEGRATIONS_UPDATE" -> GuildEvents
    "GUILD_MEMBER_ADD" -> GuildEvents
    "GUILD_MEMBER_REMOVE" -> GuildEvents
    "GUILD_MEMBER_UPDATE" -> GuildEvents
    "GUILD_MEMBERS_CHUNK" -> GuildEvents
    "GUILD_ROLE_CREATE" -> GuildEvents
    "GUILD_ROLE_UPDATE" -> GuildEvents
    "GUILD_ROLE_DELETE" -> GuildEvents
    "GUILD_SCHEDULED_EVENT_CREATE" -> GuildEvents
    "GUILD_SCHEDULED_EVENT_UPDATE" -> GuildEvents
    "GUILD_SCHEDULED_EVENT_DELETE" -> GuildEvents
    "GUILD_SCHEDULED_EVENT_USER_ADD" -> GuildEvents
    "GUILD_SCHEDULED_EVENT_USER_REMOVE" -> GuildEvents
    "GUILD_SOUNDBOARD_SOUND_CREATE" -> GuildEvents
    "GUILD_SOUNDBOARD_SOUND_UPDATE" -> GuildEvents
    "GUILD_SOUNDBOARD_SOUND_DELETE" -> GuildEvents
    "GUILD_SOUNDBOARD_SOUNDS_UPDATE" -> GuildEvents
    "WEBHOOKS_UPDATE" -> GuildEvents

    "MESSAGE_CREATE" -> MessageEvents
    "MESSAGE_UPDATE" -> MessageEvents
    "MESSAGE_DELETE" -> MessageEvents
    "MESSAGE_DELETE_BULK" -> MessageEvents
    "MESSAGE_REACTION_ADD" -> MessageEvents
    "MESSAGE_REACTION_REMOVE" -> MessageEvents
    "MESSAGE_REACTION_REMOVE_ALL" -> MessageEvents
    "MESSAGE_REACTION_REMOVE_EMOJI" -> MessageEvents

    "INTERACTION_CREATE" -> InteractionEvents
    "APPLICATION_COMMAND_PERMISSIONS_UPDATE" -> InteractionEvents

    "PRESENCE_UPDATE" -> PresenceEvents
    "USER_UPDATE" -> PresenceEvents
    "TYPING_START" -> PresenceEvents

    "AUTO_MODERATION_RULE_CREATE" -> AutoModerationEvents
    "AUTO_MODERATION_RULE_UPDATE" -> AutoModerationEvents
    "AUTO_MODERATION_RULE_DELETE" -> AutoModerationEvents
    "AUTO_MODERATION_ACTION_EXECUTION" -> AutoModerationEvents

    "ENTITLEMENT_CREATE" -> EntitlementEvents
    "ENTITLEMENT_UPDATE" -> EntitlementEvents
    "ENTITLEMENT_DELETE" -> EntitlementEvents
    "SUBSCRIPTION_CREATE" -> EntitlementEvents
    "SUBSCRIPTION_UPDATE" -> EntitlementEvents
    "SUBSCRIPTION_DELETE" -> EntitlementEvents

    "MESSAGE_POLL_VOTE_ADD" -> PollEvents
    "MESSAGE_POLL_VOTE_REMOVE" -> PollEvents

    "VOICE_STATE_UPDATE" -> VoiceEvents
    "VOICE_CHANNEL_STATUS_UPDATE" -> VoiceEvents
    "VOICE_SERVER_UPDATE" -> VoiceEvents

    _ -> Other
  }
}

/// True when the event name appears in this table — the shard can
/// decode it. Unknown names are not errors; they land in `Other`.
pub fn is_known(event_name: String) -> Bool {
  category(event_name) != Other
}

/// Intent bits Discord requires before it will send this event.
pub fn required_intents(event_name: String) -> List(Int) {
  case category(event_name) {
    Lifecycle -> []
    ChannelEvents -> [intent_guilds]
    GuildEvents -> [intent_guilds]
    MessageEvents -> [intent_guilds, intent_guild_messages]
    InteractionEvents -> [intent_guilds]
    PresenceEvents -> [intent_guilds]
    AutoModerationEvents -> [intent_auto_mod_config]
    EntitlementEvents -> [intent_guilds]
    PollEvents -> [intent_guilds, intent_guild_messages]
    VoiceEvents -> [intent_guilds, intent_voice_states]
    Other -> []
  }
}

// Same values as tadpole/intent; local to avoid a dependency cycle.
const intent_guilds = 0x0001

const intent_guild_messages = 0x0200

const intent_voice_states = 0x0080

const intent_auto_mod_config = 0x100000

/// Every event name known to this table. Exists so tests can iterate.
pub fn all_known_names() -> List(String) {
  [
    "READY", "RESUMED", "CHANNEL_CREATE", "CHANNEL_UPDATE", "CHANNEL_DELETE",
    "CHANNEL_PINS_UPDATE", "THREAD_CREATE", "THREAD_UPDATE", "THREAD_DELETE",
    "THREAD_LIST_SYNC", "THREAD_MEMBER_UPDATE", "THREAD_MEMBERS_UPDATE",
    "STAGE_INSTANCE_CREATE", "STAGE_INSTANCE_UPDATE", "STAGE_INSTANCE_DELETE",
    "GUILD_CREATE", "GUILD_UPDATE", "GUILD_DELETE", "GUILD_BAN_ADD",
    "GUILD_BAN_REMOVE", "GUILD_EMOJIS_UPDATE", "GUILD_STICKERS_UPDATE",
    "GUILD_INTEGRATIONS_UPDATE", "GUILD_MEMBER_ADD", "GUILD_MEMBER_REMOVE",
    "GUILD_MEMBER_UPDATE", "GUILD_MEMBERS_CHUNK", "GUILD_ROLE_CREATE",
    "GUILD_ROLE_UPDATE", "GUILD_ROLE_DELETE", "GUILD_SCHEDULED_EVENT_CREATE",
    "GUILD_SCHEDULED_EVENT_UPDATE", "GUILD_SCHEDULED_EVENT_DELETE",
    "GUILD_SCHEDULED_EVENT_USER_ADD", "GUILD_SCHEDULED_EVENT_USER_REMOVE",
    "GUILD_SOUNDBOARD_SOUND_CREATE", "GUILD_SOUNDBOARD_SOUND_UPDATE",
    "GUILD_SOUNDBOARD_SOUND_DELETE", "GUILD_SOUNDBOARD_SOUNDS_UPDATE",
    "WEBHOOKS_UPDATE", "MESSAGE_CREATE", "MESSAGE_UPDATE", "MESSAGE_DELETE",
    "MESSAGE_DELETE_BULK", "MESSAGE_REACTION_ADD", "MESSAGE_REACTION_REMOVE",
    "MESSAGE_REACTION_REMOVE_ALL", "MESSAGE_REACTION_REMOVE_EMOJI",
    "INTERACTION_CREATE", "APPLICATION_COMMAND_PERMISSIONS_UPDATE",
    "PRESENCE_UPDATE", "USER_UPDATE", "TYPING_START",
    "AUTO_MODERATION_RULE_CREATE", "AUTO_MODERATION_RULE_UPDATE",
    "AUTO_MODERATION_RULE_DELETE", "AUTO_MODERATION_ACTION_EXECUTION",
    "ENTITLEMENT_CREATE", "ENTITLEMENT_UPDATE", "ENTITLEMENT_DELETE",
    "SUBSCRIPTION_CREATE", "SUBSCRIPTION_UPDATE", "SUBSCRIPTION_DELETE",
    "MESSAGE_POLL_VOTE_ADD", "MESSAGE_POLL_VOTE_REMOVE", "VOICE_STATE_UPDATE",
    "VOICE_CHANNEL_STATUS_UPDATE", "VOICE_SERVER_UPDATE",
  ]
}

/// Set of every known event name, for fast membership checks.
pub fn names_set() -> Set(String) {
  set.from_list(all_known_names())
}

/// The event's category if it is in this table, None otherwise.
pub fn maybe_known(event_name: String) -> Option(Category) {
  case is_known(event_name) {
    True -> Some(category(event_name))
    False -> None
  }
}
