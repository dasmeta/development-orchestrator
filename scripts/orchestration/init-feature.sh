#!/usr/bin/env bash

set -euo pipefail

feature_id=""
title=""
repo_root="${PWD}"

render_template() {
  local src="$1"
  local dst="$2"

  sed \
    -e "s/{{FEATURE_ID}}/${feature_id}/g" \
    -e "s/{{TITLE}}/${title//\//\\/}/g" \
    "$src" > "$dst"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature-id)
      feature_id="$2"
      shift 2
      ;;
    --title)
      title="$2"
      shift 2
      ;;
    --repo-root)
      repo_root="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$feature_id" || -z "$title" ]]; then
  echo "feature id and title are required" >&2
  exit 1
fi

feature_dir="$repo_root/features/$feature_id"
mkdir -p \
  "$feature_dir/evidence" \
  "$feature_dir/waivers" \
  "$feature_dir/state/runs" \
  "$feature_dir/state/provider-runs"

render_template "$repo_root/templates/features/intake.md" "$feature_dir/intake.md"
render_template "$repo_root/templates/features/status.md" "$feature_dir/state/status.md"
render_template "$repo_root/templates/features/scope.json" "$feature_dir/scope.json"
render_template "$repo_root/templates/features/claims.json" "$feature_dir/claims.json"
render_template \
  "$repo_root/templates/features/architecture.json" \
  "$feature_dir/architecture.json"

echo "Initialized $feature_id: $title"
