#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/orchestration/lib/workspace_config.sh"
source "$repo_root/scripts/orchestration/lib/quality_config.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_command_fails() {
  if "$@" >"$tmp_dir/command.stdout" 2>"$tmp_dir/command.stderr"; then
    echo "expected command to fail: $*" >&2
    exit 1
  fi
}

mkdir -p "$tmp_dir/config" "$tmp_dir/overlays/quality"

legacy_config="$tmp_dir/config/legacy.json"
cat >"$legacy_config" <<'JSON'
{
  "repositories": {},
  "stages": []
}
JSON

valid_config="$tmp_dir/config/workspace.json"
cat >"$valid_config" <<'JSON'
{
  "quality": {
    "mode": "observe",
    "policy": "../overlays/quality/policy.json"
  }
}
JSON

valid_policy="$tmp_dir/overlays/quality/policy.json"
cat >"$valid_policy" <<'JSON'
{
  "schema_version": "1",
  "policy_version": "1",
  "protected_path_regex": ["(^|/)evidence/", "(^|/)waivers/"],
  "impact_rules": [
    {
      "id": "implementation-change",
      "when": {
        "repository_ids_any": [],
        "repository_roles_any": ["implementation"],
        "path_regex_any": ["(^|/)src/"]
      },
      "add_impacts": ["implementation"]
    }
  ],
  "gates": [
    {
      "id": "focused-tests",
      "decisions": ["stage-ready", "merge-ready"],
      "when": {"impacts_any": ["implementation"]},
      "evidence_types": ["focused-tests"],
      "providers": ["repository-tests"],
      "coverage": {"claims": "all", "architecture": "none"},
      "required_result": "passed"
    }
  ],
  "providers": {
    "repository-tests": {
      "kind": "command",
      "trust": "repository-check",
      "producer_role": "verification",
      "repository_role": "implementation",
      "repository_ids": [],
      "working_directory": ".",
      "command": ["scripts/quality/focused-tests.sh"],
      "output_mode": "exit-code"
    }
  },
  "decisions": {
    "stage-ready": {"require_gates": ["focused-tests"]},
    "merge-ready": {"require_gates": ["focused-tests"]},
    "release-ready": {"require_gates": []}
  },
  "release_archive": {
    "kind": "filesystem",
    "destination": "workspace/quality-archive"
  },
  "budgets": {"provider_retries": 1, "repair_attempts": 3}
}
JSON

assert_equals "off" "$(workspace_quality_mode "$legacy_config")"
assert_command_fails workspace_quality_policy_path "$legacy_config"
assert_equals "observe" "$(workspace_quality_mode "$valid_config")"
assert_equals "$tmp_dir/config/../overlays/quality/policy.json" \
  "$(workspace_quality_policy_path "$valid_config")"
assert_equals "$tmp_dir/config/workspace/quality-archive" \
  "$(workspace_quality_release_archive_path "$valid_config")"
validate_quality_policy "$valid_policy"

absolute_config="$tmp_dir/config/absolute.json"
jq --arg policy "$valid_policy" '.quality.policy = $policy' \
  "$valid_config" >"$absolute_config"
assert_equals "$valid_policy" "$(workspace_quality_policy_path "$absolute_config")"

duplicate_impact_policy="$tmp_dir/duplicate-impact.json"
jq '.impact_rules += [.impact_rules[0]]' \
  "$valid_policy" >"$duplicate_impact_policy"
assert_command_fails validate_quality_policy "$duplicate_impact_policy"
grep -Fq "duplicate impact rule id" "$tmp_dir/command.stderr"

duplicate_gate_policy="$tmp_dir/duplicate-gate.json"
jq '.gates += [.gates[0]]' "$valid_policy" >"$duplicate_gate_policy"
assert_command_fails validate_quality_policy "$duplicate_gate_policy"
grep -Fq "duplicate gate id" "$tmp_dir/command.stderr"

newline_command_policy="$tmp_dir/newline-command.json"
jq '.providers["repository-tests"].command = ["npm", "test\n--watch"]' \
  "$valid_policy" >"$newline_command_policy"
assert_command_fails validate_quality_policy "$newline_command_policy"
grep -Fq "command arguments must not contain CR or LF" "$tmp_dir/command.stderr"

unknown_provider_policy="$tmp_dir/unknown-provider.json"
jq '.gates[0].providers = ["missing-provider"]' \
  "$valid_policy" >"$unknown_provider_policy"
assert_command_fails validate_quality_policy "$unknown_provider_policy"
grep -Fq "unknown provider" "$tmp_dir/command.stderr"

unknown_gate_decision_policy="$tmp_dir/unknown-gate-decision.json"
jq '.gates[0].decisions = ["missing-decision"]' \
  "$valid_policy" >"$unknown_gate_decision_policy"
assert_command_fails validate_quality_policy "$unknown_gate_decision_policy"
grep -Fq "unknown decision" "$tmp_dir/command.stderr"

unknown_decision_gate_policy="$tmp_dir/unknown-decision-gate.json"
jq '.decisions["stage-ready"].require_gates = ["missing-gate"]' \
  "$valid_policy" >"$unknown_decision_gate_policy"
assert_command_fails validate_quality_policy "$unknown_decision_gate_policy"
grep -Fq "unknown gate" "$tmp_dir/command.stderr"

invalid_structure_policy="$tmp_dir/invalid-structure.json"
jq '.budgets.provider_retries = -1' \
  "$valid_policy" >"$invalid_structure_policy"
assert_command_fails validate_quality_policy "$invalid_structure_policy"
grep -Fq "invalid quality policy structure" "$tmp_dir/command.stderr"

untargeted_provider_policy="$tmp_dir/untargeted-provider.json"
jq 'del(.providers["repository-tests"].repository_role)' \
  "$valid_policy" >"$untargeted_provider_policy"
assert_command_fails validate_quality_policy "$untargeted_provider_policy"
grep -Fq "invalid quality policy structure" "$tmp_dir/command.stderr"
