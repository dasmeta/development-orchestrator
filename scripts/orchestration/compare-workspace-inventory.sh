#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/workspace_bootstrap.sh"

inventory_path=""
index_path=""
workspace_root=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory)
      inventory_path="$2"
      shift 2
      ;;
    --index)
      index_path="$2"
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

if [[ -z "$inventory_path" || -z "$index_path" || -z "$workspace_root" || -z "$output_path" ]]; then
  echo "inventory, index, workspace root, and output are required" >&2
  exit 1
fi

require_command jq
[[ -f "$inventory_path" ]] || { echo "inventory does not exist: $inventory_path" >&2; exit 1; }
[[ -f "$index_path" ]] || { echo "repository index does not exist: $index_path" >&2; exit 1; }
workspace_root="$(absolute_path "$workspace_root")"

tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT
for list in present misplaced missing unindexed remote_mismatches matched; do
  : > "$tmp_dir/$list.jsonl"
done

while IFS=$'\t' read -r repo_id target_path expected_origin; do
  expected_path="$workspace_root/$target_path"
  exact_entry="$(jq -c --arg path "$expected_path" '.repositories | map(select(.path == $path)) | first // empty' "$inventory_path")"

  if [[ -n "$exact_entry" ]]; then
    actual_origin="$(jq -r '.remotes.origin // empty' <<<"$exact_entry")"
    jq -cn --arg path "$expected_path" '{path: $path}' >> "$tmp_dir/matched.jsonl"
    if [[ -n "$expected_origin" && -n "$actual_origin" && "$expected_origin" != "$actual_origin" ]]; then
      jq -cn \
        --arg id "$repo_id" \
        --arg path "$expected_path" \
        --arg expected_origin "$expected_origin" \
        --arg actual_origin "$actual_origin" \
        '{id: $id, path: $path, expected_origin: $expected_origin, actual_origin: $actual_origin}' \
        >> "$tmp_dir/remote_mismatches.jsonl"
    else
      jq -cn --arg id "$repo_id" '$id' >> "$tmp_dir/present.jsonl"
    fi
    continue
  fi

  remote_entry=""
  if [[ -n "$expected_origin" ]]; then
    remote_entry="$(jq -c --arg origin "$expected_origin" '
      .repositories
      | map(select([.remotes[]?] | index($origin)))
      | first // empty
    ' "$inventory_path")"
  fi

  if [[ -n "$remote_entry" ]]; then
    actual_path="$(jq -r '.path' <<<"$remote_entry")"
    jq -cn --arg path "$actual_path" '{path: $path}' >> "$tmp_dir/matched.jsonl"
    jq -cn \
      --arg id "$repo_id" \
      --arg expected_path "$expected_path" \
      --arg actual_path "$actual_path" \
      '{id: $id, expected_path: $expected_path, actual_path: $actual_path}' \
      >> "$tmp_dir/misplaced.jsonl"
  else
    jq -c --arg id "$repo_id" '.repositories[$id] | {id, target_path, required, remotes}' "$index_path" \
      >> "$tmp_dir/missing.jsonl"
  fi
done < <(jq -r '.repositories | to_entries | sort_by(.key)[] | [.key, .value.target_path, (.value.remotes.origin // "")] | @tsv' "$index_path")

matched_paths="$(jq -s 'map(.path)' "$tmp_dir/matched.jsonl")"
jq -c --argjson matched "$matched_paths" '.repositories[] | select(.path as $path | $matched | index($path) | not)' "$inventory_path" \
  >> "$tmp_dir/unindexed.jsonl"

present="$(jq -s 'sort' "$tmp_dir/present.jsonl")"
misplaced="$(jq -s 'sort_by(.id)' "$tmp_dir/misplaced.jsonl")"
missing="$(jq -s 'sort_by(.id)' "$tmp_dir/missing.jsonl")"
unindexed="$(jq -s 'sort_by(.path)' "$tmp_dir/unindexed.jsonl")"
remote_mismatches="$(jq -s 'sort_by(.id)' "$tmp_dir/remote_mismatches.jsonl")"

mkdir -p "$(dirname "$output_path")"
jq -n \
  --argjson schema_version 1 \
  --arg inventory_fingerprint "$(jq -r '.fingerprint // ""' "$inventory_path")" \
  --argjson present "$present" \
  --argjson misplaced "$misplaced" \
  --argjson missing "$missing" \
  --argjson unindexed "$unindexed" \
  --argjson remote_mismatches "$remote_mismatches" \
  '{
    schema_version: $schema_version,
    inventory_fingerprint: $inventory_fingerprint,
    present: $present,
    misplaced: $misplaced,
    missing: $missing,
    unindexed: $unindexed,
    remote_mismatches: $remote_mismatches,
    has_changes: (([$misplaced, $missing, $unindexed, $remote_mismatches] | map(length) | add) > 0)
  }' > "$tmp_dir/delta.json"
mv "$tmp_dir/delta.json" "$output_path"
