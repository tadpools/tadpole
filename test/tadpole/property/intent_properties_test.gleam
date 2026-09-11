//// Properties for the intent bitfield algebra: enabling is idempotent,
//// disabling undoes enabling, `has` agrees with `enabled`, and
//// privileged detection never reports an unprivileged bit. See
//// test/tadpole/support/property for the harness.

import gleam/int
import gleam/list
import gleam/string
import tadpole/intent
import tadpole/support/property.{type Gen}

fn one_intent() -> Gen(intent.Intent) {
  property.one_of(intent.all)
}

fn any_valid_mask() -> Gen(Int) {
  // Build a mask from the documented intents only, so from_int never
  // drops unknown bits and the property holds.
  fn(rng) {
    list.fold(intent.all, #(0, rng), fn(acc, intent) {
      let #(mask, current_rng) = acc
      let #(bit, next_rng) = property.int_in(0, 1)(current_rng)
      case bit {
        0 -> #(mask, next_rng)
        _ -> #(
          int.bitwise_or(
            mask,
            intent.to_int(intent.new() |> intent.enable(intent)),
          ),
          next_rng,
        )
      }
    })
  }
}

fn intents(mask: Int) -> intent.Intents {
  intent.from_int(mask)
}

pub fn enabling_is_idempotent_test() {
  property.check(
    "enable twice equals enable once",
    fn(pair) {
      let #(mask, intent) = pair
      int.to_string(mask) <> " + " <> intent.intent_name(intent)
    },
    property.map2(any_valid_mask(), one_intent(), fn(mask, intent) {
      #(mask, intent)
    }),
    fn(pair) {
      let #(mask, intent) = pair
      intent.to_int(intent.enable(intents(mask), intent))
      == intent.to_int(intent.enable(
        intent.enable(intents(mask), intent),
        intent,
      ))
    },
  )
}

pub fn disable_undoes_enable_test() {
  property.check(
    "enable then disable clears exactly that intent",
    fn(pair) {
      let #(mask, intent) = pair
      int.to_string(mask) <> " + " <> intent.intent_name(intent)
    },
    property.map2(any_valid_mask(), one_intent(), fn(mask, intent) {
      #(mask, intent)
    }),
    fn(pair) {
      let #(mask, intent) = pair
      let round = intent.disable(intent.enable(intents(mask), intent), intent)
      // The intent must be gone...
      let intent_cleared = {
        intent.has(round, intent) == False
      }
      // ...and every other enabled intent must survive.
      let rest_kept =
        list.all(intent.enabled(round), fn(kept) {
          intent.has(intents(mask), kept)
        })
      intent_cleared && rest_kept
    },
  )
}

pub fn enabled_is_exactly_the_set_bits_test() {
  property.check(
    "every intent in all either has or lacks the bit, consistently",
    int.to_string,
    any_valid_mask(),
    fn(mask) {
      let value = intents(mask)
      // For every documented intent, has and enabled must agree.
      list.all(intent.all, fn(i) {
        intent.has(value, i) == list.contains(intent.enabled(value), i)
      })
    },
  )
}

pub fn has_agrees_with_enabled_test() {
  property.check(
    "has(intents, intent) iff intent is in enabled(intents)",
    int.to_string,
    any_valid_mask(),
    fn(mask) {
      let value = intents(mask)
      let reported = intent.enabled(value)
      list.all(intent.all, fn(intent) {
        { intent.has(value, intent) == list.contains(reported, intent) }
      })
    },
  )
}

pub fn check_privileged_is_always_a_privileged_subset_test() {
  property.check(
    "check_privileged reports only the three privileged intents",
    int.to_string,
    any_valid_mask(),
    fn(mask) {
      list.all(intent.check_privileged(intents(mask)), fn(intent) {
        intent.is_privileged(intent)
      })
    },
  )
}

pub fn from_int_to_int_is_identity_test() {
  property.check(
    "intent from_int . to_int is identity",
    int.to_string,
    any_valid_mask(),
    fn(mask) { intent.to_int(intents(mask)) == mask },
  )
}

pub fn to_string_names_every_enabled_intent_test() {
  property.check(
    "to_string mentions every enabled intent by name",
    int.to_string,
    any_valid_mask(),
    fn(mask) {
      let value = intents(mask)
      case intent.enabled(value) {
        [] -> intent.to_string(value) == "(none)"
        intents ->
          list.all(intents, fn(intent) {
            let name = intent.intent_name(intent)
            string.contains(intent.to_string(value), name)
          })
      }
    },
  )
}
