#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/common.sh"

proposal_path=""
output_root=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposal)
      proposal_path="$2"
      shift 2
      ;;
    --output-root)
      output_root="$2"
      shift 2
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$proposal_path" || -z "$output_root" ]]; then
  echo "proposal and output root are required" >&2
  exit 1
fi

require_command jq
bash "$script_dir/validate-workspace-proposal.sh" --proposal "$proposal_path"

tmp_dir="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp_dir"; exit $status' EXIT
mkdir -p "$tmp_dir/config" "$tmp_dir/overlays"

workspace_name="$(jq -r '.workspace.name' "$proposal_path")"
workspace_description="$(jq -r '.workspace.description' "$proposal_path")"

jq '{
  schema_version: 1,
  workspace: {
    name: .workspace.name,
    description: .workspace.description
  },
  repositories: (
    .repositories
    | map(del(.source_path, .materialization, .dirty, .allow_dirty))
    | map({key: .id, value: .})
    | from_entries
  ),
  stages: .stages
}' "$proposal_path" > "$tmp_dir/config/repository-index.json"

jq '{
  workspace: {
    name: .workspace.name,
    description: .workspace.description
  },
  initial_stage: (.stages[0].id // "definition"),
  advance_when: {
    path: ".pull_request.approved",
    equals: true
  },
  repositories: (
    .repositories
    | map({
        key: .id,
        value: {
          path: ("../" + .target_path),
          checkout: (if .materialization == "symlink" then "symlink" else "directory" end),
          remotes: .remotes,
          role: .role,
          description: .description
        }
      })
    | from_entries
  ),
  stages: .stages,
  github_state: {
    check_name_patterns: {
      implementation: ["implementation", "build", "test"],
      validation: ["validation", "e2e", "end-to-end"],
      preview: ["preview", "deploy"]
    }
  },
  mergeability: {
    ready_reason: "all_configured_gates_green",
    incomplete_reason: "configured_gates_incomplete",
    required: [
      {path: ".pull_request.merged", equals: true},
      {path: ".checks.implementation", equals: "green"},
      {path: ".checks.validation", equals: "green"}
    ]
  }
}' "$proposal_path" > "$tmp_dir/config/workspace.json"

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

escaped_name="$(escape_sed_replacement "$workspace_name")"
escaped_description="$(escape_sed_replacement "$workspace_description")"

sed \
  -e "s|{{WORKSPACE_NAME}}|$escaped_name|g" \
  -e "s|{{WORKSPACE_DESCRIPTION}}|$escaped_description|g" \
  "$repo_root/templates/workspace/repository-index.md" \
  > "$tmp_dir/overlays/repository-index.md"

jq -r '
  .repositories
  | sort_by(.target_path)[]
  | [
      (.name | gsub("\\|"; "\\|")),
      ("`" + .target_path + "`"),
      .role,
      (.authority | join(", ")),
      (if (.dependencies | length) == 0 then "—" else (.dependencies | join(", ")) end),
      (if .required then "yes" else "no" end)
    ]
  | "| " + join(" | ") + " |"
' "$proposal_path" >> "$tmp_dir/overlays/repository-index.md"

while IFS= read -r template_line || [[ -n "$template_line" ]]; do
  if [[ "$template_line" == "{{ROUTING_NOTES}}" ]]; then
    jq -r 'if (.routing_notes | length) == 0 then "- No additional routing notes." else .routing_notes[] | "- " + . end' "$proposal_path"
  else
    rendered_line="${template_line//\{\{WORKSPACE_NAME\}\}/$workspace_name}"
    rendered_line="${rendered_line//\{\{WORKSPACE_DESCRIPTION\}\}/$workspace_description}"
    printf '%s\n' "$rendered_line"
  fi
done < "$repo_root/templates/workspace/WORKSPACE.md" > "$tmp_dir/WORKSPACE.md"

mkdir -p "$output_root/config" "$output_root/overlays"
mv "$tmp_dir/config/repository-index.json" "$output_root/config/repository-index.json"
mv "$tmp_dir/config/workspace.json" "$output_root/config/workspace.json"
mv "$tmp_dir/overlays/repository-index.md" "$output_root/overlays/repository-index.md"
mv "$tmp_dir/WORKSPACE.md" "$output_root/WORKSPACE.md"
