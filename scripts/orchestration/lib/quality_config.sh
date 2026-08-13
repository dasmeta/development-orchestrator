#!/usr/bin/env bash

set -euo pipefail

workspace_quality_mode() {
  local config_path="$1"
  jq -r '.quality.mode // "off"' "$config_path"
}

resolve_config_relative_path() {
  local config_path="$1"
  local configured_path="$2"
  local config_dir

  config_dir="$(cd "$(dirname "$config_path")" && pwd)"
  if [[ "$configured_path" = /* ]]; then
    printf '%s\n' "$configured_path"
  else
    printf '%s\n' "$config_dir/$configured_path"
  fi
}

workspace_quality_policy_path() {
  local config_path="$1"
  local policy

  policy="$(jq -r '.quality.policy // empty' "$config_path")"
  if [[ -z "$policy" ]]; then
    return 1
  fi

  resolve_config_relative_path "$config_path" "$policy"
}

workspace_quality_release_archive_path() {
  local config_path="$1"
  local policy_path
  local destination

  policy_path="$(workspace_quality_policy_path "$config_path")" || return 1
  destination="$(jq -r '.release_archive.destination // empty' "$policy_path")"
  if [[ -z "$destination" ]]; then
    return 1
  fi

  resolve_config_relative_path "$config_path" "$destination"
}

_quality_policy_error() {
  printf 'invalid quality policy: %s\n' "$1" >&2
  return 1
}

_quality_policy_structure_is_valid() {
  local policy_path="$1"

  jq -e '
    def nonempty_string: type == "string" and length > 0;
    def string_array: type == "array" and all(.[]; nonempty_string);
    def only_keys($allowed): ([keys[]] - $allowed | length) == 0;

    type == "object" and
    only_keys([
      "schema_version", "policy_version", "protected_path_regex",
      "impact_rules", "gates", "providers", "decisions",
      "release_archive", "budgets"
    ]) and
    .schema_version == "1" and
    .policy_version == "1" and
    (.protected_path_regex | string_array) and
    (.impact_rules | type == "array") and
    all(.impact_rules[];
      type == "object" and
      only_keys(["id", "when", "add_impacts"]) and
      (.id | nonempty_string) and
      (.when | type == "object") and
      (.when | only_keys([
        "repository_ids_any", "repository_roles_any", "path_regex_any"
      ])) and
      (.when.repository_ids_any | string_array) and
      (.when.repository_roles_any | string_array) and
      (.when.path_regex_any | string_array) and
      (.add_impacts | string_array)
    ) and
    (.gates | type == "array") and
    all(.gates[];
      type == "object" and
      only_keys([
        "id", "decisions", "when", "evidence_types", "providers",
        "coverage", "required_result"
      ]) and
      (.id | nonempty_string) and
      (.decisions | string_array) and
      (.when | type == "object" and only_keys(["impacts_any"])) and
      (.when.impacts_any | string_array) and
      (.evidence_types | string_array) and
      (.providers | string_array) and
      (.coverage | type == "object" and only_keys(["claims", "architecture"])) and
      (.coverage.claims == "none" or .coverage.claims == "all") and
      (
        .coverage.architecture == "none" or
        .coverage.architecture == "all" or
        .coverage.architecture == "all_blocking"
      ) and
      (.required_result | nonempty_string)
    ) and
    (.providers | type == "object") and
    all(.providers | to_entries[];
      (.key | nonempty_string) and
      (.value | type == "object") and
      (.value | only_keys([
        "kind", "trust", "producer_role", "repository_role",
        "repository_ids", "working_directory", "command", "output_mode"
      ])) and
      (
        .value.kind == "command" or
        .value.kind == "external-import" or
        .value.kind == "source-control" or
        .value.kind == "verifier"
      ) and
      (.value.trust | nonempty_string) and
      (.value.producer_role | nonempty_string) and
      (
        (.value.repository_role? | nonempty_string) or
        (.value.repository_ids? | string_array and length > 0)
      ) and
      (
        (.value | has("repository_ids") | not) or
        (.value.repository_ids | string_array)
      ) and
      (
        (.value | has("repository_role") | not) or
        (.value.repository_role | nonempty_string)
      ) and
      if (.value.kind == "command" or .value.kind == "verifier") then
        (.value.working_directory | type == "string") and
        (.value.command | type == "array" and length > 0) and
        all(.value.command[]; type == "string") and
        (.value.output_mode | nonempty_string)
      else
        ((.value | has("working_directory") | not) or
          (.value.working_directory | type == "string")) and
        ((.value | has("command") | not) or
          ((.value.command | type == "array" and length > 0) and
            all(.value.command[]; type == "string"))) and
        ((.value | has("output_mode") | not) or
          (.value.output_mode | nonempty_string))
      end
    ) and
    (.decisions | type == "object") and
    all(.decisions | to_entries[];
      (.key | nonempty_string) and
      (.value | type == "object" and only_keys(["require_gates"])) and
      (.value.require_gates | string_array)
    ) and
    (.release_archive | type == "object" and only_keys(["kind", "destination"])) and
    (
      .release_archive.kind == "filesystem" or
      .release_archive.kind == "command"
    ) and
    (.release_archive.destination | nonempty_string) and
    (.budgets | type == "object" and only_keys(["provider_retries", "repair_attempts"])) and
    (.budgets.provider_retries | type == "number" and floor == . and . >= 0) and
    (.budgets.repair_attempts | type == "number" and floor == . and . >= 0)
  ' "$policy_path" >/dev/null 2>&1
}

validate_quality_policy() {
  local policy_path="$1"
  local duplicate_id
  local invalid_reference

  if [[ ! -f "$policy_path" ]]; then
    _quality_policy_error "file not found: $policy_path"
    return 1
  fi

  if ! jq -e 'type == "object"' "$policy_path" >/dev/null 2>&1; then
    _quality_policy_error "invalid JSON object: $policy_path"
    return 1
  fi

  if ! _quality_policy_structure_is_valid "$policy_path"; then
    _quality_policy_error "invalid quality policy structure"
    return 1
  fi

  duplicate_id="$(jq -r '
    first(
      [.impact_rules[].id]
      | group_by(.)[]
      | select(length > 1)
      | .[0]
    ) // empty
  ' "$policy_path")"
  if [[ -n "$duplicate_id" ]]; then
    _quality_policy_error "duplicate impact rule id: $duplicate_id"
    return 1
  fi

  duplicate_id="$(jq -r '
    first(
      [.gates[].id]
      | group_by(.)[]
      | select(length > 1)
      | .[0]
    ) // empty
  ' "$policy_path")"
  if [[ -n "$duplicate_id" ]]; then
    _quality_policy_error "duplicate gate id: $duplicate_id"
    return 1
  fi

  if jq -e '
    [.providers[] | .command[]? | select(test("[\\r\\n]"))]
    | length > 0
  ' "$policy_path" >/dev/null; then
    _quality_policy_error "command arguments must not contain CR or LF"
    return 1
  fi

  invalid_reference="$(jq -r '
    (.providers | keys) as $provider_ids
    | [.gates[].providers[] | select(. as $id | $provider_ids | index($id) | not)]
    | first // empty
  ' "$policy_path")"
  if [[ -n "$invalid_reference" ]]; then
    _quality_policy_error "gate references unknown provider: $invalid_reference"
    return 1
  fi

  invalid_reference="$(jq -r '
    (.decisions | keys) as $decision_ids
    | [.gates[].decisions[] | select(. as $id | $decision_ids | index($id) | not)]
    | first // empty
  ' "$policy_path")"
  if [[ -n "$invalid_reference" ]]; then
    _quality_policy_error "gate references unknown decision: $invalid_reference"
    return 1
  fi

  invalid_reference="$(jq -r '
    ([.gates[].id]) as $gate_ids
    | [.decisions[].require_gates[] | select(. as $id | $gate_ids | index($id) | not)]
    | first // empty
  ' "$policy_path")"
  if [[ -n "$invalid_reference" ]]; then
    _quality_policy_error "decision references unknown gate: $invalid_reference"
    return 1
  fi
}
