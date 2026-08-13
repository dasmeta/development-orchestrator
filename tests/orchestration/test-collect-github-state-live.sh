#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/features/FEAT-0001/state" "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{
  "github_state": {
    "check_name_patterns": {
      "implementation": [
        "implementation",
        "build"
      ],
      "validation": [
        "validation",
        "e2e"
      ],
      "preview": [
        "preview",
        "deploy"
      ]
    }
  }
}
JSON

cat <<'EOF' > "$tmp_dir/bin/gh"
#!/usr/bin/env bash
cat <<'JSON'
{
  "reviewDecision": "APPROVED",
  "mergeStateStatus": "MERGED",
  "headRefName": "feat-0001-branch-previews",
  "headRefOid": "1111111111111111111111111111111111111111",
  "url": "https://github.com/example/implementation/pull/12",
  "latestReviews": [{"author":{"login":"reviewer-one"},"state":"APPROVED"}],
  "statusCheckRollup": [
    {
      "name": "implementation-build",
      "conclusion": "SUCCESS",
      "detailsUrl": "https://ci.example/implementation"
    },
    {
      "name": "preview-deploy",
      "conclusion": "SUCCESS",
      "detailsUrl": "https://preview.example.test/feat-0001"
    },
    {
      "name": "e2e-smoke",
      "conclusion": "SUCCESS",
      "detailsUrl": "https://ci.example/e2e"
    }
  ]
}
JSON
EOF
chmod +x "$tmp_dir/bin/gh"

PATH="$tmp_dir/bin:$PATH" \
  bash "$repo_root/scripts/orchestration/collect-github-state.sh" \
    --feature-dir "$tmp_dir/features/FEAT-0001" \
    --repo "example/implementation" \
    --pr-number "12" \
    --config "$tmp_dir/config/workspace.json"

state_path="$tmp_dir/features/FEAT-0001/state/github-state.json"
assert_file_exists "$state_path"
jq -e '.pull_request.approved == true' "$state_path" >/dev/null
jq -e '.pull_request.merged == true' "$state_path" >/dev/null
jq -e '.checks.implementation == "green"' "$state_path" >/dev/null
jq -e '.checks.validation == "green"' "$state_path" >/dev/null
jq -e '.preview.status == "ready"' "$state_path" >/dev/null
jq -e '.preview.url == "https://preview.example.test/feat-0001"' "$state_path" >/dev/null

PATH="$tmp_dir/bin:$PATH" \
  bash "$repo_root/scripts/orchestration/collect-github-state.sh" \
    --feature-dir "$tmp_dir/features/FEAT-0001" \
    --repo-id "implementation" \
    --repo "example/implementation" \
    --pr-number "12" \
    --config "$tmp_dir/config/workspace.json"
repo_state="$tmp_dir/features/FEAT-0001/state/github/implementation.json"
assert_file_exists "$repo_state"
jq -e '.repository_id=="implementation" and .pull_request.head_oid=="1111111111111111111111111111111111111111" and .pull_request.reviewers==["reviewer-one"] and .checks.implementation.url=="https://ci.example/implementation"' "$repo_state" >/dev/null
