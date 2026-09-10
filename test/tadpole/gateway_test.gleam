//// Gateway decision tables and backoff, pure logic.
////

import gleam/int
import gleam/list
import gleeunit/should
import tadpole/gateway

pub fn close_1000_is_resumable_test() {
  gateway.can_resume(1000) |> should.be_true
}

pub fn close_1001_is_resumable_test() {
  gateway.can_resume(1001) |> should.be_true
}

pub fn close_1006_is_resumable_test() {
  // Abnormal closure is usually a network drop; the session survives.
  gateway.can_resume(1006) |> should.be_true
}

pub fn close_4000_4001_4002_are_resumable_test() {
  gateway.can_resume(4000) |> should.be_true
  gateway.can_resume(4001) |> should.be_true
  gateway.can_resume(4002) |> should.be_true
}

pub fn close_4004_auth_failure_is_not_resumable_test() {
  gateway.can_resume(4004) |> should.be_false
}

pub fn close_4007_invalid_seq_is_not_resumable_test() {
  gateway.can_resume(4007) |> should.be_false
}

pub fn close_4014_disallowed_intents_is_not_resumable_test() {
  gateway.can_resume(4014) |> should.be_false
}

pub fn unknown_codes_are_not_resumable_test() {
  // Unknown 5xxx and undocumented codes: be conservative.
  gateway.can_resume(5555) |> should.be_false
  gateway.can_resume(9999) |> should.be_false
}

pub fn close_4003_reconnects_with_fresh_identify_test() {
  // The docs' close code table marks 4003 reconnect: true. The session
  // is gone, so the fresh identify on reconnect is the documented fix.
  gateway.should_reconnect(4003) |> should.be_true
}

pub fn config_errors_never_reconnect_test() {
  // The docs mark these reconnect: false. Every one is a config or
  // token problem no amount of reconnecting fixes; backing off forever
  // just grinds against the API.
  [4004, 4010, 4011, 4012, 4013, 4014]
  |> list.each(fn(code) { gateway.should_reconnect(code) |> should.be_false })
}

pub fn transient_failures_reconnect_test() {
  gateway.should_reconnect(1006) |> should.be_true
  gateway.should_reconnect(4000) |> should.be_true
  gateway.should_reconnect(4009) |> should.be_true
}

pub fn backoff_starts_at_initial_test() {
  gateway.backoff_ms(0) |> should.equal(1000)
  gateway.backoff_ms(1) |> should.equal(2000)
}

pub fn backoff_grows_exponentially_test() {
  { gateway.backoff_ms(1) > gateway.backoff_ms(0) } |> should.be_true
  { gateway.backoff_ms(2) > gateway.backoff_ms(1) } |> should.be_true
  { gateway.backoff_ms(3) > gateway.backoff_ms(2) } |> should.be_true
}

pub fn backoff_is_capped_at_60s_test() {
  gateway.backoff_ms(10) |> should.equal(gateway.max_backoff_ms)
  gateway.backoff_ms(100) |> should.equal(gateway.max_backoff_ms)
}

pub fn backoff_never_negative_test() {
  { gateway.backoff_ms(0) >= 0 } |> should.be_true
  { gateway.backoff_ms(7) >= 0 } |> should.be_true
}

pub fn ack_received_resets_missed_count_test() {
  let state = gateway.HeartbeatState(45_000, 42, 0)
  // Miss once — recoverable, not a zombie yet.
  let #(after, zombie) = gateway.ack_missed(state)
  let recovered = gateway.ack_received(after)

  zombie |> should.be_false
  recovered.missed_acks |> should.equal(0)
}

pub fn zombie_detected_after_threshold_test() {
  let state = gateway.HeartbeatState(45_000, 1, 0)

  // Miss once, twice: not yet a zombie.
  let #(s1, zombie1) = gateway.ack_missed(state)
  let #(s2, zombie2) = gateway.ack_missed(s1)
  // Third consecutive miss: zombie connection, kill it.
  let #(s3, zombie3) = gateway.ack_missed(s2)

  zombie1 |> should.be_false
  zombie2 |> should.be_false
  zombie3 |> should.be_true
  s3.missed_acks |> should.equal(gateway.max_missed_acks)
}

pub fn guild_shard_id_follows_formula_test() {
  // shard = (guild_id >> 22) % count
  let guild = 5_107_035_452_918_333_573
  gateway.guild_shard_id(guild, 4)
  |> should.equal(int.bitwise_shift_right(guild, 22) % 4)
}

pub fn guild_shard_id_always_in_range_test() {
  let guild = 5_107_035_452_918_333_573
  let shard = gateway.guild_shard_id(guild, 8)
  { shard >= 0 } |> should.be_true
  { shard < 8 } |> should.be_true
}

pub fn zero_shard_count_does_not_crash_test() {
  gateway.guild_shard_id(123, 0) |> should.equal(0)
}

pub fn close_code_names_test() {
  gateway.close_code_name(1006) |> should.equal("abnormal closure")
  gateway.close_code_name(4004) |> should.equal("authentication failed")
  gateway.close_code_name(4014) |> should.equal("disallowed intents")
  gateway.close_code_name(4900)
  |> should.equal("tadpole keep-session close")
  gateway.close_code_name(4242) |> should.equal("close code 4242")
}
