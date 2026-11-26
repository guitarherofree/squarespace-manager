#!/usr/bin/env bash
# Prints the notes under "## <version>" in CHANGELOG.md, without the heading.
# Usage: scripts/release-notes.sh 0.2.0
set -euo pipefail
version="${1#v}"
cd "$(dirname "$0")/.."
awk -v v="$version" '
  /^## / {
    if (found) exit
    heading = $2
    sub(/^v/, "", heading)
    if (heading == v) { found = 1; next }
  }
  found { print }
' CHANGELOG.md | sed '/./,$!d'
