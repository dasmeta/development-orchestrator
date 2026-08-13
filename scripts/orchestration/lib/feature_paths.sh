#!/usr/bin/env bash

set -euo pipefail

feature_id_from_dir() {
  local feature_dir="$1"
  basename "$feature_dir"
}

feature_manifest_path() {
  local feature_dir="$1"
  echo "$feature_dir/state/manifest.json"
}

feature_scope_path() {
  echo "$1/scope.json"
}

feature_claims_path() {
  echo "$1/claims.json"
}

feature_architecture_path() {
  echo "$1/architecture.json"
}

feature_evidence_dir() {
  echo "$1/evidence"
}

feature_waiver_dir() {
  echo "$1/waivers"
}

feature_readiness_path() {
  echo "$1/state/readiness.json"
}

feature_repair_brief_path() {
  echo "$1/state/repair-brief.json"
}

feature_run_history_dir() {
  echo "$1/state/runs"
}
