#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-GH"; mkdir -p "$feature_dir/state/github" "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{"app":{"path":"../app","role":"implementation"},"validation":{"path":"../validation","role":"validation"}}}
JSON
cat > "$tmp_dir/config/policy.json" <<'JSON'
{
 "schema_version":"1","policy_version":"1","protected_path_regex":[],"impact_rules":[],
 "gates":[
  {"id":"checks","decisions":["merge-ready"],"when":{"impacts_any":["implementation"]},"evidence_types":["source-control-checks"],"providers":["github-checks"],"coverage":{"claims":"none","architecture":"none"},"required_result":"passed"},
  {"id":"approval","decisions":["merge-ready"],"when":{"impacts_any":["implementation"]},"evidence_types":["intent-approval"],"providers":["github-authority"],"coverage":{"claims":"none","architecture":"none"},"required_result":"passed"}],
 "providers":{
  "github-checks":{"kind":"source-control","trust":"source-control-check","producer_role":"verification","repository_ids":["app","validation"]},
  "github-authority":{"kind":"source-control","trust":"human-authority","producer_role":"authority","repository_ids":["app","validation"]}},
 "decisions":{"merge-ready":{"require_gates":["checks","approval"]}},"release_archive":{"kind":"filesystem","destination":"archive"},"budgets":{"provider_retries":0,"repair_attempts":0}
}
JSON
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-GH","repositories":[{"id":"app","role":"implementation","subject":"commit:aaa","changed_paths":[]},{"id":"validation","role":"validation","subject":"commit:bbb","changed_paths":[]}],"explicit_impacts":["implementation"],"derived_impacts":[],"policy_version":"1"}
JSON
for spec in 'app aaa reviewer-app https://ci.example/app' 'validation bbb reviewer-validation https://ci.example/validation'; do
  set -- $spec; id="$1"; oid="$2"; reviewer="$3"; url="$4"
  jq -n --arg id "$id" --arg oid "$oid" --arg reviewer "$reviewer" --arg url "$url" '{repository_id:$id,pull_request:{approved:true,merged:false,head_oid:$oid,url:("https://github.example/"+$id+"/pull/1"),reviewers:[$reviewer]},checks:{required:{status:"green",url:$url}},preview:{status:"ready",url:"https://preview.example"}}' > "$feature_dir/state/github/$id.json"
done
bash "$repo_root/scripts/orchestration/collect-github-evidence.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --checks-provider github-checks --authority-provider github-authority --run-id gh-run --now 2026-08-13T01:00:00Z
assert_file_exists "$feature_dir/evidence/EV-github-checks-app-gh-run.json"; assert_file_exists "$feature_dir/evidence/EV-github-checks-validation-gh-run.json"
assert_file_exists "$feature_dir/evidence/EV-github-authority-app-gh-run.json"; assert_file_exists "$feature_dir/evidence/EV-github-authority-validation-gh-run.json"
jq -e '.subject.repositories=={"app":"commit:aaa"} and .result=="passed" and .artifacts[0].reference=="https://ci.example/app"' "$feature_dir/evidence/EV-github-checks-app-gh-run.json" >/dev/null
jq -e '.producer.id=="reviewer-app" and .producer.role=="authority" and .result=="passed"' "$feature_dir/evidence/EV-github-authority-app-gh-run.json" >/dev/null
