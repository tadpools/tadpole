//// Component model: message components (buttons, select menus, action
//// rows). Data shape only; sending is handled by REST endpoints.
//// Stability: Experimental.

import gleam/json
import gleam/option.{type Option, None, Some}

pub type SelectOption {
  SelectOption(
    label: String,
    value: String,
    description: Option(String),
    default: Bool,
  )
}

pub type Component {
  ActionRow(components: List(Component))
  Button(
    style: Int,
    label: Option(String),
    custom_id: Option(String),
    url: Option(String),
    disabled: Bool,
  )
  StringSelect(
    custom_id: String,
    options: List(SelectOption),
    placeholder: Option(String),
    min_values: Option(Int),
    max_values: Option(Int),
    disabled: Bool,
  )
}

pub fn to_json(component: Component) -> json.Json {
  case component {
    ActionRow(components) ->
      json.object([
        #("type", json.int(1)),
        #("components", json.array(components, to_json)),
      ])
    Button(style, label, custom_id, url, disabled) -> {
      let base = [#("type", json.int(2)), #("style", json.int(style))]
      let with_label = case label {
        Some(v) -> [#("label", json.string(v)), ..base]
        None -> base
      }
      let with_custom = case custom_id {
        Some(v) -> [#("custom_id", json.string(v)), ..with_label]
        None -> with_label
      }
      let with_url = case url {
        Some(v) -> [#("url", json.string(v)), ..with_custom]
        None -> with_custom
      }
      let with_disabled = case disabled {
        True -> [#("disabled", json.bool(True)), ..with_url]
        False -> with_url
      }
      json.object(with_disabled)
    }
    StringSelect(
      custom_id,
      options,
      placeholder,
      min_values,
      max_values,
      disabled,
    ) -> {
      let base = [
        #("type", json.int(3)),
        #("custom_id", json.string(custom_id)),
        #(
          "options",
          json.array(options, fn(o) {
            let baseo = [
              #("label", json.string(o.label)),
              #("value", json.string(o.value)),
            ]
            let with_desc = case o.description {
              Some(v) -> [#("description", json.string(v)), ..baseo]
              None -> baseo
            }
            let with_default = case o.default {
              True -> [#("default", json.bool(True)), ..with_desc]
              False -> with_desc
            }
            json.object(with_default)
          }),
        ),
      ]
      let with_placeholder = case placeholder {
        Some(v) -> [#("placeholder", json.string(v)), ..base]
        None -> base
      }
      let with_min = case min_values {
        Some(v) -> [#("min_values", json.int(v)), ..with_placeholder]
        None -> with_placeholder
      }
      let with_max = case max_values {
        Some(v) -> [#("max_values", json.int(v)), ..with_min]
        None -> with_min
      }
      let with_disabled = case disabled {
        True -> [#("disabled", json.bool(True)), ..with_max]
        False -> with_max
      }
      json.object(with_disabled)
    }
  }
}
