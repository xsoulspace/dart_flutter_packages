#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$repo_root/.." && pwd)"

targets=(
  "prompt_character"
  "drip"
  "word_by_word_game"
  "daily_budget_planner/packages/mobile_app"
  "last_answer/packages/core"
)

universal_packages=(
  "universal_storage_filesystem"
  "universal_storage_local_db"
  "universal_storage_interface"
  "universal_storage_sync"
  "universal_storage_sync_utils"
)

failed=0

contains_universal_path_in_pubspec() {
  local pubspec="$1"
  awk '
    BEGIN { in_section = 0; pkg = "" }
    /^[^[:space:]][^:]*:/ {
      section = $0
      sub(/:.*/, "", section)
      in_section = (section == "dependencies" || section == "dev_dependencies" || section == "dependency_overrides")
      pkg = ""
      next
    }
    !in_section { next }
    /^  [a-zA-Z0-9_]+:/ {
      pkg = $0
      sub(/^  /, "", pkg)
      sub(/:.*/, "", pkg)
      next
    }
    pkg ~ /^universal_storage_(filesystem|local_db|interface|sync|sync_utils)$/ && /^    path:/ {
      print NR ":" pkg ":" $0
    }
  ' "$pubspec"
}

has_override_path_entry() {
  local overrides="$1"
  local pkg="$2"
  awk -v expected_pkg="$pkg" '
    BEGIN { in_overrides = 0; current_pkg = ""; expect_path = 0; found = 0 }
    /^dependency_overrides:/ { in_overrides = 1; next }
    in_overrides && /^[^[:space:]]/ { in_overrides = 0 }
    !in_overrides { next }
    /^  [a-zA-Z0-9_]+:/ {
      current_pkg = $0
      sub(/^  /, "", current_pkg)
      sub(/:.*/, "", current_pkg)
      expect_path = (current_pkg == expected_pkg)
      next
    }
    expect_path && /^    path:/ {
      found = 1
      expect_path = 0
    }
    END { exit(found ? 0 : 1) }
  ' "$overrides"
}

for target in "${targets[@]}"; do
  app_dir="$workspace_root/$target"
  pubspec="$app_dir/pubspec.yaml"
  overrides="$app_dir/pubspec_overrides.yaml"

  echo "== $target =="

  if [[ ! -f "$pubspec" ]]; then
    echo "FAIL: missing pubspec.yaml"
    failed=1
    continue
  fi

  if [[ ! -f "$overrides" ]]; then
    echo "FAIL: missing pubspec_overrides.yaml"
    failed=1
    continue
  fi

  path_hits="$(contains_universal_path_in_pubspec "$pubspec" || true)"
  if [[ -n "$path_hits" ]]; then
    echo "FAIL: universal_storage path sourcing still in pubspec.yaml"
    echo "$path_hits"
    failed=1
  fi

  for pkg in "${universal_packages[@]}"; do
    if ! has_override_path_entry "$overrides" "$pkg"; then
      echo "FAIL: missing $pkg path override in pubspec_overrides.yaml"
      failed=1
    fi
  done
done

if [[ "$failed" -ne 0 ]]; then
  echo "Universal storage path audit failed."
  exit 1
fi

echo "Universal storage path audit passed."
