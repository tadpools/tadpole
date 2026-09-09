//// Properties for snowflake validation and timestamp extraction:
//// every value the constructor accepts must round-trip through both the
//// int and string representations, always date after the Discord epoch,
//// and order by id exactly as it orders by creation time. See
//// test/tadpole/support/property for the harness.

import gleam/int
import gleam/list
import tadpole/support/property.{type Gen}
import tadpole/types/snowflake

// The 22 low bits hold worker and sequence noise below the timestamp.
const noise_bits = 4_194_303

fn snowflake_int() -> Gen(Int) {
  property.map2(
    property.int_in(0, snowflake.max_inner_timestamp),
    property.int_in(0, noise_bits),
    fn(ts, noise) { int.bitwise_shift_left(ts, 22) + noise },
  )
}

fn valid(value: Int) -> snowflake.Snowflake {
  let assert Ok(sf) = snowflake.from_int(value)
  sf
}

pub fn from_int_to_int_roundtrip_test() {
  property.check(
    "snowflake from_int . to_int is identity",
    int.to_string,
    snowflake_int(),
    fn(value) { snowflake.to_int(valid(value)) == value },
  )
}

pub fn from_string_to_string_roundtrip_test() {
  property.check(
    "snowflake from_string . to_string is identity",
    int.to_string,
    snowflake_int(),
    fn(value) {
      case snowflake.from_string(snowflake.to_string(valid(value))) {
        Ok(again) -> snowflake.to_int(again) == value
        Error(_) -> False
      }
    },
  )
}

pub fn is_valid_accepts_every_generated_id_test() {
  property.check(
    "snowflake is_valid accepts every generated valid id",
    int.to_string,
    snowflake_int(),
    fn(value) { snowflake.is_valid(int.to_string(value)) },
  )
}

pub fn timestamp_is_never_before_discord_epoch_test() {
  property.check(
    "snowflake timestamp_ms >= discord_epoch for every valid id",
    int.to_string,
    snowflake_int(),
    fn(value) {
      snowflake.timestamp_ms(valid(value)) >= snowflake.discord_epoch
    },
  )
}

pub fn timestamp_is_epoch_plus_embedded_ts_test() {
  property.check(
    "snowflake timestamp_ms == embedded ts + discord_epoch",
    int.to_string,
    snowflake_int(),
    fn(value) {
      snowflake.timestamp_ms(valid(value))
      == int.bitwise_shift_right(value, 22) + snowflake.discord_epoch
    },
  )
}

pub fn id_order_matches_timestamp_order_test() {
  property.check(
    "lower snowflake id never carries a later timestamp",
    fn(pair) {
      let #(a, b) = pair
      int.to_string(a) <> " < " <> int.to_string(b)
    },
    property.map2(snowflake_int(), snowflake_int(), fn(a, b) { #(a, b) }),
    fn(pair) {
      let #(a, b) = pair
      case a < b {
        True ->
          snowflake.timestamp_ms(valid(a)) <= snowflake.timestamp_ms(valid(b))
        False -> True
      }
    },
  )
}

pub fn sorting_by_id_sorts_by_timestamp_test() {
  // Sorting by raw id sorts by creation time: the usual reason to reach
  // for the int representation at all. Equal-timestamp ids (same high
  // bits, different noise) may interleave in either order, so the check
  // is that timestamps come out non-decreasing, not that a second sort
  // reproduces the first.
  property.check(
    "sorting snowflakes by int sorts by timestamp",
    fn(values) { int.to_string(list.length(values)) <> " ids" },
    property.list_of(snowflake_int(), 0, 12),
    fn(values) {
      let by_int = list.sort(values, int.compare)
      let times =
        list.map(by_int, fn(value) { snowflake.timestamp_ms(valid(value)) })
      times == list.sort(times, int.compare)
    },
  )
}
