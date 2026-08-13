#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/features/FEAT-0001/state"
cat <<'EOF' > "$tmp_dir/features/FEAT-0001/intake.md"
# Feature Intake: FEAT-0001

## Title
Branch previews for product delivery
EOF
mkdir -p "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{
  "repositories": {
    "intent": {
      "path": "../intent",
      "role": "requirements"
    }
  },
  "stages": [
    {
      "id": "definition",
      "repository": "intent",
      "skill": "speckit-specify"
    }
  ]
}
JSON

bash "$repo_root/scripts/orchestration/run-speckit-stage.sh" \
  --feature-dir "$tmp_dir/features/FEAT-0001" \
  --stage definition \
  --run-id dry-run-1 \
  --sandbox read-only \
  --dry-run \
  --config "$tmp_dir/config/workspace.json"

log_path="$tmp_dir/features/FEAT-0001/state/run-log.json"
assert_file_exists "$log_path"
jq -e '.repo == "intent"' "$log_path" >/dev/null
jq -e '.stage == "definition"' "$log_path" >/dev/null
jq -e '.dry_run == true' "$log_path" >/dev/null
assert_file_exists "$tmp_dir/features/FEAT-0001/state/runs/dry-run-1.json"
jq -e '.run_id=="dry-run-1" and .sandbox=="read-only" and .exit_status==0 and .finding_ids==[]' "$log_path" >/dev/null

cat > "$tmp_dir/features/FEAT-0001/state/repair-brief.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-0001","decision":"stage-ready","subject_fingerprint":"x","human_action_required":false,"repairs":[{"finding_id":"FAIL-1","gate_id":"tests","owner":"validation","affected_claim_ids":[],"affected_architecture_constraint_ids":[],"allowed_responsibility":"implementation","message":"wrong owner"}]}
JSON
assert_command_fails bash "$repo_root/scripts/orchestration/run-speckit-stage.sh" \
  --feature-dir "$tmp_dir/features/FEAT-0001" --stage definition --run-id repair-1 \
  --repair-brief "$tmp_dir/features/FEAT-0001/state/repair-brief.json" --dry-run \
  --config "$tmp_dir/config/workspace.json"
