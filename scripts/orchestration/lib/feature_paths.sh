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
