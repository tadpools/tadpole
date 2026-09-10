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
2. **Every failure mode documented in a doc comment maps to a test**: if
   `/// ## Failure modes` says X can happen, a test proves the error carries
   what it claims.
3. **No bare boolean test bodies.** A test ending in `a == b` is a test that
   can never fail. Use `should` assertions or `let assert`:
   ```gleam
   // BAD: passes even when False
   pub fn broken_test() { 1 == 2 }
   // GOOD
   pub fn works_test() { 1 |> should.equal(2) }
   ```
4. **Pipe precedence:** comparisons piped into `should` must be braced:
   `{ x >= 0 } |> should.be_true`.
5. **Redaction is sacred:** any test touching rendered output checks that a
   planted full token does not appear. See `test/tadpole/error_test.gleam`.

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

New user-facing strings follow three laws: clarity outranks charm (delete
   the whimsy; if information is lost, the whimsy was load-bearing), never
joke at the user (self-deprecating about the library is fine), and the more
severe the failure the quieter the whimsy. Severity lives in
`render.severity_of` and is tested; if you add an error, you assign its
   severity. A reviewer will check the ladder, not just the code.

Levels: `Light` for rate limits and heartbeat hiccups (one friendly
line), `Actionable` for REST and decode errors (notes plus a straight
`Try:` list), `Severe` for auth failures (zero whimsy), `Internal` for
our bugs (apology and a report request). Pond words (the Current, lilypads, ripples) may flavor
prose and docs, never type or function names.

## Versioning

Calendar versioning: `YYYY.MILESTONE.PATCH` (e.g. `2026.1.0`). MILESTONE
counts feature milestones within the year, PATCH counts fix releases. Hex
tooling requires an X.Y.Z-shaped version string anyway; CalVer keeps that
shape while making the date the message.

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

Release flow. Hard gate first: the package is not published to Hex until
the library can actually connect to Discord end to end: gateway connect →
hello → heartbeat → identify → ready, plus one real REST call. Publishing
before that is like publishing an emulator that can't emulate. Then: green
gates → changelog entry → CalVer bump in `gleam.toml` and the matching
`version` in `tadpole/user_agent.gleam` → optional
growth-stage git tag → `gleam publish`, only if the gate is met.

## Commit discipline

- Imperative mood, present tense: `add heartbeat zombie detection`, not
  `added`/`adds`.
- One logical change per commit; tests travel with the code they test.
- No tokens, no payloads with real user data, ever: not in fixtures, not in
  logs, not in examples. Fixtures are synthetic or redacted.

## What a reviewer checks

1. The four commands above are green.
2. The change respects module boundaries (no reaching into `tadpole/types`
   internals from `rest`, etc.).
3. New error variants: severity assigned, rendered, tested.
4. New public API: documented, example'd, failure modes listed.
5. The naming: Discord-accurate in code, pond-flavored only in prose.
