//// A tiny deterministic property-testing harness, in-repo because Hex has
//// no native Gleam property library and the dependency policy prefers
//// plain Gleam over a foreign-runtime binding.
////
//// A property is a function of a generated input that must always hold.
//// `check` generates inputs with a seeded PRNG and runs the property
//// many times; a failure aborts the test run with the label, seed, case
//// index, and the failing input, so any failure is exactly reproducible:
//// re-run with the same `seed` via `check_with` and generation replays
//// input-for-input.
////
//// There is no shrinking. Generation is cheap, inputs here are small
//// (ints, bitmasks, short paths), and the failing case is reported
//// verbatim. If a reported counterexample ever needs manual minimising,
//// the seed makes it a one-liner to reproduce and inspect.
////
//// Layout: this module is test-only infrastructure under
//// test/tadpole/support; property suites live in test/tadpole/property
//// and are named `<module>_properties_test.gleam`.

import gleam/int
import gleam/list
import gleam/string

/// Cases run per property by `check`. Small enough for a fast suite,
/// large enough to exercise combinations.
pub const default_cases = 200

/// The default seed. Fixed on purpose: a failing property must be
/// reproducible across machines and runs, not re-rolled.
pub const default_seed = 20_260_909

/// The linear-congruential generator state. Pure data: a property that
/// holds for one `Rng` history holds for any re-seeded history starting
/// the same way.
pub type Rng {
  Rng(state: Int)
}

/// A generator: from an `Rng`, produce a value and the advanced `Rng`.
/// Compose generators by threading the pair; `int_in` shows the shape.
pub type Gen(a) =
  fn(Rng) -> #(a, Rng)

// 63-bit LCG constants (Hull-Dobell-suitable increment for full period
// modulo 2^63; the modulus is enforced with the mask below).
const multiplier = 6_364_136_223_846_793_005

const increment = 1_442_695_040_888_963_407

const mask = 0x7FFF_FFFF_FFFF_FFFF

/// Seed a generator run. Any integer is accepted; it is masked into the
/// 63-bit state space.
pub fn from_seed(seed: Int) -> Rng {
  Rng(int.bitwise_and(seed, mask))
}

/// Draw the next raw 63-bit value.
pub fn next(rng: Rng) -> #(Int, Rng) {
  let Rng(state) = rng
  let next_state = int.bitwise_and(state * multiplier + increment, mask)
  #(next_state, Rng(next_state))
}

/// An integer in `lo..hi`, both ends inclusive. `lo > hi` is a test bug
/// and fails loudly.
pub fn int_in(lo: Int, hi: Int) -> Gen(Int) {
  fn(rng) {
    let assert True = lo <= hi
    let #(raw, next_rng) = next(rng)
    // A positive 31-bit draw avoids sign and modulo edge cases entirely.
    let draw = int.bitwise_and(raw, 0x7FFF_FFFF)
    let span = hi - lo + 1
    #(lo + draw % span, next_rng)
  }
}

/// Pick one element. Empty options are a test bug and fail loudly.
pub fn one_of(options: List(a)) -> Gen(a) {
  fn(rng) {
    case options {
      [] -> panic as "property.one_of: no options to choose from"
      _ -> {
        let #(index, next_rng) = int_in(0, list.length(options) - 1)(rng)
        let assert Ok(picked) = options |> list.drop(index) |> list.first
        #(picked, next_rng)
      }
    }
  }
}

/// Transform a generated value. Generation order is preserved.
pub fn map(gen: Gen(a), f: fn(a) -> b) -> Gen(b) {
  fn(rng) {
    let #(value, next_rng) = gen(rng)
    #(f(value), next_rng)
  }
}

/// Combine two generators. `gen_a` is fully consumed first, then `gen_b`,
/// then `f` is applied, so a failure report replayed from the same seed
/// reproduces both draws in that order.
pub fn map2(gen_a: Gen(a), gen_b: Gen(b), f: fn(a, b) -> c) -> Gen(c) {
  fn(rng) {
    let #(value_a, _) = gen_a(rng)
    let #(value_b, after_b) = gen_b(rng)
    #(f(value_a, value_b), after_b)
  }
}

/// A list of generated values, length in `min..max` inclusive.
pub fn list_of(gen: Gen(a), min: Int, max: Int) -> Gen(List(a)) {
  fn(rng) {
    let assert True = min <= max
    let #(count, after_count) = int_in(min, max)(rng)
    fill(gen, count, after_count, [])
  }
}

fn fill(gen: Gen(a), count: Int, rng: Rng, acc: List(a)) -> #(List(a), Rng) {
  case count {
    0 -> #(list.reverse(acc), rng)
    _ -> {
      let #(value, next_rng) = gen(rng)
      fill(gen, count - 1, next_rng, [value, ..acc])
    }
  }
}

const digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

/// A string of digit characters, length in `min..max` inclusive. This is
/// the shape Discord ids travel in, which is why it is here and not a
/// general `string_of`.
pub fn digit_string(min: Int, max: Int) -> Gen(String) {
  fn(rng) {
    let assert True = min <= max
    let #(length, after_length) = int_in(min, max)(rng)
    let #(chars, next_rng) = fill(one_of(digits), length, after_length, [])
    #(string.concat(chars), next_rng)
  }
}

/// Run a property with the default seed and case count. Fails the test
/// run with a message naming the property, seed, failing case index, and
/// input; `show` renders that input for the message.
pub fn check(
  label: String,
  show: fn(a) -> String,
  gen: Gen(a),
  property: fn(a) -> Bool,
) -> Nil {
  check_with(default_seed, default_cases, label, show, gen, property)
}

/// `check` with explicit seed and case count. Use it to reproduce a
/// reported failure: the same seed replays the same inputs in the same
/// order, so the reported case index fails again exactly where it did.
pub fn check_with(
  seed: Int,
  cases: Int,
  label: String,
  show: fn(a) -> String,
  gen: Gen(a),
  property: fn(a) -> Bool,
) -> Nil {
  from_seed(seed)
  |> run(seed, cases, 0, label, show, gen, property)
}

fn run(
  rng: Rng,
  seed: Int,
  cases: Int,
  index: Int,
  label: String,
  show: fn(a) -> String,
  gen: Gen(a),
  property: fn(a) -> Bool,
) -> Nil {
  case index >= cases {
    True -> Nil
    False -> {
      let #(input, next_rng) = gen(rng)
      case property(input) {
        True ->
          run(next_rng, seed, cases, index + 1, label, show, gen, property)
        False -> {
          let message =
            label
            <> ": property failed (seed "
            <> int.to_string(seed)
            <> ", case "
            <> int.to_string(index)
            <> " of "
            <> int.to_string(cases)
            <> "): "
            <> show(input)
          panic as message
        }
      }
    }
  }
}
