#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$repo_root/tests/helpers/assert.sh"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
feature_dir="$tmp_dir/features/FEAT-GH"; mkdir -p "$feature_dir/state/github" "$feature_dir/evidence" "$feature_dir/waivers" "$tmp_dir/config"
cat > "$tmp_dir/config/workspace.json" <<'JSON'
{"quality":{"mode":"observe","policy":"policy.json"},"repositories":{"app":{"path":"../app","role":"implementation"},"validation":{"path":"../validation","role":"validation"},"empty":{"path":"../empty","role":"validation"}}}
JSON
cat > "$tmp_dir/config/policy.json" <<'JSON'
{
 "schema_version":"1","policy_version":"1","protected_path_regex":[],"impact_rules":[],
 "gates":[
  {"id":"checks","decisions":["merge-ready"],"when":{"impacts_any":["implementation"]},"evidence_types":["source-control-checks"],"providers":["github-checks"],"coverage":{"claims":"none","architecture":"none"},"required_result":"passed"},
  {"id":"approval","decisions":["merge-ready"],"when":{"impacts_any":["implementation"]},"evidence_types":["intent-approval"],"providers":["github-authority"],"coverage":{"claims":"none","architecture":"none"},"required_result":"passed"}],
 "providers":{
  "github-checks":{"kind":"source-control","trust":"source-control-check","producer_role":"verification","repository_ids":["app","validation","empty"]},
  "github-authority":{"kind":"source-control","trust":"human-authority","producer_role":"authority","repository_ids":["app","validation","empty"]}},
 "decisions":{"merge-ready":{"require_gates":["checks","approval"]}},"release_archive":{"kind":"filesystem","destination":"archive"},"budgets":{"provider_retries":0,"repair_attempts":0}
}
JSON
cat > "$feature_dir/scope.json" <<'JSON'
{"schema_version":"1","feature_id":"FEAT-GH","repositories":[{"id":"app","role":"implementation","subject":"commit:aaa","changed_paths":[]},{"id":"validation","role":"validation","subject":"commit:bbb","changed_paths":[]},{"id":"empty","role":"validation","subject":"commit:ccc","changed_paths":[]}],"explicit_impacts":["implementation"],"derived_impacts":[],"policy_version":"1"}
JSON
for spec in 'app aaa reviewer-app https://ci.example/app' 'validation bbb reviewer-validation https://ci.example/validation'; do
  set -- $spec; id="$1"; oid="$2"; reviewer="$3"; url="$4"
  jq -n --arg id "$id" --arg oid "$oid" --arg reviewer "$reviewer" --arg url "$url" '{repository_id:$id,pull_request:{approved:true,merged:false,head_oid:$oid,url:("https://github.example/"+$id+"/pull/1"),reviewers:[$reviewer]},checks:{required:{status:"green",url:$url}},preview:{status:"ready",url:"https://preview.example"}}' > "$feature_dir/state/github/$id.json"
done
jq -n '{repository_id:"empty",pull_request:{approved:false,merged:false,head_oid:"ccc",url:"https://github.example/empty/pull/1",reviewers:[]},checks:{},preview:{status:"ready",url:"https://preview.example"}}' > "$feature_dir/state/github/empty.json"

for run_id in gh-run-1 gh-run-2; do
  bash "$repo_root/scripts/orchestration/collect-github-evidence.sh" --feature-dir "$feature_dir" --config "$tmp_dir/config/workspace.json" --checks-provider github-checks --authority-provider github-authority --run-id "$run_id" --now 2026-08-13T01:00:00Z
  assert_file_exists "$feature_dir/evidence/EV-github-checks-app-$run_id.json"
  assert_file_exists "$feature_dir/evidence/EV-github-checks-validation-$run_id.json"
  assert_file_exists "$feature_dir/evidence/EV-github-checks-empty-$run_id.json"
  assert_file_exists "$feature_dir/evidence/EV-github-authority-app-$run_id.json"
  assert_file_exists "$feature_dir/evidence/EV-github-authority-validation-$run_id.json"
  assert_file_exists "$feature_dir/state/provider-runs/$run_id/source-control/app/EV-github-checks-app-$run_id.payload.json"
done

jq -e '.subject.repositories=={"app":"commit:aaa"} and .coverage.repository_ids==["app"] and .result=="passed" and .artifacts[0].reference=="https://ci.example/app"' "$feature_dir/evidence/EV-github-checks-app-gh-run-1.json" >/dev/null
jq -e '.producer.id=="reviewer-app" and .producer.role=="authority" and .result=="passed" and .coverage.claim_ids==[] and .coverage.repository_ids==["app"] and .subject.repositories=={"app":"commit:aaa"}' "$feature_dir/evidence/EV-github-authority-app-gh-run-1.json" >/dev/null
jq -e '.result=="blocked" and .coverage.repository_ids==["empty"] and .known_gaps==[{"id":"SOURCE_CONTROL_CHECKS_EMPTY","message":"No source-control checks were collected"}]' "$feature_dir/evidence/EV-github-checks-empty-gh-run-1.json" >/dev/null
