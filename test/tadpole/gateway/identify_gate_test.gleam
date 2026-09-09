//// Tests for the identify pacing helper. The 5s-per-bucket rule is
//// Discord's documented session-start limit; see identify_gate.gleam
//// for what is deliberately not implemented yet.

import gleeunit/should
import tadpole/gateway/identify_gate

pub fn single_shard_waits_five_seconds_test() {
  identify_gate.recommended_delay_ms(1) |> should.equal(5000)
}

pub fn delay_scales_with_shard_count_test() {
  identify_gate.recommended_delay_ms(2) |> should.equal(10_000)
  identify_gate.recommended_delay_ms(4) |> should.equal(20_000)
  identify_gate.recommended_delay_ms(16) |> should.equal(80_000)
}

pub fn zero_and_negative_shard_counts_still_wait_test() {
  // A nonsense fleet size must not produce a zero wait.
  identify_gate.recommended_delay_ms(0) |> should.equal(5000)
  identify_gate.recommended_delay_ms(-3) |> should.equal(5000)
}
