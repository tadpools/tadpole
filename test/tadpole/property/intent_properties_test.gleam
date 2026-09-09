//// Properties for the intent bitfield algebra: enabling is idempotent,
//// disabling undoes enabling, `has` agrees with `enabled`, and
//// privileged detection never reports an unprivileged bit. See
//// test/tadpole/support/property for the harness.

import gleam/int
import gleam/list
import gleam/string
import tadpole/intent
import tadpole/support/property.{type Gen}

// The union of every documented intent bit, derived from intent.all
// itself so the property can never drift from the real bit list.
fn union_mask() -> Int {
  list.fold(intent.all, 0, fn(acc, bit) { int.bitwise_or(acc, bit) })
}

fn one_bit() -> Gen(Int) {
  property.one_of(intent.all)
}

fn any_mask() -> Gen(Int) {
  // 0..2^22-1 spans every documented bit (top: 1 << 21).
  property.int_in(0, 4_194_303)
}

fn intents(mask: Int) -> intent.Intents {
  intent.from_int(mask)
}

fn set_bits(mask: Int) -> Int {
  // Popcount over the 22 relevant bits.
  count_bits(mask, 22)
}

fn count_bits(mask: Int, bit: Int) -> Int {
  case bit {
    0 -> 0
    _ -> {
      let bit_value = int.bitwise_shift_left(1, bit - 1)
      let found = case int.bitwise_and(mask, bit_value) != 0 {
        True -> 1
        False -> 0
      }
      found + count_bits(mask, bit - 1)
    }
  }
}

pub fn enabling_is_idempotent_test() {
  property.check(
    "enable twice equals enable once",
    fn(pair) {
      let #(mask, bit) = pair
      int.to_string(mask) <> " + bit " <> int.to_string(bit)
    },
    property.map2(any_mask(), one_bit(), fn(mask, bit) { #(mask, bit) }),
    fn(pair) {
      let #(mask, bit) = pair
      intent.to_int(intent.enable(intents(mask), bit))
      == intent.to_int(intent.enable(intent.enable(intents(mask), bit), bit))
    },
  )
}

pub fn disable_undoes_enable_test() {
  property.check(
    "enable then disable clears exactly that bit",
    fn(pair) {
      let #(mask, bit) = pair
      int.to_string(mask) <> " + bit " <> int.to_string(bit)
    },
    property.map2(any_mask(), one_bit(), fn(mask, bit) { #(mask, bit) }),
    fn(pair) {
      let #(mask, bit) = pair
      let round = intent.disable(intent.enable(intents(mask), bit), bit)
      // The bit must be gone...
      let bit_cleared = {
        intent.has(round, bit) == False
      }
      // ...and every other enabled bit must survive.
      let rest_kept =
        list.all(intent.enabled(round), fn(kept) {
          intent.has(intents(mask), kept)
        })
      bit_cleared && rest_kept
    },
  )
}

pub fn enabled_never_exceeds_the_union_mask_test() {
  property.check(
    "enabled reports exactly the set bits of the documented union",
    int.to_string,
    any_mask(),
    fn(mask) {
      let documented = int.bitwise_and(mask, union_mask())
      set_bits(documented) == list.length(intent.enabled(intents(mask)))
    },
  )
}

pub fn has_agrees_with_enabled_test() {
  property.check(
    "has(intents, bit) iff bit is in enabled(intents)",
    int.to_string,
    any_mask(),
    fn(mask) {
      let value = intents(mask)
      let reported = intent.enabled(value)
      list.all(intent.all, fn(bit) {
        { intent.has(value, bit) == list.contains(reported, bit) }
      })
    },
  )
}

pub fn check_privileged_is_always_a_privileged_subset_test() {
  property.check(
    "check_privileged reports only the three privileged bits",
    int.to_string,
    any_mask(),
    fn(mask) {
      list.all(intent.check_privileged(intents(mask)), fn(bit) {
        intent.is_privileged(bit)
      })
    },
  )
}

pub fn from_int_to_int_is_identity_test() {
  property.check(
    "intent from_int . to_int is identity",
    int.to_string,
    any_mask(),
    fn(mask) { intent.to_int(intents(mask)) == mask },
  )
}

pub fn to_string_names_every_enabled_bit_test() {
  property.check(
    "to_string mentions every enabled intent by name",
    int.to_string,
    any_mask(),
    fn(mask) {
      let value = intents(mask)
      case intent.enabled(value) {
        [] -> intent.to_string(value) == "(none)"
        bits ->
          list.all(bits, fn(bit) {
            let name = intent.intent_name(bit)
            name != "UNKNOWN(" <> int.to_string(bit) <> ")"
            && string.contains(intent.to_string(value), name)
          })
      }
    },
  )
}
