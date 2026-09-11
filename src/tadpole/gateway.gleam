//// Shard protocol decisions, pure logic: resume/reconnect/close-code
//// tables, backoff, heartbeat rules (first-heartbeat jitter, miss
//// tracking), sharding math. The shard actor in tadpole/gateway/shard
//// applies these decisions on a live connection.
////
//// ## When you reach for this
////
//// Through [`tadpole/gateway/shard`](gateway/shard.html) — the shard
//// actor calls `can_resume`, `should_reconnect`, `backoff_ms`,
//// `first_heartbeat_delay_ms`, and `close_code_name` on a live
//// connection. Directly when you need a close code's name (the bot
//// runner logs quote `close_code_name`) or the shard a guild belongs
//// to (`guild_shard_id`).
////
//// ## Internals
////
//// Total functions over integers, so every decision the actor makes is
//// testable without a socket. See also
//// [`tadpole/gateway/shard`](gateway/shard.html) for the actor, and
//// [`tadpole/bot`](bot.html), whose disconnect logs quote
//// `close_code_name`.

import gleam/float
import gleam/int

/// The shard's connection lifecycle, from cold start through reconnect.
/// The shard actor owns this state; nothing outside should depend on it.
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

/// Starting backoff: 1 second.
pub const initial_backoff_ms = 1000

/// Backoff cap: 60 seconds.
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

/// The shard's heartbeat bookkeeping: interval, last sent sequence, and
/// how many ACKs have been missed since the last heartbeat.
pub type HeartbeatState {
  HeartbeatState(interval_ms: Int, last_sent_sequence: Int, missed_acks: Int)
}

/// The delay before the FIRST heartbeat on a fresh connection, in ms.
/// The docs' rule: wait `heartbeat_interval * jitter`, jitter any value
/// between 0 and 1, so a mass reconnect does not heartbeat in lockstep.
/// Every later heartbeat waits the full interval. `jitter` outside 0..1
/// clamps into the range, so a caller with a bad random source cannot
/// produce a negative or oversized delay.
pub fn first_heartbeat_delay_ms(interval_ms: Int, jitter: Float) -> Int {
  float.round(int.to_float(interval_ms) *. float.clamp(jitter, 0.0, 1.0))
}

/// How many heartbeats can go un-ACKed before the connection is
/// considered dead (zombie). 3 missed ACKs triggers a reconnect.
pub const max_missed_acks = 3

/// Reset the missed-ACK counter to zero — the server acknowledged our
/// heartbeat.
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

/// Human-readable name for a gateway close code, matching Discord's docs
/// table. Tadpole's own 4900 is "tadpole keep-session close"; unknown
/// codes render as "close code N".
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
    // Tadpole's own keep-session wire code, never sent by Discord. It
    // shows up in lifecycle notices for deliberate resume-intended
    // closes (op 7 reconnect, resumable op 9, zombie kill).
    4900 -> "tadpole keep-session close"
    _ -> "close code " <> int.to_string(code)
  }
}
