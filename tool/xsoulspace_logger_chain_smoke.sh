#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

restore_files=()
restore_backups=()

cleanup() {
  local idx
  for ((idx=0; idx<${#restore_files[@]}; idx++)); do
    local target="${restore_files[$idx]}"
    local backup="${restore_backups[$idx]}"
    if [[ -f "$backup" ]]; then
      mv "$backup" "$target"
    else
      rm -f "$target"
    fi
  done
}
trap cleanup EXIT

set_override() {
  local pkg_dir="$1"
  local content="$2"
  local target="$pkg_dir/pubspec_overrides.yaml"
  local backup=""

  if [[ -f "$target" ]]; then
    backup="$target.codex_backup"
    cp "$target" "$backup"
  fi

  printf "%s\n" "$content" > "$target"
  restore_files+=("$target")
  restore_backups+=("$backup")
}

run_pkg_checks() {
  local pkg_dir="$1"

  if rg -q "sdk:\\s*flutter" "$pkg_dir/pubspec.yaml"; then
    (
      cd "$pkg_dir"
      flutter pub get
      flutter analyze --no-fatal-infos --no-fatal-warnings lib test
      flutter test
    )
  else
    (
      cd "$pkg_dir"
      dart pub get
      dart analyze lib test
      dart test
    )
  fi
}

logger_dir="$repo_root/pkgs/xsoulspace_logger"
triage_dir="$repo_root/pkgs/xsoulspace_logger_triage"
io_dir="$repo_root/pkgs/xsoulspace_logger_io"
universal_storage_dir="$repo_root/pkgs/xsoulspace_logger_universal_storage"
flutter_dir="$repo_root/pkgs/xsoulspace_logger_flutter"

echo "=== logger smoke: xsoulspace_logger ==="
run_pkg_checks "$logger_dir"

override_logger=$'dependency_overrides:\n  xsoulspace_logger:\n    path: ../xsoulspace_logger'

for pkg_dir in "$triage_dir" "$io_dir" "$universal_storage_dir"; do
  echo "=== logger smoke: $(basename "$pkg_dir") ==="
  set_override "$pkg_dir" "$override_logger"
  run_pkg_checks "$pkg_dir"
done

override_flutter=$'dependency_overrides:\n  xsoulspace_logger:\n    path: ../xsoulspace_logger\n  xsoulspace_logger_triage:\n    path: ../xsoulspace_logger_triage'

echo "=== logger smoke: xsoulspace_logger_flutter ==="
set_override "$flutter_dir" "$override_flutter"
run_pkg_checks "$flutter_dir"

echo "Logger chain smoke checks passed."
