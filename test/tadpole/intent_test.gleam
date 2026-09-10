//// Tests for the intent bitfield.

import gleam/int
import gleam/list
import gleeunit/should
import tadpole/intent

pub fn new_is_empty_test() {
  let intents = intent.new()
  intent.has(intents, intent.guilds) |> should.be_false
  intent.has(intents, intent.guild_messages) |> should.be_false
  intent.has(intents, intent.message_content) |> should.be_false
}

pub fn enable_adds_intent_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guild_messages)

  intent.has(intents, intent.guilds) |> should.be_true
  intent.has(intents, intent.guild_messages) |> should.be_true
  intent.has(intents, intent.guild_members) |> should.be_false
}

pub fn enable_is_idempotent_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guilds)

  intent.has(intents, intent.guilds) |> should.be_true
  intent.enabled(intents) |> list.length |> should.equal(1)
}

pub fn disable_removes_intent_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guild_messages)
    |> intent.disable(intent.guilds)

  intent.has(intents, intent.guilds) |> should.be_false
  intent.has(intents, intent.guild_messages) |> should.be_true
}

pub fn disable_is_idempotent_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.disable(intent.guilds)
    |> intent.disable(intent.guilds)

  intent.has(intents, intent.guilds) |> should.be_false
}

pub fn enabled_lists_exactly_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guild_messages)
    |> intent.enable(intent.guild_members)

  let enabled = intent.enabled(intents)
  list.length(enabled) |> should.equal(3)
  list.contains(enabled, intent.guilds) |> should.be_true
  list.contains(enabled, intent.guild_messages) |> should.be_true
  list.contains(enabled, intent.guild_members) |> should.be_true
  list.contains(enabled, intent.guild_moderation) |> should.be_false
}

pub fn to_int_roundtrip_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guild_messages)
    |> intent.enable(intent.message_content)

  let restored = intent.from_int(intent.to_int(intents))
  intent.has(restored, intent.guilds) |> should.be_true
  intent.has(restored, intent.guild_messages) |> should.be_true
  intent.has(restored, intent.message_content) |> should.be_true
  intent.has(restored, intent.guild_moderation) |> should.be_false
}

pub fn to_string_renders_names_test() {
  let intents =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guild_messages)

  intent.to_string(intents) |> should.equal("GUILDS, GUILD_MESSAGES")
}

pub fn to_string_empty_test() {
  intent.to_string(intent.new()) |> should.equal("(none)")
}

pub fn privileged_intents_are_known_test() {
  intent.is_privileged(intent.guild_members) |> should.be_true
  intent.is_privileged(intent.guild_presences) |> should.be_true
  intent.is_privileged(intent.message_content) |> should.be_true
  intent.is_privileged(intent.guilds) |> should.be_false
  intent.is_privileged(intent.guild_messages) |> should.be_false
  intent.is_privileged(intent.guild_moderation) |> should.be_false
}

pub fn check_privileged_finds_only_privileged_test() {
  let mixed =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guild_members)
    |> intent.enable(intent.guild_messages)
    |> intent.enable(intent.message_content)

  let privileged = intent.check_privileged(mixed)
  list.length(privileged) |> should.equal(2)
  list.contains(privileged, intent.guild_members) |> should.be_true
  list.contains(privileged, intent.message_content) |> should.be_true

  let clean =
    intent.new()
    |> intent.enable(intent.guilds)
    |> intent.enable(intent.guild_messages)

  intent.check_privileged(clean) |> list.length |> should.equal(0)
}

pub fn bit_values_are_unique_test() {
  // Every intent must be a distinct power of two; a duplicate bit would
  // silently enable two intents at once.
  let bits = intent.all
  list.length(list.unique(bits)) |> should.equal(list.length(bits))
  list.each(bits, fn(bit) {
    // Power of two ⟺ exactly one bit set ⟺ n & (n-1) == 0.
    let is_power_of_two = bit > 0 && int.bitwise_and(bit, bit - 1) == 0
    is_power_of_two |> should.be_true
  })
}

pub fn intent_names_are_unique_test() {
  let names = list.map(intent.all, intent.intent_name)
  list.length(list.unique(names)) |> should.equal(list.length(names))
}

pub fn polls_intents_pin_the_wire_bits_test() {
  // 1 << 24 and 1 << 25 per the docs. A wrong constant here would
  // enable the wrong event family and nothing would complain, so the
  // exact values are pinned.
  intent.guild_message_polls |> should.equal(0x1000000)
  intent.direct_message_polls |> should.equal(0x2000000)

  let intents =
    intent.new()
    |> intent.enable(intent.guild_message_polls)
    |> intent.enable(intent.direct_message_polls)

  intent.has(intents, intent.guild_messages) |> should.be_false
  intent.to_string(intents)
  |> should.equal("GUILD_MESSAGE_POLLS, DIRECT_MESSAGE_POLLS")
}
