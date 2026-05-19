#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/workspace_config.sh"

require_command jq

feature_dir=""
fixtures_dir=""
repo=""
pr_number=""
config_path="$(default_workspace_config_path "$script_dir")"

normalize_check_status() {
  local raw_status="$1"
  case "$raw_status" in
    SUCCESS|NEUTRAL)
      echo "green"
      ;;
    FAILURE|TIMED_OUT|CANCELLED|STARTUP_FAILURE|ACTION_REQUIRED)
      echo "red"
      ;;
    *)
      echo "pending"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature-dir)
      feature_dir="$2"
      shift 2
      ;;
    --fixtures)
      fixtures_dir="$2"
      shift 2
      ;;
    --repo)
      repo="$2"
      shift 2
      ;;
    --pr-number)
      pr_number="$2"
      shift 2
      ;;
    --config)
      config_path="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$feature_dir" ]]; then
  echo "feature directory is required" >&2
  exit 1
fi
require_workspace_config "$config_path"

mkdir -p "$feature_dir/state"

if [[ -n "$fixtures_dir" ]]; then
  jq -n \
    --slurpfile pr "$fixtures_dir/pr-approved.json" \
    --slurpfile checks "$fixtures_dir/checks-green.json" \
    --slurpfile preview "$fixtures_dir/preview-ready.json" \
    '{
      pull_request: $pr[0].pull_request,
      checks: $checks[0],
      preview: $preview[0]
    }' > "$feature_dir/state/github-state.json"
  exit 0
fi

if [[ -z "$repo" || -z "$pr_number" ]]; then
  echo "repo and pr number are required when fixtures are not provided" >&2
  exit 1
fi

require_command gh

pr_json="$(gh pr view "$pr_number" --repo "$repo" --json reviewDecision,mergeStateStatus,statusCheckRollup,url,headRefName)"

check_patterns_json="$(jq -c '.github_state.check_name_patterns // {}' "$config_path")"
check_keys="$(printf '%s' "$check_patterns_json" | jq -r 'keys[] | select(. != "preview")')"
checks_json="$(
  printf '%s\n' "$check_keys" | while IFS= read -r check_key; do
    [[ -n "$check_key" ]] || continue
    patterns="$(printf '%s' "$check_patterns_json" | jq -c --arg key "$check_key" '.[$key] // [$key]')"
    raw_status="$(
      printf '%s' "$pr_json" | jq -r --argjson patterns "$patterns" '
        [.statusCheckRollup[]?
          | select(.name as $name | ($patterns | any(. as $pattern | ($name | ascii_downcase | contains($pattern)))))
          | .conclusion
        ][0] // "PENDING"
      '
    )"
    jq -n --arg key "$check_key" --arg value "$(normalize_check_status "$raw_status")" '{($key): $value}'
  done | jq -s 'add // {}'
)"
preview_patterns="$(printf '%s' "$check_patterns_json" | jq -c '.preview // ["preview","deploy"]')"
preview_status_raw="$(
  printf '%s' "$pr_json" | jq -r --argjson patterns "$preview_patterns" '
    [.statusCheckRollup[]?
      | select(.name as $name | ($patterns | any(. as $pattern | ($name | ascii_downcase | contains($pattern)))))
      | .conclusion
    ][0] // "MISSING"
  '
)"
preview_url="$(
  printf '%s' "$pr_json" | jq -r --argjson patterns "$preview_patterns" '
    [.statusCheckRollup[]?
      | select(.name as $name | ($patterns | any(. as $pattern | ($name | ascii_downcase | contains($pattern)))))
      | .detailsUrl
    ][0] // empty
  '
)"

case "$preview_status_raw" in
  SUCCESS|NEUTRAL)
    preview_status="ready"
    ;;
  MISSING)
    preview_status="missing"
    ;;
  *)
    preview_status="pending"
    ;;
esac

jq -n \
  --argjson approved "$(printf '%s' "$pr_json" | jq '.reviewDecision == "APPROVED"')" \
  --argjson merged "$(printf '%s' "$pr_json" | jq '.mergeStateStatus == "MERGED"')" \
  --argjson checks "$checks_json" \
  --arg preview_status "$preview_status" \
  --arg preview_url "$preview_url" \
  '{
    pull_request: {
      approved: $approved,
      merged: $merged
    },
    checks: $checks,
    preview: {
      status: $preview_status,
      url: $preview_url
    }
  }' > "$feature_dir/state/github-state.json"
