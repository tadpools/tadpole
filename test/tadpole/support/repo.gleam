//// Reading repo files that are not fixtures. Used by the README drift
//// test, which compares the fenced example in README.md against the
//// compiled copy under test/examples.
////
//// Relative paths, because the compiler sets the CWD to the package root
//// when running `gleam test`. A missing file is a test bug and fails with
//// the path in the message.

@external(erlang, "tadpole_repo_ffi", "read")
fn read(path: String) -> Result(String, Nil)

pub fn must_read(path: String) -> String {
  let assert Ok(contents) = read(path)
  contents
}
