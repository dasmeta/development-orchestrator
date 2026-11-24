#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
skill="$root/.agents/skills/development-definition"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
owner="$tmp/specification"
producer="$owner/.agents/skills/write-spec/SKILL.md"
mkdir -p "$(dirname "$producer")" "$tmp/other"
cat > "$tmp/workspace.json" <<'JSON'
{"repositories":{"source":{"path":"specification","skill":"write-spec"}},"stages":[{"id":"intent","repository":"source"}]}
JSON
printf '%s\n' '---' 'name: write-spec' 'description: Write the requested specification.' '---' > "$producer"

test -r "$skill/SKILL.md"
check() {
  bash "$skill/scripts/check-route.sh" "$tmp/workspace.json" intent "$1"
}
expect_block() {
  if check "$1" > "$tmp/out" 2>"$tmp/error"; then
    echo "unexpectedly admitted $1" >&2
    exit 1
  fi
  grep -Fq "$2" "$tmp/error"
}
check "$owner" | jq -e '.repository == "source" and .producer == "write-spec"' >/dev/null
expect_block "$tmp/other" 'owner mismatch'
mv "$producer" "$tmp/disabled"
expect_block "$owner" 'unavailable producer'
