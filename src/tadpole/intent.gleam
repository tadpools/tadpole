//// Gateway intents as a bitfield, with privileged-intent detection.
//// Discord sends only the event families you subscribe to, and the
//// subscription is this bitfield inside the IDENTIFY payload.
////
//// ## When you reach for this
////
//// Building the intents half of a tadpole config. Start empty with
//// `new`, switch bits on with `enable`; each intent is a variant, so
//// a typo'd intent is a compile error, not a silent wrong-event-family
//// bug.
////
//// ```gleam
//// import tadpole/intent
////
//// let intents =
////   intent.new()
////   |> intent.enable(intent.Guilds)
////   |> intent.enable(intent.GuildMessages)
////   |> intent.enable(intent.MessageContent)
//// ```
////
//// ## The privileged trio
////
//// Three bits sit behind toggles in the Developer Portal (Bot →
//// Privileged Gateway Intents), and requesting one without its toggle
//// ends the connection with close code 4014 the moment the bot
//// identifies:
////
//// - `intent.GuildMembers` — Server Members
//// - `intent.GuildPresences` — Presence
//// - `intent.MessageContent` — Message Content; without it, other
////   users' messages arrive with empty `content`
////
//// `check_privileged` lists which privileged variants a config
//// requests; tadpole refuses nothing — Discord does the enforcing,
//// after connect.
////
//// ## The wire
////
//// `to_int` produces the raw integer the IDENTIFY payload carries;
//// [`tadpole/gateway/shard`](gateway/shard.html) does exactly that when
//// it builds its ShardConfig. `intent_name` names one variant for logs
//// and rendered errors; `to_string` names them all, or "(none)".
////
//// Every function here is total bit arithmetic, so nothing fails at
//// runtime. The one failure is configurational — a privileged variant
//// without its portal toggle — and it surfaces as close 4014 after
//// connect, not as an error from this module.
////
//// ## See also
////
//// - [`tadpole`](../tadpole.html) — where intents land in the config
//// - [`tadpole/guide`](guide.html) — the portal-toggle walkthrough
//// - [`tadpole/error`](error.html) — `IntentsNotPrivileged`, the one related variant

import gleam/int
import gleam/list
import gleam/string

pub opaque type Intents {
  Intents(Int)
}

pub type Intent {
  Guilds
  GuildMembers
  GuildModeration
  GuildExpressions
  GuildIntegrations
  GuildWebhooks
  GuildInvites
  GuildVoiceStates
  GuildPresences
  GuildMessages
  GuildMessageReactions
  GuildMessageTyping
  DirectMessages
  DirectMessageReactions
  DirectMessageTyping
  MessageContent
  GuildScheduledEvents
  AutoModerationConfiguration
  AutoModerationExecution
  GuildMessagePolls
  DirectMessagePolls
}

pub const all = [
  Guilds,
  GuildMembers,
  GuildModeration,
  GuildExpressions,
  GuildIntegrations,
  GuildWebhooks,
  GuildInvites,
  GuildVoiceStates,
  GuildPresences,
  GuildMessages,
  GuildMessageReactions,
  GuildMessageTyping,
  DirectMessages,
  DirectMessageReactions,
  DirectMessageTyping,
  MessageContent,
  GuildScheduledEvents,
  AutoModerationConfiguration,
  AutoModerationExecution,
  GuildMessagePolls,
  DirectMessagePolls,
]

pub const privileged = [GuildMembers, GuildPresences, MessageContent]

pub fn new() -> Intents {
  Intents(0)
}

pub fn enable(intents: Intents, intent: Intent) -> Intents {
  let Intents(value) = intents
  Intents(int.bitwise_or(value, intent_to_bit(intent)))
}

// (value & bit) selects the enabled bits within the mask; XOR flips
// exactly those off and leaves everything else untouched.
pub fn disable(intents: Intents, intent: Intent) -> Intents {
  let Intents(value) = intents
  Intents(int.bitwise_exclusive_or(
    value,
    int.bitwise_and(value, intent_to_bit(intent)),
  ))
}

pub fn has(intents: Intents, intent: Intent) -> Bool {
  let Intents(value) = intents
  int.bitwise_and(value, intent_to_bit(intent)) != 0
}

pub fn enabled(intents: Intents) -> List(Intent) {
  list.filter(all, fn(bit) { has(intents, bit) })
}

pub fn is_privileged(intent: Intent) -> Bool {
  list.contains(privileged, intent)
}

/// Requesting these without the Developer Portal toggles ends in close
/// code 4014 at Identify.
pub fn check_privileged(intents: Intents) -> List(Intent) {
  list.filter(enabled(intents), is_privileged)
}

/// The raw integer sent in the Identify payload.
pub fn to_int(intents: Intents) -> Int {
  let Intents(value) = intents
  value
}

pub fn from_int(value: Int) -> Intents {
  Intents(value)
}

pub fn intent_name(intent: Intent) -> String {
  case intent {
    Guilds -> "GUILDS"
    GuildMembers -> "GUILD_MEMBERS"
    GuildModeration -> "GUILD_MODERATION"
    GuildExpressions -> "GUILD_EXPRESSIONS"
    GuildIntegrations -> "GUILD_INTEGRATIONS"
    GuildWebhooks -> "GUILD_WEBHOOKS"
    GuildInvites -> "GUILD_INVITES"
    GuildVoiceStates -> "GUILD_VOICE_STATES"
    GuildPresences -> "GUILD_PRESENCES"
    GuildMessages -> "GUILD_MESSAGES"
    GuildMessageReactions -> "GUILD_MESSAGE_REACTIONS"
    GuildMessageTyping -> "GUILD_MESSAGE_TYPING"
    DirectMessages -> "DIRECT_MESSAGES"
    DirectMessageReactions -> "DIRECT_MESSAGE_REACTIONS"
    DirectMessageTyping -> "DIRECT_MESSAGE_TYPING"
    MessageContent -> "MESSAGE_CONTENT"
    GuildScheduledEvents -> "GUILD_SCHEDULED_EVENTS"
    AutoModerationConfiguration -> "AUTO_MODERATION_CONFIGURATION"
    AutoModerationExecution -> "AUTO_MODERATION_EXECUTION"
    GuildMessagePolls -> "GUILD_MESSAGE_POLLS"
    DirectMessagePolls -> "DIRECT_MESSAGE_POLLS"
  }
}

pub fn to_string(intents: Intents) -> String {
  let Intents(value) = intents
  case value {
    0 -> "(none)"
    _ ->
      enabled(intents)
      |> list.map(intent_name)
      |> string.join(", ")
  }
}

fn intent_to_bit(intent: Intent) -> Int {
  case intent {
    Guilds -> 0x0001
    GuildMembers -> 0x0002
    GuildModeration -> 0x0004
    GuildExpressions -> 0x0008
    GuildIntegrations -> 0x0010
    GuildWebhooks -> 0x0020
    GuildInvites -> 0x0040
    GuildVoiceStates -> 0x0080
    GuildPresences -> 0x0100
    GuildMessages -> 0x0200
    GuildMessageReactions -> 0x0400
    GuildMessageTyping -> 0x0800
    DirectMessages -> 0x1000
    DirectMessageReactions -> 0x2000
    DirectMessageTyping -> 0x4000
    MessageContent -> 0x8000
    GuildScheduledEvents -> 0x10000
    AutoModerationConfiguration -> 0x100000
    AutoModerationExecution -> 0x200000
    GuildMessagePolls -> 0x1000000
    DirectMessagePolls -> 0x2000000
  }
}
