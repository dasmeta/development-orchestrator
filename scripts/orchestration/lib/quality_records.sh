#!/usr/bin/env bash

set -euo pipefail

quality_record_error() {
  printf 'invalid quality record: %s\n' "$1" >&2
  return 1
}

quality_json_digest() {
  git -C "$control_repo_root" hash-object --stdin | sed 's/^/git-blob:/'
}

quality_provider_config_digest() {
  local policy_path="$1"
  local provider_id="$2"

  jq -cS --arg provider_id "$provider_id" \
    '.providers[$provider_id]' "$policy_path" | quality_json_digest
}

quality_provider_allows_evidence_type() {
  local policy_path="$1"
  local provider_id="$2"
  local evidence_type="$3"

  jq -e \
    --arg provider_id "$provider_id" \
    --arg evidence_type "$evidence_type" '
      any(.gates[];
        (.providers | index($provider_id)) != null and
        (.evidence_types | index($evidence_type)) != null
      )
    ' "$policy_path" >/dev/null
}

quality_provider_is_authority() {
  local policy_path="$1"
  local provider_id="$2"

  jq -e --arg provider_id "$provider_id" '
    .providers[$provider_id].trust
    | type == "string" and test("authority"; "i")
  ' "$policy_path" >/dev/null
}

validate_evidence_record() {
  local input_path="$1"
  local expected_feature_id="${2:-}"

  if ! jq -e '
    def valid_id:
      type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._:-]*$");
    def id_array:
      type == "array" and all(.[]; valid_id);
    type == "object" and
    .schema_version == "1" and
    (.evidence_id | valid_id) and
    (.feature_id | valid_id) and
    (.evidence_type | valid_id) and
    (.provider_id | valid_id) and
    (.producer | type == "object") and
    (.producer.id | valid_id) and
    (.producer.role | valid_id) and
    (.producer.run_id | valid_id) and
    (.coverage | type == "object") and
    (.coverage.claim_ids | id_array) and
    (.coverage.architecture_constraint_ids | id_array) and
    (.subject.repositories | type == "object") and
    all(.subject.repositories | to_entries[];
      (.key | valid_id) and
      (.value | type == "string" and test("^(commit|worktree):[^\\r\\n]+$"))
    ) and
    (.policy_version | type == "string" and length > 0) and
    (.provider_config_digest | type == "string" and length > 0) and
    (.result | IN("passed", "failed", "blocked")) and
    (.outcome | type == "string" and length > 0) and
    (.environment | type == "object") and
    (.environment.id | valid_id) and
    ((.environment.fixture == null) or (.environment.fixture | type == "string")) and
    (.collected_at | type == "string" and length > 0) and
    ((.expires_at == null) or (.expires_at | type == "string" and length > 0)) and
    (.artifacts | type == "array") and
    all(.artifacts[];
      type == "object" and
      (.reference | type == "string" and length > 0) and
      ((.digest? == null) or (.digest | type == "string")) and
      ((.media_type? == null) or (.media_type | type == "string"))
    ) and
    (.findings | type == "array") and all(.findings[]; type == "object") and
    (.known_gaps | type == "array") and all(.known_gaps[]; type == "object")
  ' "$input_path" >/dev/null 2>&1; then
    quality_record_error "malformed evidence envelope"
    return 1
  fi

  if [[ -n "$expected_feature_id" ]] && \
     ! jq -e --arg feature_id "$expected_feature_id" \
       '.feature_id == $feature_id' "$input_path" >/dev/null; then
    quality_record_error "evidence feature ID does not match $expected_feature_id"
    return 1
  fi

  if jq -e '
    any(.artifacts[]?;
      (.reference | startswith("/")) or
      (.reference | startswith("file://")) or
      (.reference | test("^[A-Za-z]:[\\\\/]"))
    )
  ' "$input_path" >/dev/null; then
    quality_record_error "absolute local artifact references are not portable"
    return 1
  fi
}

validate_waiver_record() {
  local input_path="$1"
  local expected_feature_id="${2:-}"

  if ! jq -e '
    def valid_id:
      type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._:-]*$");
    def id_array:
      type == "array" and all(.[]; valid_id);
    type == "object" and
    .schema_version == "1" and
    (.waiver_id | valid_id) and
    (.feature_id | valid_id) and
    (.gate_id | valid_id) and
    ((.finding_id == null) or (.finding_id | type == "string" and length > 0)) and
    (.scope | type == "object") and
    (.scope.repositories | type == "object") and
    all(.scope.repositories | to_entries[];
      (.key | valid_id) and
      (.value | type == "string" and test("^(commit|worktree):[^\\r\\n]+$"))
    ) and
    (.scope.claim_ids | id_array) and
    (.scope.architecture_constraint_ids | id_array) and
    ((.scope.environment_id == null) or (.scope.environment_id | valid_id)) and
    (.approver.id | valid_id) and
    (.authority_evidence_id | valid_id) and
    (.reason | type == "string" and length > 0) and
    (.acknowledged_risk | type == "string" and length > 0) and
    (.issued_at | type == "string" and length > 0) and
    (.expires_at | type == "string" and length > 0) and
    (.allow_revision_change | type == "boolean")
  ' "$input_path" >/dev/null 2>&1; then
    quality_record_error "malformed waiver envelope"
    return 1
  fi

  if [[ -n "$expected_feature_id" ]] && \
     ! jq -e --arg feature_id "$expected_feature_id" \
       '.feature_id == $feature_id' "$input_path" >/dev/null; then
    quality_record_error "waiver feature ID does not match $expected_feature_id"
    return 1
  fi
}

validate_waiver_authority_evidence() {
  local waiver_path="$1"
  local evidence_path="$2"
  local policy_path="$3"
  local provider_id
  local expected_digest
  local expected_policy_version
  local expected_role

  provider_id="$(jq -r '.provider_id' "$evidence_path")"
  if ! quality_provider_is_authority "$policy_path" "$provider_id"; then
    quality_record_error "waiver evidence is not from a trusted authority provider"
    return 1
  fi

  expected_digest="$(quality_provider_config_digest "$policy_path" "$provider_id")"
  expected_policy_version="$(jq -r '.policy_version' "$policy_path")"
  expected_role="$(jq -r --arg provider_id "$provider_id" \
    '.providers[$provider_id].producer_role' "$policy_path")"
  if ! jq -e \
    --arg expected_digest "$expected_digest" \
    --arg expected_policy_version "$expected_policy_version" \
    --arg expected_role "$expected_role" '
      .provider_config_digest == $expected_digest and
      .policy_version == $expected_policy_version and
      .producer.role == $expected_role
    ' "$evidence_path" >/dev/null; then
    quality_record_error "waiver authority evidence provenance is stale"
    return 1
  fi

  if ! quality_provider_allows_evidence_type \
    "$policy_path" "$provider_id" "waiver-approval"; then
    quality_record_error "authority provider cannot approve waivers"
    return 1
  fi

  if ! jq -e --slurpfile evidence "$evidence_path" '
    ($evidence[0]) as $authority |
    $authority.result == "passed" and
    $authority.evidence_type == "waiver-approval" and
    .feature_id == $authority.feature_id and
    .approver.id == $authority.producer.id and
    .scope.repositories == $authority.subject.repositories and
    (.scope.claim_ids | sort) == ($authority.coverage.claim_ids | sort) and
    (.scope.architecture_constraint_ids | sort) ==
      ($authority.coverage.architecture_constraint_ids | sort) and
    .scope.environment_id == $authority.environment.id
  ' "$waiver_path" >/dev/null; then
    quality_record_error "waiver scope does not match its authority evidence"
    return 1
  fi
}
