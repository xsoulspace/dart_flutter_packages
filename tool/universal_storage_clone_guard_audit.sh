#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$repo_root/.." && pwd)"

matches="$(
  cd "$workspace_root"
  rg -n "cloneRepository\\s*\\(" \
    --glob "*.dart" \
    --glob "!**/.dart_tool/**" \
    --glob "!**/build/**" \
    --glob "!**/ios/**" \
    --glob "!**/android/**" \
    --glob "!**/macos/**" \
    --glob "!**/linux/**" \
    --glob "!**/windows/**" || true
)"

failed=0

is_allowed_path() {
  local path="$1"

  case "$path" in
    dart_flutter_packages/pkgs/universal_storage_interface/lib/src/version_control_service.dart)
      return 0
      ;;
    dart_flutter_packages/pkgs/universal_storage_sync/lib/src/capabilities/version_control_service.dart)
      return 0
      ;;
    dart_flutter_packages/pkgs/universal_storage_sync_utils/lib/src/repository_manager.dart)
      return 0
      ;;
    dart_flutter_packages/pkgs/universal_storage_github_api/lib/src/github_api_storage_provider.dart)
      return 0
      ;;
    dart_flutter_packages/pkgs/universal_storage_git_offline/lib/src/offline_git_storage_provider.dart)
      return 0
      ;;
    */test/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  path="${match%%:*}"
  if is_allowed_path "$path"; then
    continue
  fi
  echo "FAIL: disallowed direct cloneRepository(...) usage -> $match"
  failed=1
done <<< "$matches"

if [[ "$failed" -ne 0 ]]; then
  cat <<'EOF'
Clone guard audit failed.
Use RepositoryManager.cloneRepositoryToLocal(...) in app/runtime flows.
Direct cloneRepository(...) calls are only allowed inside provider internals and tests.
EOF
  exit 1
fi

echo "Clone guard audit passed."
