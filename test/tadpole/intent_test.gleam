//// Tests for the intent bitfield.

import gleam/list
import gleeunit/should
import tadpole/intent

pub fn new_is_empty_test() {
  let intents = intent.new()
  intent.has(intents, intent.Guilds) |> should.be_false
  intent.has(intents, intent.GuildMessages) |> should.be_false
  intent.has(intents, intent.MessageContent) |> should.be_false
}

pub fn enable_adds_intent_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.GuildMessages)

  intent.has(intents, intent.Guilds) |> should.be_true
  intent.has(intents, intent.GuildMessages) |> should.be_true
  intent.has(intents, intent.GuildMembers) |> should.be_false
}

pub fn enable_is_idempotent_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.Guilds)

  intent.has(intents, intent.Guilds) |> should.be_true
  intent.enabled(intents) |> list.length |> should.equal(1)
}

pub fn disable_removes_intent_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.GuildMessages)
    |> intent.disable(intent.Guilds)

  intent.has(intents, intent.Guilds) |> should.be_false
  intent.has(intents, intent.GuildMessages) |> should.be_true
}

pub fn disable_is_idempotent_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.disable(intent.Guilds)
    |> intent.disable(intent.Guilds)

  intent.has(intents, intent.Guilds) |> should.be_false
}

pub fn enabled_lists_exactly_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.GuildMessages)
    |> intent.enable(intent.GuildMembers)

  let enabled = intent.enabled(intents)
  list.length(enabled) |> should.equal(3)
  list.contains(enabled, intent.Guilds) |> should.be_true
  list.contains(enabled, intent.GuildMessages) |> should.be_true
  list.contains(enabled, intent.GuildMembers) |> should.be_true
  list.contains(enabled, intent.GuildModeration) |> should.be_false
}

pub fn to_int_roundtrip_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.GuildMessages)
    |> intent.enable(intent.MessageContent)

  let restored = intent.from_int(intent.to_int(intents))
  intent.has(restored, intent.Guilds) |> should.be_true
  intent.has(restored, intent.GuildMessages) |> should.be_true
  intent.has(restored, intent.MessageContent) |> should.be_true
  intent.has(restored, intent.GuildModeration) |> should.be_false
}

pub fn to_string_renders_names_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.GuildMessages)

  intent.to_string(intents) |> should.equal("GUILDS, GUILD_MESSAGES")
}

pub fn to_string_empty_test() {
  intent.to_string(intent.new()) |> should.equal("(none)")
}

pub fn privileged_intents_are_known_test() {
  intent.is_privileged(intent.GuildMembers) |> should.be_true
  intent.is_privileged(intent.GuildPresences) |> should.be_true
  intent.is_privileged(intent.MessageContent) |> should.be_true
  intent.is_privileged(intent.Guilds) |> should.be_false
  intent.is_privileged(intent.GuildMessages) |> should.be_false
  intent.is_privileged(intent.GuildModeration) |> should.be_false
}

pub fn check_privileged_finds_only_privileged_test() {
  let mixed =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.GuildMembers)
    |> intent.enable(intent.GuildMessages)
    |> intent.enable(intent.MessageContent)

  let privileged = intent.check_privileged(mixed)
  list.length(privileged) |> should.equal(2)
  list.contains(privileged, intent.GuildMembers) |> should.be_true
  list.contains(privileged, intent.MessageContent) |> should.be_true

  let clean =
    intent.new()
    |> intent.enable(intent.Guilds)
    |> intent.enable(intent.GuildMessages)

  intent.check_privileged(clean) |> list.length |> should.equal(0)
}

pub fn all_intents_have_unique_names_test() {
  let names = list.map(intent.all, intent.intent_name)
  list.length(list.unique(names)) |> should.equal(list.length(names))
}

pub fn intent_name_is_total_test() {
  // Every variant produces a name; no UNKNOWN arm is needed.
  list.each(intent.all, fn(intent) {
    let name = intent.intent_name(intent)
    name |> should.not_equal("")
  })
}

pub fn polls_intents_pin_the_wire_bits_test() {
  // The polls intents must produce the correct wire values.
  let intents =
    intent.new()
    |> intent.enable(intent.GuildMessagePolls)
    |> intent.enable(intent.DirectMessagePolls)

  intent.has(intents, intent.GuildMessages) |> should.be_false
  intent.to_string(intents)
  |> should.equal("GUILD_MESSAGE_POLLS, DIRECT_MESSAGE_POLLS")
}
