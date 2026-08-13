def covers_all($required; $actual):
  (($required - $actual) | length) == 0;

def status_rank:
  if . == "failed" then 3
  elif . == "blocked" then 2
  elif . == "incomplete" then 1
  else 0 end;

def finding($id; $class; $owner; $gate_id; $message):
  {id:$id, class:$class, owner:$owner, gate_id:$gate_id, message:$message};

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
      {id:$gate.id,status:"ready",applicability:"not_applicable",reason:$gate.reason,evidence_id:null,waiver:null,findings:[]}
    elif $gate.applicability == "unknown" then
      {id:$gate.id,status:"incomplete",applicability:"unknown",reason:$gate.reason,evidence_id:null,waiver:null,
       findings:[finding("POLICY_APPLICABILITY_UNKNOWN:"+$gate.id;"policy";"product";$gate.id;"Gate applicability is unresolved")]}
    else
      ([$all_evidence[]
        | select(.provider_id as $id | $gate.providers | index($id))
        | select(.evidence_type as $type | $gate.evidence_types | index($type))
      ] | sort_by(.collected_at,.evidence_id) | reverse) as $allowed |
      ([$allowed[]
        | select(.feature_id == $s.feature_id)
        | select(.policy_version == $p.policy_version)
        | select(.provider_config_digest == $digests[.provider_id])
        | select(.subject.repositories == $subjects)
        | select((.expires_at == null) or (.expires_at > $now))
        | select(
            if $gate.coverage.claims == "all"
            then covers_all($claim_ids; (.coverage.claim_ids | unique))
            else true end
          )
        | select(
            if $gate.coverage.architecture == "all_blocking"
            then covers_all($blocking_architecture_ids; (.coverage.architecture_constraint_ids | unique))
            elif $gate.coverage.architecture == "all"
            then covers_all(([$a.constraints[].id] | unique); (.coverage.architecture_constraint_ids | unique))
            else true end
          )
        | select(
            if (($gate.coverage.architecture != "none") or (.evidence_type | test("verification|conformance")))
            then . as $candidate_evidence |
              $candidate_evidence.producer.role != "implementation" and
              (($implementation_run_ids | index($candidate_evidence.producer.run_id)) == null)
            else true end
          )
      ] | first) as $selected |
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
      if $selected != null then
        ($selected.findings // []) as $provider_findings |
        {id:$gate.id,
         status:(if $selected.result == $gate.required_result then "ready" elif $selected.result == "blocked" then "blocked" else "failed" end),
         applicability:"required",reason:$gate.reason,evidence_id:$selected.evidence_id,waiver:null,
         findings:($provider_findings +
           if $selected.result == $gate.required_result then []
           elif $selected.result == "blocked" then [finding("EVIDENCE_BLOCKED:"+$gate.id;"evidence";"verification";$gate.id;"The selected provider was blocked")]
           else [finding("EVIDENCE_FAILED:"+$gate.id;"evidence";"implementation";$gate.id;"Valid evidence reports a failed result")] end)}
      elif ($waiver != null and $waiver.feature_id == $s.feature_id and $waiver.scope.repositories == $subjects and
            $waiver.issued_at <= $now and $waiver.expires_at > $now) then
        {id:$gate.id,status:"ready",applicability:"required",reason:$gate.reason,evidence_id:null,waiver:$waiver,
         findings:[finding("GATE_WAIVED:"+$gate.id;"waiver";"human";$gate.id;("Gate waived: "+$waiver.reason))]}
      elif ($gate_waivers | length) > 0 then
        {id:$gate.id,status:"incomplete",applicability:"required",reason:$gate.reason,evidence_id:null,waiver:null,
         findings:[finding("WAIVER_INVALID:"+$gate.id;"authority";"human";$gate.id;"Waiver lacks matching trusted authority evidence or exact scope")]}
      elif ($allowed | length) == 0 then
        {id:$gate.id,status:"incomplete",applicability:"required",reason:$gate.reason,evidence_id:null,waiver:null,
         findings:[finding("EVIDENCE_MISSING:"+$gate.id;"evidence";"verification";$gate.id;("No valid evidence satisfies gate "+$gate.id))]}
      else
        ($allowed[0]) as $candidate |
        if $candidate.subject.repositories != $subjects then
          {id:$gate.id,status:"incomplete",applicability:"required",reason:$gate.reason,evidence_id:null,waiver:null,
           findings:[finding("EVIDENCE_SUBJECT_MISMATCH:"+$gate.id;"evidence";"implementation";$gate.id;"Evidence does not match the current repository subjects")]}
        elif $candidate.policy_version != $p.policy_version or $candidate.provider_config_digest != $digests[$candidate.provider_id] then
          {id:$gate.id,status:"incomplete",applicability:"required",reason:$gate.reason,evidence_id:null,waiver:null,
           findings:[finding("EVIDENCE_PROVENANCE_STALE:"+$gate.id;"evidence";"verification";$gate.id;"Evidence policy or provider configuration is stale")]}
        elif $candidate.expires_at != null and $candidate.expires_at <= $now then
          {id:$gate.id,status:"incomplete",applicability:"required",reason:$gate.reason,evidence_id:null,waiver:null,
           findings:[finding("EVIDENCE_EXPIRED:"+$gate.id;"evidence";"verification";$gate.id;"Evidence has expired")]}
        elif (($gate.coverage.claims == "all" and (covers_all($claim_ids; ($candidate.coverage.claim_ids | unique)) | not)) or
              ($gate.coverage.architecture == "all_blocking" and (covers_all($blocking_architecture_ids; ($candidate.coverage.architecture_constraint_ids | unique)) | not)) or
              ($gate.coverage.architecture == "all" and (covers_all(([$a.constraints[].id] | unique); ($candidate.coverage.architecture_constraint_ids | unique)) | not))) then
          {id:$gate.id,status:"incomplete",applicability:"required",reason:$gate.reason,evidence_id:null,waiver:null,
           findings:[finding("EVIDENCE_COVERAGE_INCOMPLETE:"+$gate.id;"evidence";"verification";$gate.id;"Evidence does not cover all required claims or architecture constraints")]}
        else
          {id:$gate.id,status:"incomplete",applicability:"required",reason:$gate.reason,evidence_id:null,waiver:null,
           findings:[finding("EVIDENCE_TRUST_INVALID:"+$gate.id;"authority";"human";$gate.id;"Evidence does not satisfy the configured trust boundary")]}
        end
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
