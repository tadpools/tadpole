//// Tests for Gateway opcodes.

import gleeunit/should
import tadpole/gateway/opcode

pub fn roundtrip_all_known_opcodes_test() {
  let known = [
    opcode.Dispatch, opcode.Heartbeat, opcode.Identify, opcode.PresenceUpdate,
    opcode.VoiceStateUpdate, opcode.Opcode5, opcode.Resume, opcode.Reconnect,
    opcode.RequestGuildMembers, opcode.InvalidSession, opcode.Hello,
    opcode.HeartbeatAck,
  ]
  list_each(known, fn(op) {
    opcode.from_int(opcode.to_int(op)) |> should.equal(op)
  })
}

pub fn from_int_matches_wire_values_test() {
  opcode.from_int(0) |> should.equal(opcode.Dispatch)
  opcode.from_int(1) |> should.equal(opcode.Heartbeat)
  opcode.from_int(2) |> should.equal(opcode.Identify)
  opcode.from_int(6) |> should.equal(opcode.Resume)
  opcode.from_int(7) |> should.equal(opcode.Reconnect)
  opcode.from_int(10) |> should.equal(opcode.Hello)
  opcode.from_int(11) |> should.equal(opcode.HeartbeatAck)
}

pub fn unknown_opcodes_never_crash_test() {
  // Protocol additions must land in UnknownOpcode, not crash the parser.
  let unknown = opcode.from_int(99)
  opcode.to_int(unknown) |> should.equal(99)
  opcode.name(unknown) |> should.equal("UNKNOWN(99)")
}

pub fn names_test() {
  opcode.name(opcode.Hello) |> should.equal("HELLO")
  opcode.name(opcode.Dispatch) |> should.equal("DISPATCH")
}

fn list_each(items: List(a), f: fn(a) -> b) -> Nil {
  case items {
    [] -> Nil
    [head, ..tail] -> {
      f(head)
      list_each(tail, f)
    }
  }
}
