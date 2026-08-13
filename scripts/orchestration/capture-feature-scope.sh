#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/feature_paths.sh"
source "$script_dir/lib/workspace_config.sh"
source "$script_dir/lib/git_subject.sh"

require_command git
require_command jq

feature_dir=""
repository_id=""
base_revision=""
head_revision=""
captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
config_path="$(default_workspace_config_path "$script_dir")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature-dir)
      feature_dir="$2"
      shift 2
      ;;
    --config)
      config_path="$2"
      shift 2
      ;;
    --repository)
      repository_id="$2"
      shift 2
      ;;
    --base)
      base_revision="$2"
      shift 2
      ;;
    --head)
      head_revision="$2"
      shift 2
      ;;
    --now)
      captured_at="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$feature_dir" || -z "$repository_id" || \
      -z "$base_revision" || -z "$head_revision" ]]; then
  echo "feature directory, repository, base, and head are required" >&2
  exit 1
fi
require_workspace_config "$config_path"

scope_path="$(feature_scope_path "$feature_dir")"
if [[ ! -f "$scope_path" ]]; then
  echo "feature scope is required: $scope_path" >&2
  exit 1
fi

repository_path="$(workspace_repository_path "$config_path" "$repository_id")" || {
  echo "unknown workspace repository: $repository_id" >&2
  exit 1
}
if [[ ! -d "$repository_path/.git" && ! -f "$repository_path/.git" ]]; then
  echo "configured repository is not a Git worktree: $repository_path" >&2
  exit 1
fi

repository_role="$(jq -r --arg id "$repository_id" \
  '.repositories[$id].role // empty' "$config_path")"
if [[ -z "$repository_role" ]]; then
  echo "repository role is required: $repository_id" >&2
  exit 1
fi

base_oid="$(git_commit_oid "$repository_path" "$base_revision")"
if [[ "$head_revision" == "WORKTREE" ]]; then
  head_oid="$(git_commit_oid "$repository_path" HEAD)"
  subject="$(git_worktree_subject "$repository_path")"
else
  head_oid="$(git_commit_oid "$repository_path" "$head_revision")"
  subject="$(git_commit_subject "$repository_path" "$head_revision")"
fi
changed_paths="$(git_changed_paths_json \
  "$repository_path" "$base_oid" "$head_revision")"
dependencies="$(jq -c --arg id "$repository_id" \
  '.repositories[$id].dependencies // [] | sort' "$config_path")"

policy_version="null"
if policy_path="$(workspace_quality_policy_path "$config_path" 2>/dev/null)" && \
   [[ -f "$policy_path" ]]; then
  policy_version="$(jq -c '.policy_version // null' "$policy_path")"
fi

repository_record="$(jq -cn \
  --arg id "$repository_id" \
  --arg role "$repository_role" \
  --arg subject "$subject" \
  --arg base "$base_oid" \
  --arg head "$head_oid" \
  --arg captured_at "$captured_at" \
  --argjson changed_paths "$changed_paths" \
  --argjson dependencies "$dependencies" \
  '{
    id: $id,
    role: $role,
    subject: $subject,
    base: $base,
    head: $head,
    changed_paths: $changed_paths,
    dependencies: $dependencies,
    captured_at: $captured_at
  }')"

scope_tmp="$(mktemp "$(dirname "$scope_path")/.scope.XXXXXX")"
jq \
  --arg feature_id "$(feature_id_from_dir "$feature_dir")" \
  --arg repository_id "$repository_id" \
  --argjson repository "$repository_record" \
  --argjson policy_version "$policy_version" \
  'if .feature_id != $feature_id then
     error("feature scope ID does not match its directory")
   else
     .repositories = (
       ([.repositories[]? | select(.id != $repository_id)] + [$repository])
       | sort_by(.id)
     )
     | .policy_version = $policy_version
   end' "$scope_path" > "$scope_tmp"
mv "$scope_tmp" "$scope_path"
