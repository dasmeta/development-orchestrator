#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

feature_dir="$tmp_dir/features/FEAT-0001"
downstream_repo="$tmp_dir/downstream/intent"
fake_bin="$tmp_dir/bin"
args_file="$tmp_dir/codex-args.txt"
stdin_file="$tmp_dir/codex-stdin.txt"
config_file="$tmp_dir/workspace.json"

mkdir -p "$feature_dir/state" "$downstream_repo" "$fake_bin"

cat <<'EOF' > "$feature_dir/intake.md"
# Feature Intake: FEAT-0001

## Title
Branch previews for product delivery

## Requested Outcome
- Ensure per-branch preview environments and final validation gating.
EOF

cat <<EOF > "$config_file"
{
  "repositories": {
    "intent": {
      "path": "$downstream_repo",
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
EOF

cat <<'EOF' > "$fake_bin/codex"
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CODEX_ARGS_FILE"
cat > "$CODEX_STDIN_FILE"
EOF
chmod +x "$fake_bin/codex"

PATH="$fake_bin:$PATH" \
CODEX_BIN="codex" \
CODEX_ARGS_FILE="$args_file" \
CODEX_STDIN_FILE="$stdin_file" \
  bash "$repo_root/scripts/orchestration/run-speckit-stage.sh" \
    --feature-dir "$feature_dir" \
    --stage definition \
    --config "$config_file"

log_path="$feature_dir/state/run-log.json"
assert_file_exists "$log_path"
assert_file_exists "$args_file"
assert_file_exists "$stdin_file"
assert_contains "$args_file" "exec"
assert_contains "$args_file" "--full-auto"
assert_contains "$args_file" "$downstream_repo"
assert_contains "$stdin_file" "speckit-specify"
assert_contains "$stdin_file" "FEAT-0001"
assert_contains "$stdin_file" "Branch previews for product delivery"
