import gleeunit/should
import tadpole/error
import tadpole/model/permissions

pub fn from_json_preserves_a_wide_permission_bitfield_test() {
  let assert Ok(permission_set) =
    permissions.from_json("{\"permissions\":\"1180591620717411303425\"}")

  permissions.to_string(permission_set)
  |> should.equal("1180591620717411303425")
}

pub fn from_json_rejects_a_numeric_permission_bitfield_test() {
  let assert Error(error.DecodeFailed(_, path, _, _)) =
    permissions.from_json("{\"permissions\":2048}")

  path |> should.equal("permissions")
}

pub fn from_json_rejects_a_missing_permission_field_test() {
  let assert Error(error.DecodeFailed(_, path, _, _)) =
    permissions.from_json("{}")

  path |> should.equal("permissions")
}
