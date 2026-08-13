#!/usr/bin/env bash

set -euo pipefail

workspace_config_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$workspace_config_lib_dir/quality_config.sh"
unset workspace_config_lib_dir

default_workspace_config_path() {
  local script_dir="$1"
  local repo_root
  local active_config
  local example_config

  repo_root="$(cd "$script_dir/../.." && pwd)"
  active_config="$repo_root/config/workspace.json"
  example_config="$repo_root/config/workspace.example.json"

  if [[ -f "$active_config" ]]; then
    echo "$active_config"
  elif [[ -f "$example_config" ]]; then
    echo "$example_config"
  else
    echo "$active_config"
  fi
}

require_workspace_config() {
  local config_path="$1"
  if [[ ! -f "$config_path" ]]; then
    echo "workspace config is required: $config_path" >&2
    exit 1
  fi
}

workspace_initial_stage() {
  local config_path="$1"
  jq -r '.initial_stage // (.stages[0].id // empty)' "$config_path"
}

workspace_repository_ids_json() {
  local config_path="$1"
  jq -c '.repositories | keys_unsorted' "$config_path"
}

workspace_stage_repository() {
  local config_path="$1"
  local stage="$2"
  jq -r --arg stage "$stage" \
    '.stages[]? | select(.id == $stage) | .repository // empty' \
    "$config_path"
}

workspace_stage_skill() {
  local config_path="$1"
  local stage="$2"
  local repo_id="$3"
  jq -r --arg stage "$stage" --arg repo_id "$repo_id" \
    '(
      .stages[]? | select(.id == $stage) | .skill
    ) // .repositories[$repo_id].skill // empty' \
    "$config_path"
}

workspace_repository_path() {
  local config_path="$1"
  local repo_id="$2"
  local configured_path

  configured_path="$(jq -r --arg repo_id "$repo_id" \
    '.repositories[$repo_id].path // empty' "$config_path")"

  if [[ -z "$configured_path" ]]; then
    return 1
  fi

  resolve_config_relative_path "$config_path" "$configured_path"
}

workspace_next_stage() {
  local config_path="$1"
  local current_stage="$2"
  jq -r --arg current "$current_stage" '
    .stages as $stages
    | ($stages | map(.id) | index($current)) as $idx
    | if $idx == null then empty else ($stages[$idx + 1].id // empty) end
  ' "$config_path"
}

workspace_advance_when_path() {
  local config_path="$1"
  jq -r '.advance_when.path // ".pull_request.approved"' "$config_path"
}

workspace_advance_when_equals_json() {
  local config_path="$1"
  jq -c '.advance_when.equals // true' "$config_path"
}

workspace_merge_ready_reason() {
  local config_path="$1"
  jq -r '.mergeability.ready_reason // "all_configured_gates_green"' "$config_path"
}

workspace_merge_incomplete_reason() {
  local config_path="$1"
  jq -r '.mergeability.incomplete_reason // "configured_gates_incomplete"' "$config_path"
}
