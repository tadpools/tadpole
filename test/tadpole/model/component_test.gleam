import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import tadpole/model/component

pub fn to_json_button_test() {
  let c =
    component.Button(
      style: 1,
      label: Some("ok"),
      custom_id: Some("btn"),
      url: None,
      disabled: False,
    )
  let rendered = json.to_string(component.to_json(c))
  { string.contains(rendered, "\"style\":1") } |> should.be_true
}
