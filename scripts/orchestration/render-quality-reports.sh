#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$script_dir/lib/feature_paths.sh"
feature_dir=""
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac; done
[[ -n "$feature_dir" ]] || { echo "feature directory is required" >&2; exit 1; }
readiness="$(feature_readiness_path "$feature_dir")"; scope="$(feature_scope_path "$feature_dir")"; plan="$feature_dir/state/gate-plan.json"
for path in "$readiness" "$scope" "$plan"; do [[ -f "$path" ]] || { echo "quality report input missing: $path" >&2; exit 1; }; done
if ! jq -e --slurpfile plan "$plan" '.subject_fingerprint == $plan[0].subject_fingerprint' "$readiness" >/dev/null; then
  echo "refusing to render reports from stale readiness" >&2; exit 1
fi
readiness_tmp="$(mktemp "$feature_dir/state/.readiness-md.XXXXXX")"; summary_tmp="$(mktemp "$feature_dir/state/.pr-summary.XXXXXX")"
jq -njr --slurpfile readiness "$readiness" --slurpfile scope "$scope" -f "$script_dir/jq/render-readiness.jq" > "$readiness_tmp"
jq -njr --slurpfile readiness "$readiness" --slurpfile scope "$scope" --slurpfile plan "$plan" -f "$script_dir/jq/render-pr-summary.jq" > "$summary_tmp"
mv "$readiness_tmp" "$feature_dir/state/readiness.md"; mv "$summary_tmp" "$feature_dir/state/pr-summary.md"
