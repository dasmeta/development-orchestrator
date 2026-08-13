#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$script_dir/lib/feature_paths.sh"; source "$script_dir/lib/workspace_config.sh"
feature_dir=""; config_path="$(default_workspace_config_path "$script_dir")"
while [[ $# -gt 0 ]]; do case "$1" in --feature-dir) feature_dir="$2"; shift 2;; --config) config_path="$2"; shift 2;; *) echo "unknown arg: $1" >&2; exit 1;; esac; done
[[ -n "$feature_dir" ]] || { echo "feature directory is required" >&2; exit 1; }
manifest="$(feature_manifest_path "$feature_dir")"; if [[ -f "$manifest" ]]; then version="$(jq -r '.quality.schema_version // "1"' "$manifest")"; [[ "$version" == 1 ]] || { echo "future quality schema version requires explicit migration: $version" >&2; exit 1; }; fi
feature_id="$(feature_id_from_dir "$feature_dir")"; mkdir -p "$feature_dir/evidence" "$feature_dir/waivers" "$feature_dir/state/runs" "$feature_dir/state/provider-runs"
for name in scope claims architecture; do path="$feature_dir/$name.json"; if [[ ! -e "$path" ]]; then sed "s/{{FEATURE_ID}}/$feature_id/g" "$script_dir/../../templates/features/$name.json" > "$path"; fi; done
if [[ -f "$manifest" ]]; then tmp="$(mktemp)"; jq --arg mode "$(workspace_quality_mode "$config_path")" '.quality //={schema_version:"1",mode:$mode,scope:"../scope.json",claims:"../claims.json",architecture:"../architecture.json",gate_plan:"gate-plan.json",readiness:"readiness.json",current_decision:"stage-ready"}' "$manifest" > "$tmp"; mv "$tmp" "$manifest"; fi
