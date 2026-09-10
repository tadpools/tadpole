//// Tests for the shard's pure close-decision logic, against the same
//// close-code table tadpole/gateway_test covers. No network, no actor:
//// the actor applies these decisions verbatim between protocol steps.

import gleam/list
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
