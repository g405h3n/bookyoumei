#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: swiftlint is not installed. Install via 'brew install swiftlint'." >&2
  exit 1
fi

mkdir -p .build/cache/swiftlint

exec swiftlint lint --strict --cache-path .build/cache/swiftlint
