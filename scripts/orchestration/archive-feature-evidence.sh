#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$script_dir/lib/feature_paths.sh"; source "$script_dir/lib/workspace_config.sh"
feature_dir=""; config_path="$(default_workspace_config_path "$script_dir")"; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; --now) now="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac; done
[[ -n "$feature_dir" ]] || { echo "feature directory is required" >&2; exit 1; }; require_workspace_config "$config_path"
policy="$(workspace_quality_policy_path "$config_path")"; validate_quality_policy "$policy"; readiness="$(feature_readiness_path "$feature_dir")"; scope="$(feature_scope_path "$feature_dir")"
jq -e '.decision=="release-ready" and .status=="ready"' "$readiness" >/dev/null || { echo "release evidence can only be archived from a ready release-ready decision" >&2; exit 1; }
kind="$(jq -r '.release_archive.kind' "$policy")"
destination="$(workspace_quality_release_archive_path "$config_path")"
if [[ "$kind" == filesystem ]]; then
  mkdir -p "$destination"
elif [[ "$kind" == command ]]; then
  [[ -x "$destination" && -f "$destination" ]] || {
    echo "release archive command is unavailable or not executable: $destination" >&2
    exit 1
  }
else
  echo "unsupported release archive kind: $kind" >&2
  exit 1
fi
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
evidence_files=""; waiver_files=""; for f in "$feature_dir"/evidence/*.json; do [[ -f "$f" ]] && evidence_files="$evidence_files $f"; done; for f in "$feature_dir"/waivers/*.json; do [[ -f "$f" ]] && waiver_files="$waiver_files $f"; done
printf '[]\n' > "$scratch/evidence.json"; printf '[]\n' > "$scratch/waivers.json"
if [[ -n "$evidence_files" ]]; then jq -s . $evidence_files > "$scratch/evidence.json"; fi
if [[ -n "$waiver_files" ]]; then jq -s . $waiver_files > "$scratch/waivers.json"; fi
feature_id="$(feature_id_from_dir "$feature_dir")"
if [[ "$kind" == filesystem ]]; then
  final="$destination/$feature_id.json"
  tmp="$(mktemp "$destination/.release.XXXXXX")"
else
  final=""
  tmp="$scratch/release-record.json"
fi
jq -n --slurpfile r "$readiness" --slurpfile s "$scope" --slurpfile e "$scratch/evidence.json" --slurpfile w "$scratch/waivers.json" --arg now "$now" '
 {schema_version:"1",feature_id:$r[0].feature_id,decision:$r[0].decision,status:$r[0].status,policy_version:$s[0].policy_version,subjects:($s[0].repositories|map({key:.id,value:.subject})|from_entries),evidence:$e[0],waivers:$w[0],known_gaps:$r[0].known_gaps,archived_at:$now}' > "$tmp"
if [[ "$kind" == command ]]; then
  QUALITY_ARCHIVE_FEATURE_ID="$feature_id" \
  QUALITY_ARCHIVE_DECISION="release-ready" \
    "$destination" < "$tmp"
  exit $?
fi
if [[ -e "$final" ]]; then
  if jq -e --slurpfile existing "$final" 'del(.archived_at) == ($existing[0] | del(.archived_at))' "$tmp" >/dev/null; then
    rm -f "$tmp"
    exit 0
  fi
  rm -f "$tmp"
  echo "release archive record exists with different evidence: $final" >&2
  exit 1
fi
mv "$tmp" "$final"
