#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

feature_dir="$tmp_dir/features/FEAT-0001"
mkdir -p "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config"

cp "$repo_root/tests/fixtures/quality/evidence-payload-passed.json" \
  "$tmp_dir/evidence.json"
cp "$repo_root/tests/fixtures/quality/waiver-valid.json" "$tmp_dir/waiver.json"

cat > "$tmp_dir/config/workspace.json" <<'JSON'
{
  "quality": {"mode": "observe", "policy": "policy.json"},
  "repositories": {
    "intent": {"path": "../intent", "role": "requirements"},
    "implementation": {"path": "../implementation", "role": "implementation"}
  }
}
JSON

cat > "$tmp_dir/config/policy.json" <<'JSON'
{
  "schema_version": "1",
  "policy_version": "1",
  "protected_path_regex": [],
  "impact_rules": [],
  "gates": [
    {
      "id": "focused-tests",
      "decisions": ["merge-ready"],
      "when": {"impacts_any": ["implementation"]},
      "evidence_types": ["focused-tests"],
      "providers": ["repository-tests"],
      "coverage": {"claims": "all", "architecture": "none"},
      "required_result": "passed"
    },
    {
      "id": "intent-approval",
      "decisions": ["merge-ready"],
      "when": {"impacts_any": ["implementation"]},
      "evidence_types": ["intent-approval", "waiver-approval"],
      "providers": ["human-authority"],
      "coverage": {"claims": "all", "architecture": "none"},
      "required_result": "passed"
    }
  ],
  "providers": {
    "repository-tests": {
      "kind": "external-import",
      "trust": "repository-check",
      "producer_role": "verification",
      "repository_role": "implementation"
    },
    "human-authority": {
      "kind": "external-import",
      "trust": "human-authority",
      "producer_role": "authority",
      "repository_role": "requirements"
    }
  },
  "decisions": {"merge-ready": {"require_gates": ["focused-tests", "intent-approval"]}},
  "release_archive": {"kind": "filesystem", "destination": "archive"},
  "budgets": {"provider_retries": 1, "repair_attempts": 3}
}
JSON

ingest_evidence() {
  bash "$repo_root/scripts/orchestration/ingest-evidence.sh" \
    --feature-dir "$feature_dir" \
    --config "$tmp_dir/config/workspace.json" \
    --provider "$1" \
    --producer-id "$2" \
    --run-id "$3" \
    --input "$4"
}

ingest_evidence repository-tests ci run-1 "$tmp_dir/evidence.json"
stored_evidence="$feature_dir/evidence/EV-run-1.json"
assert_file_exists "$stored_evidence"
jq -e '
  .feature_id == "FEAT-0001" and
  .provider_id == "repository-tests" and
  .producer == {id:"ci", role:"verification", run_id:"run-1"} and
  .policy_version == "1" and
  (.provider_config_digest | startswith("git-blob:"))
' "$stored_evidence" >/dev/null

jq '.result = "failed" | .outcome = "must-not-overwrite"' \
  "$tmp_dir/evidence.json" > "$tmp_dir/duplicate.json"
assert_command_fails ingest_evidence \
  repository-tests ci run-2 "$tmp_dir/duplicate.json"
jq -e '.result == "passed" and .outcome == "completed"' \
  "$stored_evidence" >/dev/null

jq '.evidence_id = "EV-malformed" | del(.coverage.claim_ids)' \
  "$tmp_dir/evidence.json" > "$tmp_dir/malformed.json"
assert_command_fails ingest_evidence \
  repository-tests ci run-2 "$tmp_dir/malformed.json"

jq '.evidence_id = "EV-mismatch" | .evidence_type = "build"' \
  "$tmp_dir/evidence.json" > "$tmp_dir/mismatch.json"
assert_command_fails ingest_evidence \
  repository-tests ci run-2 "$tmp_dir/mismatch.json"

jq '.evidence_id = "bad/id"' "$tmp_dir/evidence.json" > "$tmp_dir/bad-id.json"
assert_command_fails ingest_evidence \
  repository-tests ci run-2 "$tmp_dir/bad-id.json"

jq '.evidence_id = "EV-absolute" | .artifacts = [{reference:"/tmp/result.log",digest:null,media_type:null}]' \
  "$tmp_dir/evidence.json" > "$tmp_dir/absolute-artifact.json"
assert_command_fails ingest_evidence \
  repository-tests ci run-2 "$tmp_dir/absolute-artifact.json"

jq '
  .evidence_id = "EV-authority-1" |
  .evidence_type = "waiver-approval"
' "$tmp_dir/evidence.json" > "$tmp_dir/authority.json"
assert_command_fails ingest_evidence \
  human-authority human-reviewer authority-run "$tmp_dir/authority.json"
QUALITY_AUTHORITY_COLLECTION=1 ingest_evidence \
  human-authority human-reviewer authority-run "$tmp_dir/authority.json"

jq '.authority_evidence_id = "EV-missing" | .waiver_id = "WV-missing"' \
  "$tmp_dir/waiver.json" > "$tmp_dir/waiver-missing-authority.json"
assert_command_fails bash "$repo_root/scripts/orchestration/ingest-waiver.sh" \
  --feature-dir "$feature_dir" \
  --config "$tmp_dir/config/workspace.json" \
  --input "$tmp_dir/waiver-missing-authority.json"

bash "$repo_root/scripts/orchestration/ingest-waiver.sh" \
  --feature-dir "$feature_dir" \
  --config "$tmp_dir/config/workspace.json" \
  --input "$tmp_dir/waiver.json"
assert_file_exists "$feature_dir/waivers/WV-1.json"
bash "$repo_root/scripts/orchestration/validate-quality-record.sh" \
  --kind evidence --feature-id FEAT-0001 --input "$stored_evidence"
bash "$repo_root/scripts/orchestration/validate-quality-record.sh" \
  --kind waiver --feature-id FEAT-0001 \
  --input "$feature_dir/waivers/WV-1.json"
assert_command_fails bash "$repo_root/scripts/orchestration/ingest-waiver.sh" \
  --feature-dir "$feature_dir" \
  --config "$tmp_dir/config/workspace.json" \
  --input "$tmp_dir/waiver.json"
