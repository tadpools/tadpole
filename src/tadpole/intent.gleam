//// Gateway intents as a bitfield, with privileged-intent detection.
//// Discord sends only the event families you subscribe to, and the
//// subscription is this bitfield inside the IDENTIFY payload.
////
//// ## When you reach for this
////
//// Building the intents half of a tadpole config. Start empty with
//// `new`, switch bits on with `enable`; the value is opaque, so a
//// typo'd integer cannot reach Discord through it.
////
//// ```gleam
//// import tadpole/intent
////
//// let intents =
////   intent.new()
////   |> intent.enable(intent.guilds)
////   |> intent.enable(intent.guild_messages)
////   |> intent.enable(intent.message_content)
//// ```
////
//// ## The privileged trio
////
//// Three bits sit behind toggles in the Developer Portal (Bot →
//// Privileged Gateway Intents), and requesting one without its toggle
//// ends the connection with close code 4014 the moment the bot
//// identifies:
////
//// - `intent.guild_members` — Server Members
//// - `intent.guild_presences` — Presence
//// - `intent.message_content` — Message Content; without it, other
////   users' messages arrive with empty `content`
////
//// `check_privileged` lists which privileged bits a config requests;
//// tadpole refuses nothing — Discord does the enforcing, after connect.
//// The guide's "Privileged intents" section has the whole story.
////
//// ## The wire
////
//// `to_int` produces the raw integer the IDENTIFY payload carries;
//// [`tadpole/gateway/shard`](gateway/shard.html) does exactly that when
//// it builds its ShardConfig. `intent_name` names one bit for logs and
//// rendered errors; `to_string` names them all, or "(none)".
////
//// Every function here is total bit arithmetic, so nothing fails at
//// runtime. The one failure is configurational — a privileged bit
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

pub const guilds = 0x0001

pub const guild_members = 0x0002

pub const guild_moderation = 0x0004

pub const guild_expressions = 0x0008

pub const guild_integrations = 0x0010

pub const guild_webhooks = 0x0020

pub const guild_invites = 0x0040

pub const guild_voice_states = 0x0080

pub const guild_presences = 0x0100

pub const guild_messages = 0x0200

pub const guild_message_reactions = 0x0400

pub const guild_message_typing = 0x0800

pub const direct_messages = 0x1000

pub const direct_message_reactions = 0x2000

pub const direct_message_typing = 0x4000

pub const message_content = 0x8000

pub const guild_scheduled_events = 0x10000

pub const auto_moderation_configuration = 0x100000

pub const auto_moderation_execution = 0x200000

pub const guild_message_polls = 0x1000000

pub const direct_message_polls = 0x2000000

pub const privileged = [guild_members, guild_presences, message_content]

pub const all = [
  guilds, guild_members, guild_moderation, guild_expressions, guild_integrations,
  guild_webhooks, guild_invites, guild_voice_states, guild_presences,
  guild_messages, guild_message_reactions, guild_message_typing, direct_messages,
  direct_message_reactions, direct_message_typing, message_content,
  guild_scheduled_events, auto_moderation_configuration,
  auto_moderation_execution, guild_message_polls, direct_message_polls,
]

pub fn new() -> Intents {
  Intents(0)
}

pub fn enable(intents: Intents, intent: Int) -> Intents {
  let Intents(value) = intents
  Intents(int.bitwise_or(value, intent))
}

// (value & intent) selects the enabled bits within the mask; XOR flips
// exactly those off and leaves everything else untouched.
pub fn disable(intents: Intents, intent: Int) -> Intents {
  let Intents(value) = intents
  Intents(int.bitwise_exclusive_or(value, int.bitwise_and(value, intent)))
}

pub fn has(intents: Intents, intent: Int) -> Bool {
  let Intents(value) = intents
  int.bitwise_and(value, intent) != 0
}

pub fn enabled(intents: Intents) -> List(Int) {
  list.filter(all, fn(bit) { has(intents, bit) })
}

pub fn is_privileged(intent: Int) -> Bool {
  list.contains(privileged, intent)
}

/// Requesting these without the Developer Portal toggles ends in close
/// code 4014 at Identify.
pub fn check_privileged(intents: Intents) -> List(Int) {
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

pub fn intent_name(intent: Int) -> String {
  case intent {
    b if b == guilds -> "GUILDS"
    b if b == guild_members -> "GUILD_MEMBERS"
    b if b == guild_moderation -> "GUILD_MODERATION"
    b if b == guild_expressions -> "GUILD_EXPRESSIONS"
    b if b == guild_integrations -> "GUILD_INTEGRATIONS"
    b if b == guild_webhooks -> "GUILD_WEBHOOKS"
    b if b == guild_invites -> "GUILD_INVITES"
    b if b == guild_voice_states -> "GUILD_VOICE_STATES"
    b if b == guild_presences -> "GUILD_PRESENCES"
    b if b == guild_messages -> "GUILD_MESSAGES"
    b if b == guild_message_reactions -> "GUILD_MESSAGE_REACTIONS"
    b if b == guild_message_typing -> "GUILD_MESSAGE_TYPING"
    b if b == direct_messages -> "DIRECT_MESSAGES"
    b if b == direct_message_reactions -> "DIRECT_MESSAGE_REACTIONS"
    b if b == direct_message_typing -> "DIRECT_MESSAGE_TYPING"
    b if b == message_content -> "MESSAGE_CONTENT"
    b if b == guild_scheduled_events -> "GUILD_SCHEDULED_EVENTS"
    b if b == auto_moderation_configuration -> "AUTO_MODERATION_CONFIGURATION"
    b if b == auto_moderation_execution -> "AUTO_MODERATION_EXECUTION"
    b if b == guild_message_polls -> "GUILD_MESSAGE_POLLS"
    b if b == direct_message_polls -> "DIRECT_MESSAGE_POLLS"
    _ -> "UNKNOWN(" <> int.to_string(intent) <> ")"
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
