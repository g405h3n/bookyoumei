#!/usr/bin/env bash
# Strip all git trailers (Amp-Thread-ID, Co-authored-by, etc.) from commit messages.
# Called by prek as a commit-msg hook; $1 is the commit message file path.

set -euo pipefail

msg_file="$1"

# Get the trailer block lines
trailers=$(git interpret-trailers --parse "$msg_file" 2>/dev/null || true)

if [ -z "$trailers" ]; then
  exit 0
fi

# Remove each trailer line from the file
while IFS= read -r trailer; do
  # Escape special chars for sed
  escaped=$(printf '%s\n' "$trailer" | sed 's/[&/\]/\\&/g; s/\[/\\[/g; s/\]/\\]/g')
  sed -i '' "/^${escaped}$/d" "$msg_file"
done <<< "$trailers"

# Remove trailing blank lines
while [ -s "$msg_file" ]; do
  last_line=$(tail -1 "$msg_file")
  if [ -z "$last_line" ]; then
    # Remove last line (works on macOS and Linux)
    sed -i '' '$ d' "$msg_file"
  else
    break
  fi
done
