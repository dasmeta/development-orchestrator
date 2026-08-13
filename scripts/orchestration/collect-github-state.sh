#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/workspace_config.sh"

require_command jq

feature_dir=""
fixtures_dir=""
repo=""
repo_id=""
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
    --repo-id)
      repo_id="$2"
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
  if [[ "$(workspace_quality_mode "$config_path")" == "enforce" ]]; then
    echo "fixtures cannot be used for enforced GitHub evidence" >&2
    exit 1
  fi
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

pr_json="$(gh pr view "$pr_number" --repo "$repo" --json reviewDecision,mergeStateStatus,statusCheckRollup,url,headRefName,headRefOid,latestReviews)"

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
checks_with_urls_json="$(
  printf '%s\n' "$check_keys" | while IFS= read -r check_key; do
    [[ -n "$check_key" ]] || continue
    patterns="$(printf '%s' "$check_patterns_json" | jq -c --arg key "$check_key" '.[$key] // [$key]')"
    check_record="$(printf '%s' "$pr_json" | jq -c --argjson patterns "$patterns" '
      [.statusCheckRollup[]?
       | select(.name as $name | ($patterns | any(. as $pattern | ($name | ascii_downcase | contains($pattern)))))][0] // {}
    ')"
    raw_status="$(printf '%s' "$check_record" | jq -r '.conclusion // "PENDING"')"
    url="$(printf '%s' "$check_record" | jq -r '.detailsUrl // empty')"
    jq -n --arg key "$check_key" --arg status "$(normalize_check_status "$raw_status")" --arg url "$url" '{($key):{status:$status,url:$url}}'
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

if [[ -n "$repo_id" ]]; then
  mkdir -p "$feature_dir/state/github"
  jq -n \
    --arg repository_id "$repo_id" \
    --arg repo "$repo" \
    --arg url "$(printf '%s' "$pr_json" | jq -r '.url // empty')" \
    --arg head_ref "$(printf '%s' "$pr_json" | jq -r '.headRefName // empty')" \
    --arg head_oid "$(printf '%s' "$pr_json" | jq -r '.headRefOid // empty')" \
    --argjson approved "$(printf '%s' "$pr_json" | jq '.reviewDecision == "APPROVED"')" \
    --argjson merged "$(printf '%s' "$pr_json" | jq '.mergeStateStatus == "MERGED"')" \
    --argjson reviewers "$(printf '%s' "$pr_json" | jq '[.latestReviews[]? | select(.state=="APPROVED") | .author.login] | unique | sort')" \
    --argjson checks "$checks_with_urls_json" \
    --arg preview_status "$preview_status" --arg preview_url "$preview_url" '
      {repository_id:$repository_id,repository:$repo,pull_request:{approved:$approved,merged:$merged,url:$url,head_ref:$head_ref,head_oid:$head_oid,reviewers:$reviewers},checks:$checks,preview:{status:$preview_status,url:$preview_url}}
    ' > "$feature_dir/state/github/$repo_id.json"
  exit 0
fi

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
