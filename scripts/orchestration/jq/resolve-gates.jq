def matches_role($scope; $roles):
  ($roles | length == 0) or
  any($scope.repositories[]?; .role as $role | $roles | index($role));

def matches_repo($scope; $ids):
  ($ids | length == 0) or
  any($scope.repositories[]?; .id as $id | $ids | index($id));

def matches_path($scope; $patterns):
  ($patterns | length == 0) or
  any($scope.repositories[].changed_paths[]?; . as $path |
    any($patterns[]; . as $pattern | $path | test($pattern)));

def rule_matches($scope; $rule):
  matches_repo($scope; ($rule.when.repository_ids_any // [])) and
  matches_role($scope; ($rule.when.repository_roles_any // [])) and
  matches_path($scope; ($rule.when.path_regex_any // []));

($scope[0]) as $scope_record |
($policy[0]) as $policy_record |
[
  $policy_record.impact_rules[]
  | select(rule_matches($scope_record; .))
] as $matching_rules |
([$matching_rules[].add_impacts[]] | unique | sort) as $derived_impacts |
([$scope_record.explicit_impacts[], $derived_impacts[]] | unique | sort) as $all_impacts |
{
  schema_version: "1",
  feature_id: $scope_record.feature_id,
  policy_version: $policy_record.policy_version,
  subject_fingerprint: $subject_fingerprint,
  resolved_at: $resolved_at,
  impacts: {
    explicit: ($scope_record.explicit_impacts | unique | sort),
    derived: $derived_impacts,
    all: $all_impacts
  },
  impact_sources: (
    [$matching_rules[] | {rule_id: .id, impacts: (.add_impacts | unique | sort)}]
    | sort_by(.rule_id)
  ),
  gates: (
    [$policy_record.gates[]
      | . as $gate
      | (($gate.when.impacts_any | length == 0) or
         any($gate.when.impacts_any[]; . as $impact | $all_impacts | index($impact))) as $required
      | {
          id: $gate.id,
          applicability: (if $required then "required" else "not_applicable" end),
          reason: (if $required then "configured_impact_match" else "no_configured_impact_match" end),
          decisions: ($gate.decisions | unique | sort),
          evidence_types: ($gate.evidence_types | unique | sort),
          providers: ($gate.providers | unique | sort),
          provider_strategy: ($gate.provider_strategy // "all"),
          coverage: $gate.coverage,
          required_result: $gate.required_result
        }
    ] | sort_by(.id)
  ),
  findings: []
}
