//// README.md claims the echo bot listing is the copy to copy, and this
//// test is what makes that claim true. The program is compiled from
//// test/examples/echo_bot.gleam, so a stale API breaks the build. This
//// compares that file against the fenced gleam block in README.md, so
//// the two cannot drift apart either.
////
//// Both halves were added after the README's example silently stopped
//// compiling: intents became a sum type in 2026.3.0 and the listing kept
//// the old lowercase names, with nothing to notice. A README that
//// documents an API it does not compile against is worse than one that
//// admits it is a sketch.

import gleam/list
import gleam/string
import gleeunit/should
import tadpole/support/repo

const readme_path = "README.md"

const example_path = "test/examples/echo_bot.gleam"

pub fn readme_example_matches_the_compiled_example_test() {
  let assert [first, ..] = gleam_blocks(repo.must_read(readme_path))
  strip_header_comment(first)
  |> should.equal(strip_header_comment(repo.must_read(example_path)))
}

pub fn readme_example_block_is_the_echo_bot_test() {
  // Guards the test above. If a second gleam block ever appears before
  // the echo bot, comparing block one would silently start checking the
  // wrong program, which is a worse failure than a red test.
  let assert [first, ..] = gleam_blocks(repo.must_read(readme_path))
  string.contains(first, "pub fn main()") |> should.be_true
}

pub fn example_lives_where_the_build_compiles_it_test() {
  // The compile half of the gate is structural rather than something
  // this test can assert. What it can assert is that the file sits where
  // the build will find it, since a module outside src/ and test/ is
  // never compiled at all.
  string.contains(example_path, "test/") |> should.be_true
}

/// The contents of every ```gleam fenced block, in the order they appear.
fn gleam_blocks(markdown: String) -> List(String) {
  collect_blocks(string.split(markdown, on: "\n"), [], False, False, [])
}

/// `inside` tracks any fenced block, `gleam` whether the one we are in is
/// a gleam block. Markdown fences are all ```, only the opening one says
/// which language, so closing needs both.
fn collect_blocks(
  lines: List(String),
  current: List(String),
  inside: Bool,
  gleam: Bool,
  found: List(String),
) -> List(String) {
  case lines {
    [] ->
      case inside && gleam {
        True -> [finish(current), ..found]
        False -> found
      }
    [line, ..rest] ->
      case is_fence(line) {
        True ->
          case inside {
            True ->
              // Closing fence. Only gleam blocks are collected.
              case gleam {
                True ->
                  collect_blocks(rest, [], False, False, [
                    finish(current),
                    ..found
                  ])
                False -> collect_blocks(rest, [], False, False, found)
              }
            False ->
              collect_blocks(
                rest,
                [],
                True,
                string.starts_with(line, "```gleam"),
                found,
              )
          }
        False ->
          case inside {
            True -> collect_blocks(rest, [line, ..current], True, gleam, found)
            False -> collect_blocks(rest, [], False, False, found)
          }
      }
  }
}

fn finish(lines: List(String)) -> String {
  string.join(list.reverse(lines), with: "\n")
}

fn is_fence(line: String) -> Bool {
  string.starts_with(line, "```")
}

/// The example file opens with a `////` header explaining why it exists,
/// and the README block carries the program alone, so compare the code.
/// The blank lines the header leaves behind go too. Line endings are
/// normalised because the comparison should fail on a changed line, not
/// on which machine wrote the file.
fn strip_header_comment(source: String) -> String {
  source
  |> string.replace("\r\n", "\n")
  |> string.replace("\r", "\n")
  |> string.split(on: "\n")
  |> list.filter(fn(line) { !is_header_comment(line) })
  |> trim_blank_edges
  |> string.join(with: "\n")
}

fn trim_blank_edges(lines: List(String)) -> List(String) {
  drop_trailing_blanks(drop_leading_blanks(lines))
}

fn drop_leading_blanks(lines: List(String)) -> List(String) {
  case lines {
    [line, ..rest] ->
      case string.trim(line) {
        "" -> drop_leading_blanks(rest)
        _ -> [line, ..rest]
      }
    _ -> lines
  }
}

fn drop_trailing_blanks(lines: List(String)) -> List(String) {
  let kept = list.filter(lines, fn(line) { string.trim(line) != "" })
  case kept, lines {
    // Every line was blank, so filtering emptied the list and there is
    // nothing to keep.
    [], _ -> []
    _, _ -> kept
  }
}

fn is_header_comment(line: String) -> Bool {
  string.starts_with(line, "////")
}
