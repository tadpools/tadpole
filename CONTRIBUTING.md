# Contributing to Tadpole

Every frog starts as a tadpole, and every tadpole follows these rules.

## The quality bar (CI enforces, humans review)

A pull request is merged only when all of the following hold:

```sh
gleam build      # zero errors, ZERO WARNINGS
gleam test       # all tests pass
gleam format     # no diff after formatting
gleam docs build # renders without error
```

**Zero warnings is a hard rule.** Unused imports, unused variables, and
incomplete patterns are design smells, not noise. Fix them, or `_`-prefix
deliberately with a comment explaining why. The rule covers code this repo
owns (`src/`, `test/`); warnings from dependency sources are upstream's,
and CI enforces the distinction via `scripts/check-warnings.sh`.

## Testing requirements

The map to the suite (layers, layout, how to add property tests and
fixtures) lives in TESTING.md. The rules:

1. **Every public function has at least one test** covering its primary path.
2. **Test every documented failure mode.** If a `/// ## Failure modes`
   section says X can happen, add a test that checks the returned error.
3. **Don't end tests with bare booleans.** `a == b` just returns a value;
   Gleeunit won't treat `False` as a failure. Use `should` assertions or
   `let assert`:
   ```gleam
   // BAD: passes even when False
   pub fn broken_test() { 1 == 2 }
   // GOOD
   pub fn works_test() { 1 |> should.equal(2) }
   ```
4. **Pipe precedence:** comparisons piped into `should` must be braced:
   `{ x >= 0 } |> should.be_true`.
5. **Check redaction:** any test that inspects rendered output must verify
   that a planted full token does not appear. See
   `test/tadpole/error_test.gleam`.

## Gleam style rules (learned the hard way; these bit us)

- **No infix bitwise operators.** Gleam 1.18 removed them. Use
  `int.bitwise_or/and/exclusive_or/not/shift_left/shift_right`.
- **No `if` guards on case patterns you can express as nested cases**:
  guards are fine; unbounded ones are not.
- **Imports at the top**, one module per line, unused ones deleted.
- **Opaque types stay opaque.** Domain IDs are unwrapped only inside their
  defining module. If you need the raw value, add an explicit accessor with a
  reason in its doc comment.
- **Libraries never panic.** No `panic`, no `todo` in merged code. `todo`
  is allowed on unmerged feature branches only.
- **Errors are data.** New `TadpoleError` variants must be added to the
   renderer and to `every_variant_renders_nonempty_test`. The compiler
   will walk you there.
- **Discord terminology first, pond gloss second.** `shard (lilypad)`,
  never a pond word where the Discord word belongs.

## Documentation requirements

- Every public module starts with a `////` doc comment explaining what it
  owns and why it exists.
- Every public function documents: purpose, example, failure modes,
  concurrency notes.
- Doc-comment examples in `examples/` or extracted test cases must compile.
  Illustrative pseudo-examples are marked as such, explicitly.

## Voice (Polly) requirements

Keep user-facing text clear before making it charming. Drop a flourish if
removing it doesn't lose information. Never joke at the user's expense;
self-deprecation about the library is fine. Match the tone to the failure:
the more serious it is, the quieter the whimsy should be.

Use `Light` for rate limits and heartbeat hiccups (one friendly line),
`Actionable` for REST and decode errors (notes and a direct `Try:` list),
`Severe` for authentication failures (no whimsy), and `Internal` for bugs
(apologize and invite a report). Severity is assigned in
`render.severity_of` and covered by tests. Reviewers check that ladder along
with the wording.

Pond words such as the Current, lilypads, and ripples can flavor prose and
docs, but never type or function names.

## Versioning

We use calendar versioning: `YYYY.MILESTONE.PATCH` (for example,
`2026.1.0`). MILESTONE counts feature milestones within the year; PATCH
counts fixes. Hex requires an X.Y.Z-shaped version string, so CalVer keeps
that shape and still makes the date part of the version.

Before the first publish there are no compatibility promises between any
two versions: the changelog and the test suite are the contract. Breaking
changes to error variants are noted loudly in the changelog. Modules
declare a stability tier (`Stable` / `Growing`) in their `////` header;
the tiers say how freely each module may change and are independent of
version numbers. Full policy lives in git history and this file once it
stabilizes.

Git tags use growth-stage names alongside versions (hatching, first-swim,
froglet, frog...) as informal milestones. The CalVer number is the only
machine-parsed version.

## Release flow

Don't publish to Hex until Tadpole can complete a real gateway connection
from connect through READY and make one real REST call. Publishing before
that would be like shipping an emulator that can't emulate.

Once that gate and CI pass, update the changelog and bump the CalVer version
in `gleam.toml` and the matching value in `tadpole/user_agent.gleam`. Add an
optional growth-stage git tag, then publish with `gleam publish`.

## Commit discipline

- Imperative mood, present tense: `add heartbeat zombie detection`, not
  `added`/`adds`.
- One logical change per commit; tests travel with the code they test.
- Never put tokens or real user data in fixtures, logs, or examples. Use
  synthetic or redacted payloads instead.

## What a reviewer checks

1. The four commands above are green.
2. The change respects module boundaries (no reaching into `tadpole/types`
   internals from `rest`, etc.).
3. New error variants: severity assigned, rendered, tested.
4. New public API: documented, example'd, failure modes listed.
5. The naming: Discord-accurate in code, pond-flavored only in prose.
