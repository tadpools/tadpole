//// Snowflakes: Discord's 64-bit IDs. The top 42 bits embed the creation
//// time in milliseconds since the Discord epoch (2015-01-01); the low
//// bits are worker and sequence noise. Every Discord object id is one.
////
//// Internals: most code meets snowflakes through the opaque wrappers in
//// [`tadpole/types/ids`](ids.html). Come here for the raw value,
//// validation, or the timestamp — sorting by age (older id = earlier
//// creation) and dating objects without a timestamp field are the usual
//// reasons.
////
////     let assert Ok(id) = snowflake.from_string("123456789012345678")
////     snowflake.timestamp_ms(id)  // unix ms of creation
////
//// Validation rejects negatives and values whose embedded timestamp
//// exceeds ~2090 (`TooFarInFuture`) — corrupted data, not a real id.
//// Everything else here cannot fail.

import gleam/int

pub const discord_epoch = 1_420_070_400_000

/// Rejects timestamps past ~2090 as corrupted.
pub const max_inner_timestamp = 3_800_000_000_000

pub type InvalidSnowflakeReason {
  NotANumber
  NegativeValue
  TooFarInFuture
}

pub type InvalidSnowflake {
  InvalidSnowflake(value: String, reason: InvalidSnowflakeReason)
}

pub opaque type Snowflake {
  Snowflake(Int)
}

/// Validates the embedded timestamp window; rejects negatives.
pub fn from_int(value: Int) -> Result(Snowflake, InvalidSnowflake) {
  let inner_timestamp = int.bitwise_shift_right(value, 22)
  case value < 0 {
    True -> Error(InvalidSnowflake(int.to_string(value), NegativeValue))
    False ->
      case inner_timestamp > max_inner_timestamp {
        True -> Error(InvalidSnowflake(int.to_string(value), TooFarInFuture))
        False -> Ok(Snowflake(value))
      }
  }
}

pub fn from_string(value: String) -> Result(Snowflake, InvalidSnowflake) {
  case int.parse(value) {
    Ok(n) -> from_int(n)
    Error(_) -> Error(InvalidSnowflake(value, NotANumber))
  }
}

/// IDs travel as strings in JSON; this is internal plumbing.
pub fn to_int(snowflake: Snowflake) -> Int {
  let Snowflake(value) = snowflake
  value
}

pub fn to_string(snowflake: Snowflake) -> String {
  let Snowflake(value) = snowflake
  int.to_string(value)
}

/// Creation time in unix milliseconds.
pub fn timestamp_ms(snowflake: Snowflake) -> Int {
  let Snowflake(value) = snowflake
  int.bitwise_shift_right(value, 22) + discord_epoch
}

pub fn is_valid(value: String) -> Bool {
  case from_string(value) {
    Ok(_) -> True
    Error(_) -> False
  }
}
