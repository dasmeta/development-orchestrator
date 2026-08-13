#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/feature_paths.sh"
source "$script_dir/lib/workspace_config.sh"

feature_dir=""
stage=""
dry_run=false
run_id=""
repair_brief=""
sandbox="workspace-write"
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
  if [[ -n "$repair_brief" ]]; then
    cat <<EOF

Repair only the findings in this repair brief:
$(jq -S . "$repair_brief")

Do not modify approved claims, architecture constraints, validation sources,
quality policy, provider configuration, waivers, or evidence records.
If one of those must change, stop and report the owning stage.
EOF
  fi
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
    --run-id)
      run_id="$2"
      shift 2
      ;;
    --repair-brief)
      repair_brief="$2"
      shift 2
      ;;
    --sandbox)
      sandbox="$2"
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

if [[ -z "$feature_dir" || -z "$stage" ]]; then
  echo "feature directory and stage are required" >&2
  exit 1
fi
require_workspace_config "$config_path"
[[ "$sandbox" == "read-only" || "$sandbox" == "workspace-write" ]] || {
  echo "sandbox must be read-only or workspace-write" >&2
  exit 1
}
if [[ -z "$run_id" ]]; then
  run_id="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi
[[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || {
  echo "invalid run ID: $run_id" >&2
  exit 1
}

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

finding_ids='[]'
if [[ -n "$repair_brief" ]]; then
  [[ -f "$repair_brief" ]] || { echo "repair brief is required: $repair_brief" >&2; exit 1; }
  target_role="$(jq -r --arg repo "$repo" '.repositories[$repo].role // empty' "$config_path")"
  if ! jq -e --arg repo "$repo" --arg role "$target_role" '
    .human_action_required == false and
    all(.repairs[]; ((.repository_id? // .owner) == $repo or (.repository_id? // .owner) == $role))
  ' "$repair_brief" >/dev/null; then
    echo "repair brief targets another repository or requires human action" >&2
    exit 1
  fi
  finding_ids="$(jq -c '[.repairs[].finding_id] | unique | sort' "$repair_brief")"
fi

if [[ "$dry_run" != true && ( -z "$target_path" || -z "$skill" ) ]]; then
  echo "config with target path and skill is required for live execution" >&2
  exit 1
fi

run_dir="$(feature_run_history_dir "$feature_dir")"
mkdir -p "$run_dir"
run_path="$run_dir/$run_id.json"
[[ ! -e "$run_path" ]] || { echo "run record already exists: $run_id" >&2; exit 1; }
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_run_record() {
  local exit_status="$1" protected_json="$2" completed_at tmp
  completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp "$run_dir/.run.XXXXXX")"
  jq -n --arg run_id "$run_id" --arg repo "$repo" --arg stage "$stage" --arg target_path "$target_path" --arg skill "$skill" --arg sandbox "$sandbox" --arg started_at "$started_at" --arg completed_at "$completed_at" --argjson dry_run "$dry_run" --argjson finding_ids "$finding_ids" --argjson exit_status "$exit_status" --argjson protected_paths "$protected_json" \
    '{run_id:$run_id,repo:$repo,stage:$stage,target_path:$target_path,skill:$skill,sandbox:$sandbox,finding_ids:$finding_ids,started_at:$started_at,completed_at:$completed_at,exit_status:$exit_status,dry_run:$dry_run,protected_path_changes:$protected_paths}' > "$tmp"
  mv "$tmp" "$run_path"
  cp "$run_path" "$feature_dir/state/run-log.json"
}

if [[ "$dry_run" == true ]]; then
  write_run_record 0 '[]'
  exit 0
fi

prompt="$(build_prompt "$stage" "$repo" "$skill" "$intake_path")"
control_repo_root="$(cd "$script_dir/../.." && pwd)"
codex_bin="${CODEX_BIN:-codex}"

before_paths="$(mktemp)"
if git -C "$target_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$target_path" status --porcelain=v1 -uall | sed 's/^...//' | sort -u > "$before_paths"
fi

set +e
if [[ -n "$repair_brief" ]]; then
  printf '%s\n' "$prompt" | "$codex_bin" exec --full-auto --sandbox "$sandbox" --skip-git-repo-check -C "$target_path" -
else
  printf '%s\n' "$prompt" | "$codex_bin" exec --full-auto --sandbox "$sandbox" --skip-git-repo-check -C "$target_path" --add-dir "$control_repo_root" -
fi
exit_status=$?
set -e

protected='[]'
if git -C "$target_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  after_paths="$(mktemp)"; git -C "$target_path" status --porcelain=v1 -uall | sed 's/^...//' | sort -u > "$after_paths"
  new_paths="$(comm -13 "$before_paths" "$after_paths")"
  if policy_path="$(workspace_quality_policy_path "$config_path" 2>/dev/null)" && [[ -f "$policy_path" ]]; then
    protected="$(printf '%s\n' "$new_paths" | jq -Rsc --slurpfile policy "$policy_path" 'split("\n")[:-1] | map(select(. as $path | any($policy[0].protected_path_regex[]; $path|test(.)))) | sort')"
  fi
fi
write_run_record "$exit_status" "$protected"
if [[ "$(printf '%s' "$protected" | jq length)" -gt 0 ]]; then
  echo "PROTECTED_PATH_CHANGED: repair modified protected paths" >&2
  exit 25
fi
exit "$exit_status"
