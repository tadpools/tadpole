//// Gateway opcodes, with a safe slot for opcodes Discord adds later:
//// `from_int` never fails, unknown values land in `UnknownOpcode(value)`
//// and are ignored by the shard. Pure data; see
//// [`tadpole/gateway/frame`](frame.html) for the envelopes that carry
//// these.

import gleam/int

pub type Opcode {
  /// 0 — receive. A dispatched event; payload in `d`, name in `t`.
  Dispatch
  /// 1 — send/receive. Heartbeat; payload is the last sequence number.
  Heartbeat
  /// 2 — send. Authenticate and subscribe to intents.
  Identify
  /// 3 — send. Update presence status.
  PresenceUpdate
  /// 4 — send. Join/move/disconnect voice channels.
  VoiceStateUpdate
  /// 5 — reserved, unused.
  Opcode5
  /// 6 — send. Resume a dropped session.
  Resume
  /// 7 — receive. Discord asks us to reconnect; resume afterwards.
  Reconnect
  /// 8 — send. Request guild members.
  RequestGuildMembers
  /// 9 — receive. Invalid session; `d` says whether resume is possible.
  InvalidSession
  /// 10 — receive. First payload after connect; carries heartbeat interval.
  Hello
  /// 11 — receive. Heartbeat acknowledgment.
  HeartbeatAck
  UnknownOpcode(Int)
}

pub fn to_int(opcode: Opcode) -> Int {
  case opcode {
    Dispatch -> 0
    Heartbeat -> 1
    Identify -> 2
    PresenceUpdate -> 3
    VoiceStateUpdate -> 4
    Opcode5 -> 5
    Resume -> 6
    Reconnect -> 7
    RequestGuildMembers -> 8
    InvalidSession -> 9
    Hello -> 10
    HeartbeatAck -> 11
    UnknownOpcode(value) -> value
  }
}

/// Never fails: unknown opcodes land in UnknownOpcode instead.
pub fn from_int(value: Int) -> Opcode {
  case value {
    0 -> Dispatch
    1 -> Heartbeat
    2 -> Identify
    3 -> PresenceUpdate
    4 -> VoiceStateUpdate
    5 -> Opcode5
    6 -> Resume
    7 -> Reconnect
    8 -> RequestGuildMembers
    9 -> InvalidSession
    10 -> Hello
    11 -> HeartbeatAck
    _ -> UnknownOpcode(value)
  }
}

pub fn name(opcode: Opcode) -> String {
  case opcode {
    Dispatch -> "DISPATCH"
    Heartbeat -> "HEARTBEAT"
    Identify -> "IDENTIFY"
    PresenceUpdate -> "PRESENCE_UPDATE"
    VoiceStateUpdate -> "VOICE_STATE_UPDATE"
    Opcode5 -> "RESERVED_5"
    Resume -> "RESUME"
    Reconnect -> "RECONNECT"
    RequestGuildMembers -> "REQUEST_GUILD_MEMBERS"
    InvalidSession -> "INVALID_SESSION"
    Hello -> "HELLO"
    HeartbeatAck -> "HEARTBEAT_ACK"
    UnknownOpcode(value) -> "UNKNOWN(" <> int.to_string(value) <> ")"
  }
}
