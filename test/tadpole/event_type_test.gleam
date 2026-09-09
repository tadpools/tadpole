//// Tests for the event dispatch table.

import gleam/list
import gleam/option.{None}
import gleam/set
import gleeunit/should
import tadpole/event_type

pub fn known_events_recognized_test() {
  event_type.is_known("READY") |> should.be_true
  event_type.is_known("MESSAGE_CREATE") |> should.be_true
  event_type.is_known("INTERACTION_CREATE") |> should.be_true
  event_type.is_known("GUILD_CREATE") |> should.be_true
  event_type.is_known("PRESENCE_UPDATE") |> should.be_true
  event_type.is_known("VOICE_STATE_UPDATE") |> should.be_true
}

pub fn unknown_events_fall_through_test() {
  // Discord adds an event after Tadpole's release: no crash, no failure.
  event_type.is_known("BRAND_NEW_EVENT") |> should.be_false
  event_type.category("BRAND_NEW_EVENT") |> should.equal(event_type.Other)
  event_type.maybe_known("BRAND_NEW_EVENT") |> should.equal(None)
}

pub fn categories_are_coherent_test() {
  event_type.category("MESSAGE_CREATE")
  |> should.equal(event_type.MessageEvents)

  event_type.category("GUILD_ROLE_DELETE")
  |> should.equal(event_type.GuildEvents)

  event_type.category("AUTO_MODERATION_ACTION_EXECUTION")
  |> should.equal(event_type.AutoModerationEvents)

  event_type.category("MESSAGE_POLL_VOTE_ADD")
  |> should.equal(event_type.PollEvents)

  event_type.category("ENTITLEMENT_CREATE")
  |> should.equal(event_type.EntitlementEvents)
}

pub fn message_events_require_message_intent_test() {
  // MESSAGE_CREATE arrives only with guild_messages (or direct_messages).
  let required = event_type.required_intents("MESSAGE_CREATE")
  list.contains(required, 0x0200) |> should.be_true
}

pub fn voice_events_require_voice_states_test() {
  let required = event_type.required_intents("VOICE_STATE_UPDATE")
  list.contains(required, 0x0080) |> should.be_true
}

pub fn lifecycle_events_need_no_intents_test() {
  // READY/RESUMED arrive on every connection.
  event_type.required_intents("READY") |> list.length |> should.equal(0)
  event_type.required_intents("RESUMED") |> list.length |> should.equal(0)
}

pub fn unknown_events_need_no_intents_test() {
  event_type.required_intents("BRAND_NEW_EVENT")
  |> list.length
  |> should.equal(0)
}

pub fn table_has_no_duplicates_test() {
  let names = event_type.all_known_names()
  list.length(names) |> should.equal(set.size(event_type.names_set()))
}

pub fn table_names_roundtrip_through_category_test() {
  list.each(event_type.all_known_names(), fn(name) {
    event_type.category(name) |> should.not_equal(event_type.Other)
    event_type.is_known(name) |> should.be_true
  })
}
