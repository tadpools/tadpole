//// Snowflakes: Discord's 64-bit IDs. The top 42 bits embed the creation
//// time in milliseconds since the Discord epoch (2015-01-01); the low
//// bits are worker and sequence noise. Every Discord object id is one.
////
//// ## When you reach for this
////
//// Through the opaque wrappers in [`tadpole/types/ids`](ids.html) —
//// `message.channel_id` is a `ChannelId`, ready for `bot.send_message`,
//// and most code never touches the raw snowflake. Come here for the raw
//// value, validation, or the timestamp — sorting by age (older id =
//// earlier creation) and dating objects without a timestamp field are the
//// usual reasons.
////
////     let assert Ok(id) = snowflake.from_string("123456789012345678")
////     snowflake.timestamp_ms(id)  // unix ms of creation
////
//// Validation rejects negatives and values whose embedded timestamp
//// exceeds ~2090 (`TooFarInFuture`) — corrupted data, not a real id.
//// Everything else here cannot fail.

import gleam/int

/// Discord epoch: 2015-01-01T00:00:00Z in unix milliseconds. Snowflake
/// timestamps are milliseconds after this value.
pub const discord_epoch = 1_420_070_400_000

/// Rejects timestamps past ~2090 as corrupted.
pub const max_inner_timestamp = 3_800_000_000_000

/// Why a string did not parse as a snowflake.
pub type InvalidSnowflakeReason {
  NotANumber
  NegativeValue
  TooFarInFuture
}

/// A rejected snowflake parse: the original string and why it failed.
pub type InvalidSnowflake {
  InvalidSnowflake(value: String, reason: InvalidSnowflakeReason)
}

/// A validated Discord snowflake: a 64-bit integer that encodes a
/// creation timestamp. Opaque; construct via `from_string` or `from_int`.
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

/// Parse a string as a snowflake. Rejects non-numeric strings, negatives,
/// and values whose embedded timestamp exceeds ~2090.
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

/// Decimal string form, the shape Discord sends over the wire.
pub fn to_string(snowflake: Snowflake) -> String {
  let Snowflake(value) = snowflake
  int.to_string(value)
}

/// Creation time in unix milliseconds.
pub fn timestamp_ms(snowflake: Snowflake) -> Int {
  let Snowflake(value) = snowflake
  int.bitwise_shift_right(value, 22) + discord_epoch
}

/// Quick check: does the string parse as a valid snowflake?
pub fn is_valid(value: String) -> Bool {
  case from_string(value) {
    Ok(_) -> True
    Error(_) -> False
  }
}
