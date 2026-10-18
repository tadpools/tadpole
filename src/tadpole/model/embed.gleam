//// Embed model: the rich embed object Discord accepts on messages and
//// interaction responses. This is the data shape only; sending it is
//// handled by the REST endpoints and bot helpers.
//// Stability: Experimental.

import gleam/json
import gleam/option.{type Option, None, Some}

pub type EmbedField {
  EmbedField(name: String, value: String, inline: Bool)
}

pub type EmbedFooter {
  EmbedFooter(text: String, icon_url: Option(String))
}

pub type EmbedAuthor {
  EmbedAuthor(name: String, url: Option(String), icon_url: Option(String))
}

pub type EmbedImage {
  EmbedImage(url: String)
}

pub type Embed {
  Embed(
    title: Option(String),
    description: Option(String),
    url: Option(String),
    color: Option(Int),
    timestamp: Option(String),
    footer: Option(EmbedFooter),
    image: Option(EmbedImage),
    thumbnail: Option(EmbedImage),
    author: Option(EmbedAuthor),
    fields: List(EmbedField),
  )
}

pub fn new() -> Embed {
  Embed(
    title: None,
    description: None,
    url: None,
    color: None,
    timestamp: None,
    footer: None,
    image: None,
    thumbnail: None,
    author: None,
    fields: [],
  )
}

pub fn to_json(embed: Embed) -> json.Json {
  let fields =
    json.array(embed.fields, fn(f) {
      json.object([
        #("name", json.string(f.name)),
        #("value", json.string(f.value)),
        #("inline", json.bool(f.inline)),
      ])
    })
  let base = [
    #("fields", fields),
  ]
  // optional fields
  let with_title = case embed.title {
    Some(v) -> [#("title", json.string(v)), ..base]
    None -> base
  }
  let with_desc = case embed.description {
    Some(v) -> [#("description", json.string(v)), ..with_title]
    None -> with_title
  }
  let with_url = case embed.url {
    Some(v) -> [#("url", json.string(v)), ..with_desc]
    None -> with_desc
  }
  let with_color = case embed.color {
    Some(v) -> [#("color", json.int(v)), ..with_url]
    None -> with_url
  }
  let with_ts = case embed.timestamp {
    Some(v) -> [#("timestamp", json.string(v)), ..with_color]
    None -> with_color
  }
  let with_footer = case embed.footer {
    Some(f) -> [
      #(
        "footer",
        json.object(
          [#("text", json.string(f.text))]
          |> append_opt("icon_url", f.icon_url, json.string),
        ),
      ),
      ..with_ts
    ]
    None -> with_ts
  }
  let with_image = case embed.image {
    Some(i) -> [
      #("image", json.object([#("url", json.string(i.url))])),
      ..with_footer
    ]
    None -> with_footer
  }
  let with_thumb = case embed.thumbnail {
    Some(i) -> [
      #("thumbnail", json.object([#("url", json.string(i.url))])),
      ..with_image
    ]
    None -> with_image
  }
  let with_author = case embed.author {
    Some(a) -> {
      let obj =
        [#("name", json.string(a.name))]
        |> append_opt("url", a.url, json.string)
        |> append_opt("icon_url", a.icon_url, json.string)
      [#("author", json.object(obj)), ..with_thumb]
    }
    None -> with_thumb
  }
  json.object(with_author)
}

fn append_opt(list, key, value, encoder) {
  case value {
    Some(v) -> [#(key, encoder(v)), ..list]
    None -> list
  }
}
