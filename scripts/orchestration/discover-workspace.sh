#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/workspace_bootstrap.sh"

search_roots=()
workspace_root=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --search-root)
      search_roots+=("$2")
      shift 2
      ;;
    --workspace-root)
      workspace_root="$2"
      shift 2
      ;;
    --output)
      output_path="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ${#search_roots[@]} -eq 0 || -z "$workspace_root" || -z "$output_path" ]]; then
  echo "at least one search root, workspace root, and output are required" >&2
  exit 1
fi

require_command git
require_command jq

workspace_root="$(absolute_path "$workspace_root")"
tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT

candidate_paths="$tmp_dir/candidates.txt"
: > "$candidate_paths"

normalized_search_roots=()
for search_root in "${search_roots[@]}"; do
  if [[ ! -d "$search_root" ]]; then
    echo "search root does not exist: $search_root" >&2
    exit 1
  fi

  normalized_root="$(absolute_path "$search_root")"
  normalized_search_roots+=("$normalized_root")
  find "$normalized_root" \
    \( -type d \( -name node_modules -o -name .worktrees -o -name vendor \) -prune \) -o \
    \( -name .git -print -prune \) \
    | while IFS= read -r git_entry; do
        dirname "$git_entry"
      done >> "$candidate_paths"
done

sort -u "$candidate_paths" > "$tmp_dir/candidates.sorted.txt"
entries_path="$tmp_dir/repositories.jsonl"
: > "$entries_path"

while IFS= read -r candidate_path; do
  [[ -n "$candidate_path" ]] || continue
  repo_path="$(absolute_path "$candidate_path")"
  [[ "$repo_path" != "$workspace_root" ]] || continue

  if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
    continue
  fi

  remotes='{}'
  first_remote_url=""
  while IFS= read -r remote_name; do
    [[ -n "$remote_name" ]] || continue
    remote_url="$(git -C "$repo_path" remote get-url "$remote_name")"
    [[ -n "$first_remote_url" ]] || first_remote_url="$remote_url"
    remotes="$(jq -c --arg name "$remote_name" --arg url "$remote_url" '. + {($name): $url}' <<<"$remotes")"
  done < <(git -C "$repo_path" remote)

  if [[ -n "$first_remote_url" ]]; then
    forge="$(remote_host "$first_remote_url")"
  else
    forge="local"
  fi

  branch="$(git -C "$repo_path" branch --show-current 2>/dev/null || true)"
  if [[ -n "$(git -C "$repo_path" status --porcelain)" ]]; then
    dirty=true
  else
    dirty=false
  fi

  readme=false
  agents=false
  ai_index=false
  [[ -f "$repo_path/README.md" ]] && readme=true
  [[ -f "$repo_path/AGENTS.md" ]] && agents=true
  [[ -f "$repo_path/AI-INDEX.md" ]] && ai_index=true

  jq -cn \
    --arg name "$(basename "$repo_path")" \
    --arg path "$repo_path" \
    --arg branch "$branch" \
    --arg forge "$forge" \
    --argjson dirty "$dirty" \
    --argjson remotes "$remotes" \
    --argjson readme "$readme" \
    --argjson agents "$agents" \
    --argjson ai_index "$ai_index" \
    '{
      name: $name,
      path: $path,
      branch: $branch,
      dirty: $dirty,
      forge: $forge,
      remotes: $remotes,
      signals: {
        readme: $readme,
        agents: $agents,
        ai_index: $ai_index
      }
    }' >> "$entries_path"
done < "$tmp_dir/candidates.sorted.txt"

repositories="$(jq -s 'sort_by(.path)' "$entries_path")"
fingerprint="$(jq -S -c '.' <<<"$repositories" | sha256_stream)"
search_roots_json="$(printf '%s\n' "${normalized_search_roots[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"

mkdir -p "$(dirname "$output_path")"
jq -n \
  --argjson schema_version 1 \
  --arg workspace_root "$workspace_root" \
  --argjson search_roots "$search_roots_json" \
  --arg fingerprint "$fingerprint" \
  --argjson repositories "$repositories" \
  '{
    schema_version: $schema_version,
    workspace_root: $workspace_root,
    search_roots: $search_roots,
    fingerprint: $fingerprint,
    repositories: $repositories
  }' > "$tmp_dir/inventory.json"
mv "$tmp_dir/inventory.json" "$output_path"
