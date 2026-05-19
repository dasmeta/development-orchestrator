#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/workspace_config.sh"

feature_dir=""
stage=""
dry_run=false
config_path="$(default_workspace_config_path "$script_dir")"

build_prompt() {
  local requested_stage="$1"
  local repo_id="$2"
  local skill="$3"
  local intake_path="$4"

  cat <<EOF
Use the ${skill} skill in this repository to process the '${requested_stage}' stage for control feature $(basename "$feature_dir").

Target repository id: ${repo_id}
Control repo feature dir: ${feature_dir}
Control repo intake path: ${intake_path}

Work from this intake:
$(cat "$intake_path")
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature-dir)
      feature_dir="$2"
      shift 2
      ;;
    --stage)
      stage="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
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

if [[ -z "$feature_dir" || -z "$stage" ]]; then
  echo "feature directory and stage are required" >&2
  exit 1
fi
require_workspace_config "$config_path"

repo="$(workspace_stage_repository "$config_path" "$stage")"
if [[ -z "$repo" ]]; then
  echo "unknown stage: $stage" >&2
  exit 1
fi

intake_path="$feature_dir/intake.md"
if [[ ! -f "$intake_path" ]]; then
  echo "feature intake is required: $intake_path" >&2
  exit 1
fi

target_path=""
skill=""

target_path="$(workspace_repository_path "$config_path" "$repo")"
skill="$(workspace_stage_skill "$config_path" "$stage" "$repo")"

if [[ "$dry_run" != true && ( -z "$target_path" || -z "$skill" ) ]]; then
  echo "config with target path and skill is required for live execution" >&2
  exit 1
fi

mkdir -p "$feature_dir/state"

jq -n \
  --arg repo "$repo" \
  --arg stage "$stage" \
  --arg target_path "$target_path" \
  --arg skill "$skill" \
  --argjson dry_run "$dry_run" \
  '{
    repo: $repo,
    stage: $stage,
    target_path: $target_path,
    skill: $skill,
    dry_run: $dry_run
  }' > "$feature_dir/state/run-log.json"

if [[ "$dry_run" == true ]]; then
  exit 0
fi

prompt="$(build_prompt "$stage" "$repo" "$skill" "$intake_path")"
control_repo_root="$(cd "$script_dir/../.." && pwd)"
codex_bin="${CODEX_BIN:-codex}"

printf '%s\n' "$prompt" | "$codex_bin" exec \
  --full-auto \
  --skip-git-repo-check \
  -C "$target_path" \
  --add-dir "$control_repo_root" \
  -
