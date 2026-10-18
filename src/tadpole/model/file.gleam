//// File model for uploads: a filename, bytes, and a MIME type.
//// Stability: Experimental.

import gleam/bit_array

pub type File {
  File(name: String, content: BitArray, mime_type: String)
}

pub fn from_bytes(name: String, content: BitArray, mime_type: String) -> File {
  File(name: name, content: content, mime_type: mime_type)
}

pub fn from_string(name: String, content: String, mime_type: String) -> File {
  File(
    name: name,
    content: bit_array.from_string(content),
    mime_type: mime_type,
  )
}
