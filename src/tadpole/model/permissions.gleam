//// Computed guild and channel permissions returned by Discord's lookup
//// endpoints. Discord serializes permission bitfields as decimal strings;
//// this model keeps the value intact instead of narrowing it to an integer.
//// Stability: Growing.
////
//// ## When you reach for this
////
//// The permission lookup functions in
//// [`tadpole/rest/endpoints`](../rest/endpoints.html) and
//// [`tadpole/bot`](../bot.html) return a `PermissionSet`. Read its
//// decimal bitfield with `to_string` and interpret the bits the way your
//// application needs.
////
//// ## Failure modes
////
//// `from_json` returns `DecodeFailed` when the payload is invalid JSON,
//// lacks a string `permissions` field, or gives that field another type.
//// `to_string` cannot fail.
////
//// ## Concurrency
////
//// This module is pure data conversion. It does not perform network or
//// process operations.

import gleam/dynamic/decode as d
import tadpole/error.{type TadpoleError}
import tadpole/model/decode

/// A permission bitfield returned by Discord, kept as its decimal string.
/// Keeping it textual preserves bits even if Discord extends the bitfield
/// beyond the range of a platform integer.
pub opaque type PermissionSet {
  PermissionSet(String)
}

/// Decode a permission response such as `{"permissions":"2048"}`.
///
/// Example: `permissions.from_json("{\"permissions\":\"2048\"}")`.
///
/// Fails with `DecodeFailed` when JSON is malformed or `permissions` is
/// missing or is not a string. This is pure decoding and does not block.
pub fn from_json(payload: String) -> Result(PermissionSet, TadpoleError) {
  decode.from_json(None, payload, decoder())
}

/// Return the exact decimal string Discord sent for this bitfield.
///
/// Example: `permissions.to_string(permission_set)`.
///
/// Cannot fail. This is a pure accessor and does not block.
pub fn to_string(permission_set: PermissionSet) -> String {
  let PermissionSet(bits) = permission_set
  bits
}

fn decoder() -> d.Decoder(PermissionSet) {
  use bits <- d.field("permissions", d.string)
  d.success(PermissionSet(bits))
}
