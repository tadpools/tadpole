//// Tests for the shard's pure decisions: the close ladder against the
//// same close-code table tadpole/gateway_test covers, and the URL the
//// next connection dials. No network, no actor: the actor applies
//// these decisions verbatim between protocol steps.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import tadpole/gateway/shard.{GiveUp, IdentifyFresh, Resume}

pub fn resumable_codes_with_session_resume_test() {
  // Codes Discord sends while the session survives: normal close,
  // going away, network drop, and the recoverable 4xxx errors.
  [1000, 1001, 1006, 4000, 4001, 4002]
  |> list.each(fn(code) {
    shard.next_action_on_close(code, True) |> should.equal(Resume)
  })
}

pub fn resumable_codes_without_session_identify_fresh_test() {
  // Nothing to resume — the session was never established (or was
  // already forgotten after op 9) — so even a resumable close means
  // starting over.
  [1000, 1001, 1006, 4000, 4001, 4002]
  |> list.each(fn(code) {
    shard.next_action_on_close(code, False) |> should.equal(IdentifyFresh)
  })
}

pub fn reconnectable_but_dead_session_identifies_fresh_test() {
  // Invalid seq, rate limit, session timeout: Discord kept the door
  // open but threw the session away. Mirrors gateway_test:
  // should_reconnect True, can_resume False.
  [4007, 4008, 4009]
  |> list.each(fn(code) {
    shard.next_action_on_close(code, True) |> should.equal(IdentifyFresh)
    shard.next_action_on_close(code, False) |> should.equal(IdentifyFresh)
  })
}

pub fn unknown_codes_identify_fresh_test() {
  // Conservative on undocumented codes: reconnect, but do not bet the
  // session on them.
  shard.next_action_on_close(5555, True) |> should.equal(IdentifyFresh)
  shard.next_action_on_close(9999, False) |> should.equal(IdentifyFresh)
}

pub fn not_authenticated_reconnects_with_fresh_identify_test() {
  // 4003: the docs mark it reconnect: true, and with the session gone
  // the fresh identify on reconnect is the documented fix.
  shard.next_action_on_close(4003, True) |> should.equal(IdentifyFresh)
  shard.next_action_on_close(4003, False) |> should.equal(IdentifyFresh)
}

pub fn config_errors_stop_test() {
  // The docs mark these reconnect: false: bad token, invalid shard,
  // sharding required, invalid API version, invalid or disallowed
  // intents. A config problem, not a network problem — reconnecting
  // loops forever without fixing anything.
  [4004, 4010, 4011, 4012, 4013, 4014]
  |> list.each(fn(code) {
    shard.next_action_on_close(code, True) |> should.equal(GiveUp)
    shard.next_action_on_close(code, False) |> should.equal(GiveUp)
  })
}

pub fn invalid_session_resumable_resumes_test() {
  shard.on_invalid_session(True) |> should.equal(Resume)
}

pub fn invalid_session_fatal_identifies_fresh_test() {
  shard.on_invalid_session(False) |> should.equal(IdentifyFresh)
}

pub fn resume_dials_the_ready_gateway_url_test() {
  // The docs: a resume reconnect uses the resume_gateway_url READY
  // provided instead of the URL first connected with, carrying the
  // same query parameters.
  shard.connect_url(
    "wss://gateway.discord.gg/?v=10&encoding=json",
    Some("wss://far-far-away.discord.gg"),
    True,
  )
  |> should.equal("wss://far-far-away.discord.gg/?v=10&encoding=json")
}

pub fn bare_resume_url_gets_the_path_back_test() {
  // Discord sends the resume host bare, no path and no query. Without
  // a path the handshake request-target would be empty, so a bare
  // host dials "/" with the config's query carried over.
  shard.connect_url(
    "wss://gateway.discord.gg/?v=10&encoding=json",
    Some("wss://gateway.discord.gg"),
    True,
  )
  |> should.equal("wss://gateway.discord.gg/?v=10&encoding=json")
}

pub fn resume_url_with_its_own_path_keeps_it_test() {
  // A resume URL that already names a path keeps it; only the query
  // parameters ride over from the configured connection.
  shard.connect_url(
    "ws://localhost:9000/gateway?v=10&encoding=json",
    Some("ws://localhost:9000/gateway"),
    True,
  )
  |> should.equal("ws://localhost:9000/gateway?v=10&encoding=json")
}

pub fn resume_url_with_its_own_query_rules_over_the_config_test() {
  // A resume URL that already carries a query keeps its own: it is
  // the one Discord said to dial, so its parameters win over the
  // config's.
  shard.connect_url(
    "wss://gateway.discord.gg/?v=10&encoding=json",
    Some("wss://gateway.discord.gg?x=1"),
    True,
  )
  |> should.equal("wss://gateway.discord.gg/?x=1")
}

pub fn resume_without_a_captured_url_dials_the_config_test() {
  // No READY has offered a URL yet (or one did and the field was
  // gone): the configured URL keeps working. Nothing about a missing
  // resume_gateway_url should break the reconnect.
  shard.connect_url("wss://gateway.discord.gg/?v=10&encoding=json", None, True)
  |> should.equal("wss://gateway.discord.gg/?v=10&encoding=json")
}

pub fn fresh_connections_dial_the_config_url_test() {
  // The resume URL is only for resumes. An identify dials what the
  // caller configured, even when a READY URL is still stored.
  shard.connect_url(
    "wss://gateway.discord.gg/?v=10&encoding=json",
    Some("wss://far-far-away.discord.gg"),
    False,
  )
  |> should.equal("wss://gateway.discord.gg/?v=10&encoding=json")
}
