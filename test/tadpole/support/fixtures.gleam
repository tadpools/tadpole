//// Fixture loading for the contract tests: names map to files under
//// test/fixtures, read at test time so payloads stay diffable data and
//// new fixtures never require touching this module. Every id, token,
//// and username in the fixture files is synthetic.

/// Read one fixture by file name, .json included in the name.
/// Missing or unreadable fixtures are test bugs: `must_load` crashes
/// the test with the name in the error, which is exactly the report a
/// broken fixture wants.
pub fn must_load(name: String) -> String {
  let assert Ok(payload) = read(name)
  payload
}

@external(erlang, "tadpole_fixture_ffi", "read")
fn read(name: String) -> Result(String, Nil)
