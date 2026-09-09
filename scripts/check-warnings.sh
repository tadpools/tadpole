#!/usr/bin/env bash
# Zero-warnings gate for Tadpole's own code (src/ and test/).
#
# Warnings coming from dependency sources (build/packages/...) are upstream
# bugs, not ours; failing on those just breaks CI whenever any dependency
# is compiled from scratch. This gate fails only when a warning points at
# code this repository owns.
#
# Usage: scripts/check-warnings.sh   (run from the repo root, after a build)

set -u

rm -f build_warnings.txt
gleam build 2> build_warnings.txt || true

# A warning block starts at "warning:" and its location line follows two
# lines later (┌─ path:line:col). Dependency locations live under
# build/packages/ and are dropped first; anything left pointing at src/
# or test/ is code this repository owns.
ours=$(grep -A 2 '^warning:' build_warnings.txt \
  | grep -v 'build.packages' \
  | grep -E 'src[\\/]|test[\\/]' || true)

if [ -n "$ours" ]; then
  echo "::error::Compiler warnings in Tadpole's own code are not allowed:"
  echo "$ours"
  exit 1
fi

echo "own-code warnings: none (dependency warnings, if any, are upstream)"
rm -f build_warnings.txt
