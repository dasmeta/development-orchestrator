def covers_all($required; $actual):
  (($required - $actual) | length) == 0;

def status_rank:
  if . == "failed" then 3
  elif . == "blocked" then 2
  elif . == "incomplete" then 1
  else 0 end;

def ranked_status($results):
  ($results | map(.status | status_rank) | max // 0) as $rank |
  if $rank == 3 then "failed"
  elif $rank == 2 then "blocked"
  elif $rank == 1 then "incomplete"
  else "ready" end;

def finding($id; $class; $owner; $gate_id; $message):
  {id:$id, class:$class, owner:$owner, gate_id:$gate_id, message:$message};

def target_finding_id($kind; $gate_id; $provider_id; $repository_id; $simple):
  if $simple then $kind + ":" + $gate_id
  else $kind + ":" + $gate_id + ":" + $provider_id + ":" + $repository_id end;

def provider_targets($policy; $scope; $provider_id):
  ($policy.providers[$provider_id]) as $provider |
  [$scope.repositories[] as $repository |
    select(
      ((($provider.repository_ids // []) | index($repository.id)) != null) or
      ($provider.repository_role? == $repository.role)
    ) |
    $repository.id
  ] | unique | sort;

def coverage_is_complete($evidence; $gate; $claim_ids; $architecture; $blocking_architecture_ids):
  (if $gate.coverage.claims == "all"
   then covers_all($claim_ids; ($evidence.coverage.claim_ids | unique))
   else true end) and
  (if $gate.coverage.architecture == "all_blocking"
   then covers_all($blocking_architecture_ids; ($evidence.coverage.architecture_constraint_ids | unique))
   elif $gate.coverage.architecture == "all"
   then covers_all(([$architecture.constraints[].id] | unique); ($evidence.coverage.architecture_constraint_ids | unique))
   else true end);

def trust_is_valid($evidence; $gate; $implementation_run_ids):
  if (($gate.coverage.architecture != "none") or
      ($evidence.evidence_type | test("verification|conformance")))
  then
    $evidence.producer.role != "implementation" and
    (($implementation_run_ids | index($evidence.producer.run_id)) == null)
  else true end;

def subjects_are_current($evidence; $subjects):
  $evidence as $record |
  all($record.coverage.repository_ids[];
    . as $repository_id |
    $subjects[$repository_id] != null and
    $record.subject.repositories[$repository_id] == $subjects[$repository_id]
  );

def target_result(
  $policy; $scope; $gate; $provider_id; $repository_id; $target_count;
  $all_evidence; $digests; $subjects; $claim_ids; $architecture;
  $blocking_architecture_ids; $implementation_run_ids; $now
):
  ($gate.providers | length == 1 and $target_count == 1) as $simple |
  ([$all_evidence[]
    | select(.provider_id == $provider_id)
    | select(.evidence_type as $type | $gate.evidence_types | index($type))
  ] | sort_by(.collected_at,.evidence_id) | reverse) as $provider_records |
  ([$provider_records[]
    | select((.coverage.repository_ids | index($repository_id)) != null)
  ]) as $repository_records |
  ([$repository_records[]
    | select(subjects_are_current(.; $subjects))
  ]) as $subject_records |
  ([$subject_records[]
    | select(.feature_id == $scope.feature_id)
    | select(.policy_version == $policy.policy_version)
    | select(.provider_config_digest == $digests[.provider_id])
  ]) as $provenance_records |
  ([$provenance_records[]
    | select((.expires_at == null) or (.expires_at > $now))
  ]) as $fresh_records |
  ([$fresh_records[]
    | select(coverage_is_complete(.; $gate; $claim_ids; $architecture; $blocking_architecture_ids))
  ]) as $coverage_records |
  ([$coverage_records[]
    | select(trust_is_valid(.; $gate; $implementation_run_ids))
  ]) as $trusted_records |
  ($trusted_records[0] // null) as $selected |
  if $selected != null then
    ($selected.findings // []) as $provider_findings |
    {provider_id:$provider_id,repository_id:$repository_id,
     status:(if $selected.result == $gate.required_result then "ready"
             elif $selected.result == "blocked" then "blocked"
             else "failed" end),
     evidence_ids:[$selected.evidence_id],
     findings:($provider_findings +
       if $selected.result == $gate.required_result then []
       elif $selected.result == "blocked" then
         [finding(
           target_finding_id("EVIDENCE_BLOCKED"; $gate.id; $provider_id; $repository_id; $simple);
           "evidence"; "verification"; $gate.id;
           "The selected provider was blocked"
         )]
       else
         [finding(
           target_finding_id("EVIDENCE_FAILED"; $gate.id; $provider_id; $repository_id; $simple);
           "evidence"; "implementation"; $gate.id;
           "Valid evidence reports a failed result"
         )]
       end)}
  elif ($provider_records | length) == 0 then
    {provider_id:$provider_id,repository_id:$repository_id,status:"incomplete",evidence_ids:[],
     findings:[finding(
       target_finding_id("EVIDENCE_MISSING"; $gate.id; $provider_id; $repository_id; $simple);
       "evidence"; "verification"; $gate.id;
       ("No evidence from " + $provider_id + " covers " + $repository_id)
     )]}
  elif ($repository_records | length) == 0 then
    {provider_id:$provider_id,repository_id:$repository_id,status:"incomplete",evidence_ids:[],
     findings:[finding(
       target_finding_id("EVIDENCE_REPOSITORY_COVERAGE_MISSING"; $gate.id; $provider_id; $repository_id; $simple);
       "evidence"; "verification"; $gate.id;
       ("Evidence does not declare coverage for " + $repository_id)
     )]}
  elif ($subject_records | length) == 0 then
    {provider_id:$provider_id,repository_id:$repository_id,status:"incomplete",evidence_ids:[],
     findings:[finding(
       target_finding_id("EVIDENCE_SUBJECT_MISMATCH"; $gate.id; $provider_id; $repository_id; $simple);
       "evidence"; "implementation"; $gate.id;
       ("Evidence does not match the current subject for " + $repository_id)
     )]}
  elif ($provenance_records | length) == 0 then
    {provider_id:$provider_id,repository_id:$repository_id,status:"incomplete",evidence_ids:[],
     findings:[finding(
       target_finding_id("EVIDENCE_PROVENANCE_STALE"; $gate.id; $provider_id; $repository_id; $simple);
       "evidence"; "verification"; $gate.id;
       "Evidence policy or provider configuration is stale"
     )]}
  elif ($fresh_records | length) == 0 then
    {provider_id:$provider_id,repository_id:$repository_id,status:"incomplete",evidence_ids:[],
     findings:[finding(
       target_finding_id("EVIDENCE_EXPIRED"; $gate.id; $provider_id; $repository_id; $simple);
       "evidence"; "verification"; $gate.id;
       "Evidence has expired"
     )]}
  elif ($coverage_records | length) == 0 then
    {provider_id:$provider_id,repository_id:$repository_id,status:"incomplete",evidence_ids:[],
     findings:[finding(
       target_finding_id("EVIDENCE_COVERAGE_INCOMPLETE"; $gate.id; $provider_id; $repository_id; $simple);
       "evidence"; "verification"; $gate.id;
       "Evidence does not cover all required claims or architecture constraints"
     )]}
  else
    {provider_id:$provider_id,repository_id:$repository_id,status:"incomplete",evidence_ids:[],
     findings:[finding(
       target_finding_id("EVIDENCE_TRUST_INVALID"; $gate.id; $provider_id; $repository_id; $simple);
       "authority"; "human"; $gate.id;
       "Evidence does not satisfy the configured trust boundary"
     )]}
  end;

def provider_result(
  $policy; $scope; $gate; $provider_id; $all_evidence; $digests; $subjects;
  $claim_ids; $architecture; $blocking_architecture_ids;
  $implementation_run_ids; $now
):
  provider_targets($policy; $scope; $provider_id) as $targets |
  if ($targets | length) == 0 then
    {provider_id:$provider_id,status:"incomplete",evidence_ids:[],
     findings:[finding(
       "POLICY_PROVIDER_TARGET_UNRESOLVED:" + $gate.id + ":" + $provider_id;
       "policy"; "product"; $gate.id;
       ("Provider " + $provider_id + " has no target repository in feature scope")
     )]}
  else
    ([$targets[] as $repository_id |
      target_result(
        $policy; $scope; $gate; $provider_id; $repository_id; ($targets | length);
        $all_evidence; $digests; $subjects; $claim_ids; $architecture;
        $blocking_architecture_ids; $implementation_run_ids; $now
      )
    ]) as $repository_results |
    {provider_id:$provider_id,
     status:ranked_status($repository_results),
     evidence_ids:([$repository_results[].evidence_ids[]] | unique | sort),
     findings:[$repository_results[].findings[]]}
  end;

($policy[0]) as $p |
($gate_plan[0]) as $gp |
($scope[0]) as $s |
($claims[0]) as $c |
($architecture[0]) as $a |
($evidence[0]) as $all_evidence |
($waivers[0]) as $all_waivers |
($malformed[0]) as $malformed_files |
($provider_digests[0]) as $digests |
($s.repositories | map({key:.id,value:.subject}) | from_entries) as $subjects |
($c.claims | map(.id) | unique | sort) as $claim_ids |
($a.constraints | map(select(.enforcement == "blocking") | .id) | unique | sort) as $blocking_architecture_ids |
($a.constraints | map(select(.enforcement == "advisory") | .id) | unique | sort) as $advisory_architecture_ids |
($p.decisions[$decision].require_gates // []) as $decision_gate_ids |
([$all_evidence[] | select(.producer.role == "implementation") | .producer.run_id] | unique) as $implementation_run_ids |
[
  $gp.gates[]
  | select(.id as $id | $decision_gate_ids | index($id))
  | . as $gate
  | if $gate.applicability == "not_applicable" then
      {id:$gate.id,status:"ready",applicability:"not_applicable",reason:$gate.reason,
       evidence_id:null,evidence_ids:[],waiver:null,findings:[]}
    elif $gate.applicability == "unknown" then
      {id:$gate.id,status:"incomplete",applicability:"unknown",reason:$gate.reason,
       evidence_id:null,evidence_ids:[],waiver:null,
       findings:[finding("POLICY_APPLICABILITY_UNKNOWN:"+$gate.id;"policy";"product";$gate.id;"Gate applicability is unresolved")]}
    else
      ([$gate.providers[] as $provider_id |
        provider_result(
          $p; $s; $gate; $provider_id; $all_evidence; $digests; $subjects;
          $claim_ids; $a; $blocking_architecture_ids;
          $implementation_run_ids; $now
        )
      ]) as $provider_results |
      ($gate.provider_strategy // "all") as $provider_strategy |
      (if $provider_strategy == "any" then
         if any($provider_results[]; .status == "failed") then "failed"
         elif any($provider_results[]; .status == "ready") then "ready"
         elif any($provider_results[]; .status == "blocked") then "blocked"
         else "incomplete" end
       else ranked_status($provider_results) end) as $gate_status |
      (if $provider_strategy == "any" and $gate_status == "ready" then
         [$provider_results[] | select(.status == "ready")]
       elif $provider_strategy == "any" and $gate_status == "failed" then
         [$provider_results[] | select(.status == "failed")]
       else $provider_results end) as $relevant_provider_results |
      ([$relevant_provider_results[].evidence_ids[]] | unique | sort) as $evidence_ids |
      ([$all_waivers[]? | select(.gate_id == $gate.id)] | sort_by(.issued_at,.waiver_id) | reverse) as $gate_waivers |
      ([$gate_waivers[]
        | . as $waiver_candidate
        | select(any($all_evidence[];
            .evidence_id == $waiver_candidate.authority_evidence_id and
            .feature_id == $s.feature_id and
            .result == "passed" and
            .evidence_type == "waiver-approval" and
            .producer.id == $waiver_candidate.approver.id and
            (.provider_id as $provider_id | $p.providers[$provider_id].trust | test("authority";"i")) and
            .subject.repositories == $waiver_candidate.scope.repositories and
            (.coverage.claim_ids | sort) == ($waiver_candidate.scope.claim_ids | sort) and
            (.coverage.architecture_constraint_ids | sort) == ($waiver_candidate.scope.architecture_constraint_ids | sort) and
            .environment.id == $waiver_candidate.scope.environment_id
          ))
      ] | first) as $waiver |
      if ($gate_status == "incomplete" and $waiver != null and
          $waiver.feature_id == $s.feature_id and
          $waiver.scope.repositories == $subjects and
          $waiver.issued_at <= $now and $waiver.expires_at > $now) then
        {id:$gate.id,status:"ready",applicability:"required",reason:$gate.reason,
         evidence_id:(if ($evidence_ids|length)==1 then $evidence_ids[0] else null end),
         evidence_ids:$evidence_ids,waiver:$waiver,
         findings:[finding("GATE_WAIVED:"+$gate.id;"waiver";"human";$gate.id;("Gate waived: "+$waiver.reason))]}
      else
        {id:$gate.id,status:$gate_status,applicability:"required",reason:$gate.reason,
         evidence_id:(if ($evidence_ids|length)==1 then $evidence_ids[0] else null end),
         evidence_ids:$evidence_ids,waiver:null,
         findings:([$relevant_provider_results[].findings[]] +
           if ($gate_status == "incomplete" and ($gate_waivers | length) > 0) then
             [finding("WAIVER_INVALID:"+$gate.id;"authority";"human";$gate.id;"Waiver lacks matching trusted authority evidence or exact scope")]
           else [] end)}
      end
    end
] as $gate_results |
((($gp.impacts.all | index("architecture-sensitive")) != null) and (($a.sources | length) == 0)) as $architecture_source_unresolved |
([$s.repositories[]
  | select(($decision == "merge-ready" or $decision == "release-ready") and (.subject | startswith("commit:") | not))
  | finding("SUBJECT_NOT_COMMITTED:"+.id;"evidence";.role;null;("Decision "+$decision+" requires a committed subject for "+.id))
]) as $uncommitted_findings |
([$gate_results[].findings[]] +
 [$malformed_files[] | finding("EVIDENCE_MALFORMED:"+.;"evidence";"verification";null;("Malformed evidence file: "+.))] +
 (if $architecture_source_unresolved then
    [finding("ARCHITECTURE_SOURCE_UNRESOLVED";"policy";"architecture";null;"Architecture-sensitive scope has no governed architecture source")]
  else [] end) +
 $uncommitted_findings +
 ($gp.findings // [])) as $findings |
($gate_results | map(.status | status_rank) | max // 0) as $rank |
((($malformed_files|length)>0) or (($gp.findings // [] | length)>0)) as $derived_input_incomplete |
{
  schema_version:"1",
  feature_id:$s.feature_id,
  decision:$decision,
  status:(if $rank == 3 then "failed" elif $rank == 2 then "blocked" elif ($rank == 1 or $architecture_source_unresolved or $derived_input_incomplete or ($uncommitted_findings|length)>0) then "incomplete" else "ready" end),
  subject_fingerprint:$gp.subject_fingerprint,
  evaluated_at:$now,
  gates:($gate_results | sort_by(.id)),
  findings:($findings | sort_by(.id)),
  known_gaps:([$all_evidence[].known_gaps[]?] | sort_by(.id // .message // "")),
  waivers:([$gate_results[] | select(.waiver != null) | .waiver] | sort_by(.waiver_id)),
  advisory_architecture_constraint_ids:$advisory_architecture_ids
}
