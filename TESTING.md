# Testing in Tadpole

This guide explains how the test suite is organized, what each layer checks,
and where to add tests. The rules CI enforces are in CONTRIBUTING.md; this
file maps the suite.

## The three layers

| Layer | Lives in | What it checks | Runs |
| --- | --- | --- | --- |
| Unit | `test/tadpole/`, mirroring `src/tadpole/` | Does each public function do what its docs promise, including documented failure modes? | Every run |
| Property | `test/tadpole/property/` | Do pure modules hold their invariants across generated inputs? | Every run |
| Contract | `test/tadpole/contract_test.gleam` + `test/fixtures/` | Do the production decoders accept documented payloads and reject invalid shapes? | Every run |

One suite, one command:

    gleam test

Everything runs offline. Tests don't contact Discord; synthetic payloads
and canned HTTP responses stand in for the real API.

## Layout

    test/
    ├── tadpole_test.gleam          entry point, do not edit by hand
    ├── tadpole_test_ffi.erl        shared request recorder / response queue
    ├── tadpole_fixture_ffi.erl     reads test/fixtures for contract tests
    ├── tadpole/
    │   ├── <module>_test.gleam     unit tests, mirror src/ one-to-one
    │   ├── property/
    │   │   └── *_properties_test.gleam
    │   ├── support/
    │   │   ├── property.gleam      the property harness (test-only)
    │   │   └── fixtures.gleam      fixture loader (test-only)
    │   └── contract_test.gleam     the contract layer
    └── fixtures/                   payload files, one concept per file

## Writing unit tests

They mirror the source tree: `src/tadpole/rest/rate_limit.gleam` is
tested by `test/tadpole/rest/rate_limit_test.gleam`. The rules from
CONTRIBUTING.md that matter most in practice:

- every public function gets at least one test of its primary path
- every failure mode listed in a doc comment gets a test proving the
  error carries what it claims
- no bare boolean bodies; end tests in `should` assertions
- comparisons piped into `should` are braced: `{ x >= 0 } |> should.be_true`

## Writing property tests

The harness is `test/tadpole/support/property.gleam`. It is plain Gleam:
a seeded generator state, a handful of combinators, and a runner.

A property is a function that must hold for every generated input:

```gleam
import tadpole/support/property

pub fn enable_is_idempotent_test() {
  property.check(
    "enable twice equals enable once",
    fn(pair) { show_pair(pair) },
    property.map2(any_mask(), one_bit(), fn(mask, bit) { #(mask, bit) }),
    fn(pair) {
      let #(mask, bit) = pair
      /* the invariant */
    },
  )
}
```

The pieces:

- `check(label, show, gen, property)` runs 200 cases with a fixed seed.
  The label goes into failure output; `show` renders a failing input.
- generators: `int_in(lo, hi)`, `one_of(list)`, `list_of(gen, min, max)`,
  `digit_string(min, max)`; combine with `map` and `map2`
- when a property fails, the test reports its label, seed, case index, and
  input. Rerunning the suite reaches the same case every time.

Conventions: name the file after the module it tests
(`<module>_properties_test.gleam`), name every test with a `_test`
suffix so gleeunit picks it up, and keep the invariant honest: a
property that cannot fail is not a test. Property suites exist for
`snowflake`, `intent`, and `rest/rate_limit`; the next candidates are
whatever pure module grows next.

## Writing contract fixtures

A fixture is one JSON file in `test/fixtures/`, named after what it
proves (`ready_minimal.json`, `message_create_bad_id.json`). Each file
is loaded by exactly one contract test, and the test asserts the shape
the decoders produce or the failure they raise.

Rules:

- synthetic data only. Ids, usernames, urls: invented, never copied
  from a real server, per CONTRIBUTING's no-real-data rule
- one concept per file. If a test needs a second scenario, that is a
  second file
- gateway event fixtures carry the full dispatch envelope (t, s, op, d),
  because that is what `frame.parse` produces and what the shard feeds
  `events.decode`. The contract tests run that same pair
- failure fixtures are fixtures too: `message_create_bad_id.json` proves
  the decoder rejects a non-snowflake author id at path `author.id`, and
  `unknown_field_added.json` proves a field Discord has not shipped yet
  cannot break today's decoding

To add one: write the JSON file, write the test, run `gleam test`. The
loader reads from `test/fixtures` relative to the package root, which
holds both locally and in CI.

## The gates

What CI runs on every PR, in order:

    sh scripts/check-warnings.sh   # zero warnings in tadpole's own code
    gleam test                     # all three layers
    gleam format                   # canonical formatting, no diff
    gleam docs build               # docs render

Run these gates before pushing; CI runs them again on every pull request.

## The live gate

Only one test contacts real Discord, and it runs only when you opt in:
`test/tadpole/live_test.gleam`. Without `TADPOLE_TOKEN` set it prints a
one-line note and passes, so CI never needs a secret and never sees a
network. With the token set, the same suite runs CONTRIBUTING's publish
gate end to end:

    TADPOLE_TOKEN="your bot token" gleam test

It authenticates over REST (`get_current_user`, proving the token),
connects the gateway and waits for READY as the typed event (proving
hello, identify, and the shard's event path), checks both users carry
the same id, then closes. A wrong token fails with a 401 and a hint; a
silent gateway fails with a READY timeout and next steps. The token is
read from the environment only and never printed. This is the command
to run before tagging a release; the gitignored dev/ scripts remain the
way to watch a bot run interactively.

## What the suite does not cover yet

- **Shard actor with an injectable transport:** unit and contract tests pin
  the `frame.parse` to `events.decode` boundary, but don't exercise the actor
  loop around it.
- **End-to-end global rate-limit coordination:** 429 bodies have fixtures,
  and executor paths use canned responses in unit tests, but there is no
  full coordination test yet.
- **Live smoke tests:** they stay out of CI by design. See the README.
