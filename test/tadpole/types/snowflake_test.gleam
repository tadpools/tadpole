//// Tests for snowflake parsing, validation, and timestamp extraction.

import gleam/int
import gleeunit/should
import tadpole/types/snowflake.{
  from_int, from_string, is_valid, timestamp_ms, to_int, to_string,
}

// A real snowflake: 2018-11-10T19:53:33.610Z
const real_id = "510703545291833357"

pub fn parses_real_snowflake_test() {
  let assert Ok(sf) = from_string(real_id)
  to_string(sf) |> should.equal(real_id)
}

pub fn roundtrip_int_test() {
  let assert Ok(sf) = from_string(real_id)
  let assert Ok(again) = from_int(to_int(sf))
  to_int(again) |> should.equal(to_int(sf))
}

pub fn timestamp_extraction_test() {
  let assert Ok(sf) = from_string(real_id)
  // 2018-11-10T19:53:33.610Z == 1541879613610 unix ms
  timestamp_ms(sf) |> should.equal(1_541_831_613_610)
}

pub fn timestamp_is_after_discord_epoch_test() {
  let assert Ok(sf) = from_string(real_id)
  { timestamp_ms(sf) >= snowflake.discord_epoch } |> should.be_true
}

pub fn rejects_negative_test() {
  let assert Error(snowflake.InvalidSnowflake(_, snowflake.NegativeValue)) =
    from_int(-1)
  Nil
}

pub fn rejects_not_a_number_test() {
  let assert Error(snowflake.InvalidSnowflake(_, snowflake.NotANumber)) =
    from_string("not-a-number")
  Nil
}

pub fn rejects_empty_string_test() {
  is_valid("") |> should.be_false
}

pub fn rejects_too_far_in_future_test() {
  // This would embed a timestamp past ~2090.
  let absurd =
    { snowflake.max_inner_timestamp + 1 } * int.bitwise_shift_left(1, 22)
  let assert Error(snowflake.InvalidSnowflake(_, snowflake.TooFarInFuture)) =
    from_int(absurd)
  Nil
}

pub fn accepts_epoch_boundary_test() {
  // Smallest valid snowflake: timestamp 0 → raw int 0.
  let assert Ok(sf) = from_int(0)
  timestamp_ms(sf) |> should.equal(snowflake.discord_epoch)
}

pub fn is_valid_true_for_real_test() {
  is_valid(real_id) |> should.be_true
}

pub fn is_valid_false_for_garbage_test() {
  is_valid("zzz") |> should.be_false
}

pub fn to_string_is_decimal_test() {
  let assert Ok(sf) = from_string(real_id)
  to_string(sf) |> should.equal(int.to_string(to_int(sf)))
}
