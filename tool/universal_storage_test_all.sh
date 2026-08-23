#!/usr/bin/env bash
# Run the full Universal Storage test suite across all packages in parallel.
# Usage: tool/universal_storage_test_all.sh [package-filter]
#   e.g. tool/universal_storage_test_all.sh sync
set -uo pipefail

packages=(
  universal_storage_interface
  universal_storage_sync
  universal_storage_filesystem
  universal_storage_local_db
  universal_storage_git_offline
  universal_storage_github_api
  universal_storage_cloudkit
)

filter="${1:-}"
if [ -n "$filter" ]; then
  packages=($(printf '%s\n' "${packages[@]}" | grep "$filter"))
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pids=()
for pkg in "${packages[@]}"; do
  dir="$root/pkgs/$pkg"
  if [ ! -f "$dir/pubspec.yaml" ]; then
    echo "skip $pkg (no pubspec)"
    continue
  fi
  (
    cd "$dir"
    if flutter test >"$tmpdir/$pkg.log" 2>&1; then
      echo "PASS $pkg"
    else
      echo "FAIL $pkg  (log: $tmpdir kept? no — see below)"
      tail -20 "$tmpdir/$pkg.log"
    fi
  ) &
  pids+=($!)
done

failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || failed=1
done

if [ "$failed" -eq 0 ]; then
  echo "All Universal Storage suites passed."
else
  echo "One or more suites FAILED."
fi
exit "$failed"
