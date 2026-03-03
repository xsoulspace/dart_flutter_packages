#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_path_default="$repo_root/tool/artifacts/storage_release_gate_g6.json"
artifact_path="${1:-${UNIVERSAL_STORAGE_GATE_ARTIFACT:-$artifact_path_default}}"

if [[ "$artifact_path" != /* ]]; then
  artifact_path="$repo_root/$artifact_path"
fi
mkdir -p "$(dirname "$artifact_path")"

packages_env="${UNIVERSAL_STORAGE_GATE_PACKAGES:-universal_storage_sync universal_storage_sync_utils universal_storage_local_db}"
read -r -a gate_packages <<< "$packages_env"

run_analyze() {
  local pkg_dir="$1"
  (cd "$pkg_dir" && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings)
}

run_tests() {
  local pkg_dir="$1"
  (cd "$pkg_dir" && flutter test)
}

echo "== [1/5] Universal storage path audit =="
bash "$repo_root/tool/universal_storage_path_audit.sh"

echo "== [2/5] Clone guard audit =="
bash "$repo_root/tool/universal_storage_clone_guard_audit.sh"

echo "== [3/5] Analyzer (errors-only) =="
for pkg in "${gate_packages[@]}"; do
  pkg_dir="$repo_root/pkgs/$pkg"
  if [[ ! -f "$pkg_dir/pubspec.yaml" ]]; then
    echo "Missing package for analyze step: $pkg"
    exit 2
  fi
  echo "=== analyze: $pkg ==="
  run_analyze "$pkg_dir"
done

echo "== [4/5] Tests =="
for pkg in "${gate_packages[@]}"; do
  pkg_dir="$repo_root/pkgs/$pkg"
  echo "=== test: $pkg ==="
  run_tests "$pkg_dir"
done

echo "== [5/5] Gate G6 evaluator =="
(
  cd "$repo_root/pkgs/universal_storage_sync"
  dart run tool/storage_release_gate_ci.dart --output "$artifact_path"
)

echo "Storage release gate G6 passed. Artifact: $artifact_path"
