#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
control_repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib/quality_records.sh"

kind=""
input_path=""
feature_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind) kind="$2"; shift 2 ;;
    --input) input_path="$2"; shift 2 ;;
    --feature-id) feature_id="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$kind" || -z "$input_path" ]]; then
  echo "record kind and input are required" >&2
  exit 1
fi

case "$kind" in
  evidence) validate_evidence_record "$input_path" "$feature_id" ;;
  waiver) validate_waiver_record "$input_path" "$feature_id" ;;
  *) echo "unknown quality record kind: $kind" >&2; exit 1 ;;
esac
