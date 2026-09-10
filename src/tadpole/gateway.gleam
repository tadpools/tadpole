//// Shard protocol decisions, pure logic: resume/reconnect/close-code
//// tables, backoff, heartbeat miss tracking, sharding math. The shard
//// actor in tadpole/gateway/shard applies these decisions on a live
//// connection.
////
//// Internals: total functions over integers, so every decision the
//// actor makes is testable without a socket. See also
//// [`tadpole/gateway/shard`](gateway/shard.html) for the actor, and
//// [`tadpole/bot`](bot.html), whose disconnect logs quote
//// `close_code_name`.

import gleam/int

pub type ShardState {
  Disconnected
  Connecting
  HelloReceived
  Identifying
  Resuming
  Connected
  ReconnectScheduled(next_attempt: Int)
}

/// Is a session resume safe after this close code? Codes that mean the
/// session itself is bad (auth, invalid seq, disallowed intents) are not
/// resumable; everything up to 4002 keeps the session.
pub fn can_resume(close_code: Int) -> Bool {
  case close_code {
    1000 -> True
    1001 -> True
    1006 -> True
    4000 -> True
    4001 -> True
    4002 -> True
    _ -> False
  }
}

/// Should the shard reconnect after this close code at all? Mirrors the
/// docs' close code table. The stop set is every code the docs mark
/// "Reconnect: false": a bad token, a bad shard, a bad version, bad or
/// disallowed intents. All config problems, and backing off forever
/// without fixing any of them just grinds against the API. 4003 (not
/// authenticated) reconnects: the docs mark it reconnect: true, and a
/// fresh identify after a lost session is the documented fix.
pub fn should_reconnect(close_code: Int) -> Bool {
  case close_code {
    4004 -> False
    4010 -> False
    4011 -> False
    4012 -> False
    4013 -> False
    4014 -> False
    _ -> True
  }
}

pub const initial_backoff_ms = 1000

pub const max_backoff_ms = 60_000

/// Exponential with a cap: 1s, 2s, 4s, 8s ... 60s. No jitter; Discord's
/// session start limit already handles identify contention.
pub fn backoff_ms(attempts: Int) -> Int {
  case attempts <= 0 {
    True -> initial_backoff_ms
    False -> {
      let raw = initial_backoff_ms * int_power(2, attempts)
      case raw > max_backoff_ms {
        True -> max_backoff_ms
        False -> raw
      }
    }
  }
}

fn int_power(base: Int, exponent: Int) -> Int {
  case exponent {
    0 -> 1
    n if n < 0 -> 1
    _ -> base * int_power(base, exponent - 1)
  }
}

pub type HeartbeatState {
  HeartbeatState(interval_ms: Int, last_sent_sequence: Int, missed_acks: Int)
}

pub const max_missed_acks = 3

pub fn ack_received(state: HeartbeatState) -> HeartbeatState {
  HeartbeatState(..state, missed_acks: 0)
}

/// Returns whether the connection has crossed the zombie threshold.
pub fn ack_missed(state: HeartbeatState) -> #(HeartbeatState, Bool) {
  let missed = state.missed_acks + 1
  #(HeartbeatState(..state, missed_acks: missed), missed >= max_missed_acks)
}

/// The shard a guild belongs to.
pub fn guild_shard_id(guild_id: Int, shard_count: Int) -> Int {
  case shard_count > 0 {
    True -> int.bitwise_shift_right(guild_id, 22) % shard_count
    False -> 0
  }
}

pub fn close_code_name(code: Int) -> String {
  case code {
    1000 -> "normal closure"
    1001 -> "going away"
    1002 -> "protocol error"
    1006 -> "abnormal closure"
    4000 -> "unknown error"
    4001 -> "unknown opcode"
    4002 -> "decode error"
    4003 -> "not authenticated"
    4004 -> "authentication failed"
    4005 -> "already authenticated"
    4007 -> "invalid sequence"
    4008 -> "send rate limited"
    4009 -> "session timed out"
    4010 -> "invalid shard"
    4011 -> "sharding required"
    4012 -> "invalid API version"
    4013 -> "invalid intents"
    4014 -> "disallowed intents"
    _ -> "close code " <> int.to_string(code)
  }
}
