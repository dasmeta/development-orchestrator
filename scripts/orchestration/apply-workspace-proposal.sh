#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/workspace_bootstrap.sh"

proposal_path=""
confirm_token=""
dry_run=false
print_token=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposal)
      proposal_path="$2"
      shift 2
      ;;
    --confirm)
      confirm_token="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --print-token)
      print_token=true
      shift
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$proposal_path" ]]; then
  echo "--proposal is required" >&2
  exit 1
fi

require_command git
require_command jq
bash "$script_dir/validate-workspace-proposal.sh" --proposal "$proposal_path"
expected_token="$(proposal_token "$proposal_path")"

if [[ "$print_token" == true ]]; then
  printf '%s\n' "$expected_token"
  exit 0
fi

workspace_root_raw="$(jq -r '.workspace.root' "$proposal_path")"
if [[ ! -d "$workspace_root_raw" ]]; then
  echo "workspace root does not exist: $workspace_root_raw" >&2
  exit 1
fi
workspace_root="$(absolute_path "$workspace_root_raw")"

operation_lines() {
  jq -r --arg root "$workspace_root" '
    .repositories
    | sort_by(.target_path)[]
    | [.materialization, .id, ($root + "/" + .target_path), .source_path]
    | @tsv
  ' "$proposal_path"
}

if [[ "$dry_run" == true ]]; then
  operation_lines
  exit 0
fi

if [[ "$(jq -r '.status' "$proposal_path")" != "approved" || "$(jq -r '.approval.confirmed' "$proposal_path")" != "true" ]]; then
  echo "proposal must be approved and confirmed before apply" >&2
  exit 1
fi

if [[ -z "$confirm_token" ]]; then
  echo "confirmation token is required; use --print-token after reviewing the dry run" >&2
  exit 1
fi

if [[ "$confirm_token" != "$expected_token" ]]; then
  echo "confirmation token does not match this proposal" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT
candidate_root="$tmp_dir/generated"
bash "$script_dir/render-workspace-files.sh" --proposal "$proposal_path" --output-root "$candidate_root"

generated_paths=(
  "config/repository-index.json"
  "config/workspace.json"
  "overlays/repository-index.md"
  "WORKSPACE.md"
)
allow_update="$(jq -r '.allow_update' "$proposal_path")"
for generated_path in "${generated_paths[@]}"; do
  existing="$workspace_root/$generated_path"
  candidate="$candidate_root/$generated_path"
  if [[ -e "$existing" ]] && ! cmp -s "$existing" "$candidate" && [[ "$allow_update" != "true" ]]; then
    echo "generated file differs and allow_update is false: $generated_path" >&2
    exit 1
  fi
done

actual_state="$tmp_dir/actual-state.jsonl"
: > "$actual_state"

while IFS=$'\t' read -r operation repo_id target_path source_path; do
  proposed_origin="$(jq -r --arg id "$repo_id" '.repositories[] | select(.id == $id) | .remotes.origin // empty' "$proposal_path")"

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    if ! git -C "$target_path" rev-parse --git-dir >/dev/null 2>&1; then
      echo "target exists but is not a Git repository: $target_path" >&2
      exit 1
    fi
    actual_origin="$(git -C "$target_path" remote get-url origin 2>/dev/null || true)"
    if [[ -n "$proposed_origin" && -n "$actual_origin" && "$proposed_origin" != "$actual_origin" ]]; then
      echo "target remote mismatch for $repo_id: expected $proposed_origin, found $actual_origin" >&2
      exit 1
    fi
    jq -cn --arg id "$repo_id" --arg state "already_present" '{id: $id, state: $state}' >> "$actual_state"
    continue
  fi

  case "$operation" in
    move|symlink)
      if [[ ! -d "$source_path" ]] || ! git -C "$source_path" rev-parse --git-dir >/dev/null 2>&1; then
        echo "source is not a Git repository for $repo_id: $source_path" >&2
        exit 1
      fi
      if [[ "$operation" == "move" && -n "$(git -C "$source_path" status --porcelain)" ]]; then
        allow_dirty="$(jq -r --arg id "$repo_id" '.repositories[] | select(.id == $id) | .allow_dirty' "$proposal_path")"
        if [[ "$allow_dirty" != "true" ]]; then
          echo "dirty repository move is not approved: $repo_id" >&2
          exit 1
        fi
      fi
      ;;
    clone)
      [[ -n "$proposed_origin" ]] || { echo "clone origin is required for $repo_id" >&2; exit 1; }
      ;;
    keep)
      echo "keep target is missing: $target_path" >&2
      exit 1
      ;;
  esac

  jq -cn --arg id "$repo_id" --arg state "pending" '{id: $id, state: $state}' >> "$actual_state"
done < <(operation_lines)

proposal_id="$(jq -r '.proposal_id' "$proposal_path")"
journal_dir="$workspace_root/workspace/bootstrap/$proposal_id"
journal_path="$journal_dir/apply-journal.json"
mkdir -p "$journal_dir"

operations_json="$(jq -s '.' "$actual_state")"
jq -n \
  --arg proposal_id "$proposal_id" \
  --arg token "$expected_token" \
  --arg status "in_progress" \
  --argjson operations "$operations_json" \
  '{proposal_id: $proposal_id, confirmation_token: $token, status: $status, operations: $operations}' \
  > "$journal_path.tmp"
mv "$journal_path.tmp" "$journal_path"

completed_moves_sources=()
completed_moves_targets=()
created_symlinks=()
apply_failed=false
failed_repo=""

update_journal_operation() {
  local repo_id="$1"
  local state="$2"
  jq --arg id "$repo_id" --arg state "$state" '
    (.operations[] | select(.id == $id) | .state) = $state
  ' "$journal_path" > "$journal_path.tmp"
  mv "$journal_path.tmp" "$journal_path"
}

while IFS=$'\t' read -r operation repo_id target_path source_path; do
  current_state="$(jq -r --arg id "$repo_id" '.operations[] | select(.id == $id) | .state' "$journal_path")"
  if [[ "$current_state" == "already_present" ]]; then
    continue
  fi

  mkdir -p "$(dirname "$target_path")"
  case "$operation" in
    move)
      if mv "$source_path" "$target_path"; then
        completed_moves_sources+=("$source_path")
        completed_moves_targets+=("$target_path")
      else
        apply_failed=true
      fi
      ;;
    symlink)
      if ln -s "$source_path" "$target_path"; then
        created_symlinks+=("$target_path")
      else
        apply_failed=true
      fi
      ;;
    clone)
      origin="$(jq -r --arg id "$repo_id" '.repositories[] | select(.id == $id) | .remotes.origin' "$proposal_path")"
      git clone --quiet "$origin" "$target_path" || apply_failed=true
      ;;
    keep)
      git -C "$target_path" rev-parse --git-dir >/dev/null 2>&1 || apply_failed=true
      ;;
  esac

  if [[ "$apply_failed" == true ]]; then
    failed_repo="$repo_id"
    update_journal_operation "$repo_id" "failed"
    break
  fi
  update_journal_operation "$repo_id" "complete"
done < <(operation_lines)

if [[ "$apply_failed" == true ]]; then
  recovery_required=false

  for ((index=${#created_symlinks[@]} - 1; index >= 0; index--)); do
    link_path="${created_symlinks[$index]}"
    if [[ -L "$link_path" ]]; then
      unlink "$link_path" || recovery_required=true
    fi
  done

  for ((index=${#completed_moves_targets[@]} - 1; index >= 0; index--)); do
    source_path="${completed_moves_sources[$index]}"
    target_path="${completed_moves_targets[$index]}"
    if [[ ! -e "$source_path" ]] && [[ -e "$target_path" ]]; then
      mv "$target_path" "$source_path" || recovery_required=true
    else
      recovery_required=true
    fi
  done

  if [[ "$recovery_required" == true ]]; then
    final_status="recovery_required"
  else
    final_status="rolled_back"
  fi
  jq --arg status "$final_status" --arg failed_repo "$failed_repo" '.status = $status | .failed_repository = $failed_repo' "$journal_path" > "$journal_path.tmp"
  mv "$journal_path.tmp" "$journal_path"
  echo "workspace apply failed for $failed_repo; journal: $journal_path" >&2
  exit 1
fi

for generated_path in "${generated_paths[@]}"; do
  mkdir -p "$(dirname "$workspace_root/$generated_path")"
  cp "$candidate_root/$generated_path" "$workspace_root/$generated_path.tmp"
  mv "$workspace_root/$generated_path.tmp" "$workspace_root/$generated_path"
done

while IFS=$'\t' read -r _operation repo_id target_path _source_path; do
  if ! git -C "$target_path" rev-parse --git-dir >/dev/null 2>&1; then
    jq --arg id "$repo_id" '.status = "recovery_required" | .verification_failure = $id' "$journal_path" > "$journal_path.tmp"
    mv "$journal_path.tmp" "$journal_path"
    echo "workspace verification failed for $repo_id" >&2
    exit 1
  fi
done < <(operation_lines)

jq '.status = "complete"' "$journal_path" > "$journal_path.tmp"
mv "$journal_path.tmp" "$journal_path"
