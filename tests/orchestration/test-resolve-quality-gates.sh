#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/tests/helpers/assert.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/config" "$tmp_dir/features/FEAT-0001/state"

cat > "$tmp_dir/config/workspace.json" <<'JSON'
{
  "quality": {"mode":"observe", "policy":"policy.json"},
  "repositories": {
    "app": {"path":"../app", "role":"implementation"},
    "docs": {"path":"../docs", "role":"documentation"}
  }
}
JSON

cat > "$tmp_dir/config/policy.json" <<'JSON'
{
  "schema_version":"1",
  "policy_version":"1",
  "protected_path_regex":[],
  "impact_rules":[
    {"id":"implementation-role","when":{"repository_ids_any":[],"repository_roles_any":["implementation"],"path_regex_any":[]},"add_impacts":["implementation"]},
    {"id":"ui-path","when":{"repository_ids_any":["app"],"repository_roles_any":["implementation"],"path_regex_any":["^src/ui/"]},"add_impacts":["ui","architecture-sensitive"]},
    {"id":"docs-path","when":{"repository_ids_any":[],"repository_roles_any":[],"path_regex_any":["(^|/)docs?/|\\.md$"]},"add_impacts":["documentation"]}
  ],
  "gates":[
    {"id":"tests","decisions":["merge-ready"],"when":{"impacts_any":["implementation"]},"evidence_types":["focused-tests"],"providers":["tests"],"coverage":{"claims":"all","architecture":"none"},"required_result":"passed"},
    {"id":"visual","decisions":["merge-ready"],"when":{"impacts_any":["ui"]},"evidence_types":["visual-review"],"providers":["visual"],"coverage":{"claims":"all","architecture":"all_blocking"},"required_result":"passed"},
    {"id":"docs","decisions":["merge-ready"],"when":{"impacts_any":["documentation"]},"evidence_types":["documentation-disposition"],"providers":["docs"],"coverage":{"claims":"none","architecture":"none"},"required_result":"passed"}
  ],
  "providers":{
    "tests":{"kind":"external-import","trust":"repository-check","producer_role":"verification","repository_role":"implementation"},
    "visual":{"kind":"external-import","trust":"external-review","producer_role":"verification","repository_role":"implementation"},
    "docs":{"kind":"external-import","trust":"repository-check","producer_role":"verification","repository_role":"documentation"}
  },
  "decisions":{"merge-ready":{"require_gates":["tests","visual","docs"]}},
  "release_archive":{"kind":"filesystem","destination":"archive"},
  "budgets":{"provider_retries":1,"repair_attempts":3}
}
JSON

cat > "$tmp_dir/features/FEAT-0001/scope.json" <<'JSON'
{
  "schema_version":"1",
  "feature_id":"FEAT-0001",
  "repositories":[
    {"id":"app","role":"implementation","subject":"commit:abc","base":"base","head":"abc","changed_paths":["README.md","src/ui/button.ts"],"dependencies":[],"captured_at":"2026-08-13T00:00:00Z"}
  ],
  "explicit_impacts":["escaped-defect"],
  "derived_impacts":[],
  "policy_version":null
}
JSON

bash "$repo_root/scripts/orchestration/resolve-quality-gates.sh" \
  --feature-dir "$tmp_dir/features/FEAT-0001" \
  --config "$tmp_dir/config/workspace.json" \
  --now "2026-08-13T01:00:00Z"

plan="$tmp_dir/features/FEAT-0001/state/gate-plan.json"
assert_file_exists "$plan"
jq -e '
  .impacts.explicit == ["escaped-defect"] and
  .impacts.derived == ["architecture-sensitive","documentation","implementation","ui"] and
  .impacts.all == ["architecture-sensitive","documentation","escaped-defect","implementation","ui"] and
  (.gates | map(.id)) == ["docs","tests","visual"] and
  all(.gates[]; .applicability == "required") and
  all(.gates[]; .provider_strategy == "all") and
  (.impact_sources | map(.rule_id)) == ["docs-path","implementation-role","ui-path"] and
  (.subject_fingerprint | startswith("git-blob:"))
' "$plan" >/dev/null
jq -e '
  .derived_impacts == ["architecture-sensitive","documentation","implementation","ui"] and
  .explicit_impacts == ["escaped-defect"] and
  .policy_version == "1"
' "$tmp_dir/features/FEAT-0001/scope.json" >/dev/null

jq '.repositories[0].changed_paths = ["README.md"] | .explicit_impacts = []' \
  "$tmp_dir/features/FEAT-0001/scope.json" > "$tmp_dir/docs-scope.json"
mv "$tmp_dir/docs-scope.json" "$tmp_dir/features/FEAT-0001/scope.json"
bash "$repo_root/scripts/orchestration/resolve-quality-gates.sh" \
  --feature-dir "$tmp_dir/features/FEAT-0001" \
  --config "$tmp_dir/config/workspace.json" \
  --now "2026-08-13T01:00:00Z"
jq -e '
  (.gates[] | select(.id == "docs").applicability) == "required" and
  (.gates[] | select(.id == "visual").applicability) == "not_applicable"
' "$plan" >/dev/null

jq 'del(.providers.visual)' "$tmp_dir/config/policy.json" > "$tmp_dir/config/invalid-policy.json"
jq '.quality.policy = "invalid-policy.json"' "$tmp_dir/config/workspace.json" > "$tmp_dir/config/invalid-workspace.json"
assert_command_fails bash "$repo_root/scripts/orchestration/resolve-quality-gates.sh" \
  --feature-dir "$tmp_dir/features/FEAT-0001" \
  --config "$tmp_dir/config/invalid-workspace.json" \
  --now "2026-08-13T01:00:00Z"
