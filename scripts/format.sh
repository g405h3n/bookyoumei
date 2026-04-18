#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "error: swiftformat is not installed. Install via 'brew install swiftformat'." >&2
  exit 1
fi

mkdir -p .build/cache

exec swiftformat . --cache .build/cache/swiftformat.cache
