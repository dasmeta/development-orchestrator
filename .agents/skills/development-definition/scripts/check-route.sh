#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../../../.." && pwd)"
source "$root/scripts/orchestration/lib/workspace_config.sh"

fail() { echo "$*" >&2; exit 1; }
[[ $# -ge 3 && $# -le 4 ]] || fail "usage: check-route.sh CONFIG STAGE EXPECTED_OWNER_PATH [SKILL_CATALOG]"
config=$1
stage=$2
require_workspace_config "$config"
owner="$(workspace_stage_repository "$config" "$stage")"
[[ -n "$owner" && "$owner" != *$'\n'* ]] || fail "unknown or ambiguous stage: $stage"
mapped="$(workspace_repository_path "$config" "$owner")" || fail "missing repository path for $owner"
[[ -d "$mapped" && -d "$3" ]] || fail "owner mismatch: repository path unavailable"
[[ "$(cd "$mapped" && pwd -P)" == "$(cd "$3" && pwd -P)" ]] || fail "owner mismatch for $stage"
producer="$(workspace_stage_skill "$config" "$stage" "$owner")"
[[ "$producer" =~ ^[a-zA-Z0-9_-]+$ && "$producer" != development-definition ]] || fail "invalid or recursive producer for $stage"
catalog="${4:-$mapped/.agents/skills}"
[[ -f "$catalog/$producer/SKILL.md" && -r "$catalog/$producer/SKILL.md" ]] || fail "unavailable producer: $producer"
jq -n --arg repository "$owner" --arg producer "$producer" '{repository:$repository,producer:$producer}'
