# Root justfile – run `just` from repo root
# Install: brew install just  (or cargo install just)
# `just` or `just pub-get`: flutter pub get in all pkgs with pubspec.yaml

default:
    just pub-get

generate-all:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=0
    generators="$(rg --files pkgs | rg '/tool/generate\.dart$' | sort || true)"
    if [ -z "$generators" ]; then
      echo "No tool/generate.dart scripts found."
      exit 0
    fi
    while IFS= read -r gen; do
      [ -n "$gen" ] || continue
      pkg_dir="$(dirname "$(dirname "$gen")")"
      echo "=== $pkg_dir ==="
      if [ "$pkg_dir" = "pkgs/xsoulspace_steamworks_raw" ] && [ -z "${STEAMWORKS_SDK_PATH:-}" ]; then
        echo "Skipping $pkg_dir (set STEAMWORKS_SDK_PATH to enable generation)."
        continue
      fi
      if ! (cd "$pkg_dir" && dart run tool/generate.dart); then
        failed=1
      fi
    done <<< "$generators"
    exit "$failed"

pub-get:
    #!/usr/bin/env bash
    set -euo pipefail
    for d in pkgs/*/; do
      if [ -d "$d" ] && [ -f "$d/pubspec.yaml" ]; then
        (cd "$d" && flutter pub get)
      fi
    done

docs-check:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=0
    for d in pkgs/*/; do
      [ -f "$d/pubspec.yaml" ] || continue
      for f in README.md CHANGELOG.md LICENSE; do
        if [ ! -f "$d/$f" ]; then
          echo "Missing $f in ${d%/}"
          failed=1
        fi
      done
    done
    if [ "$failed" -ne 0 ]; then
      exit 1
    fi
    echo "All packages contain README.md, CHANGELOG.md, and LICENSE."

storage-path-audit:
    #!/usr/bin/env bash
    set -euo pipefail
    bash tool/universal_storage_path_audit.sh

clone-guard-audit:
    #!/usr/bin/env bash
    set -euo pipefail
    bash tool/universal_storage_clone_guard_audit.sh

storage-release-g6:
    #!/usr/bin/env bash
    set -euo pipefail
    bash tool/universal_storage_release_gate_g6.sh

publish-dry-run pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    just storage-release-g6
    if [ -z "{{pkg}}" ]; then
      echo "Usage: just publish-dry-run <package_name>"
      exit 2
    fi
    pkg_dir="pkgs/{{pkg}}"
    if [ ! -f "$pkg_dir/pubspec.yaml" ]; then
      echo "Package not found: {{pkg}}"
      exit 2
    fi
    if rg -q "sdk:\\s*flutter" "$pkg_dir/pubspec.yaml"; then
      (cd "$pkg_dir" && flutter pub publish --dry-run --ignore-warnings)
    else
      (cd "$pkg_dir" && dart pub publish --dry-run --ignore-warnings)
    fi

publish-dry-run-all:
    #!/usr/bin/env bash
    set -euo pipefail
    just storage-release-g6
    failed=0
    for d in pkgs/*/; do
      [ -f "$d/pubspec.yaml" ] || continue
      pkg="${d#pkgs/}"
      pkg="${pkg%/}"
      echo "=== $pkg ==="
      if rg -q "sdk:\\s*flutter" "$d/pubspec.yaml"; then
        (cd "$d" && flutter pub publish --dry-run --ignore-warnings) || failed=1
      else
        (cd "$d" && dart pub publish --dry-run --ignore-warnings) || failed=1
      fi
    done
    exit "$failed"

# CI-style checks for newly added CloudKit packages.
ci-cloudkit:
    #!/usr/bin/env bash
    set -euo pipefail
    packages=(
      "pkgs/universal_storage_cloudkit_platform_interface"
      "pkgs/universal_storage_cloudkit_web"
      "pkgs/universal_storage_cloudkit"
      "pkgs/universal_storage_cloudkit_apple"
    )
    for d in "${packages[@]}"; do
      echo "=== $d ==="
      (cd "$d" && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test)
    done

platform-sdk-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    bash tool/platform_sdk_verify.sh

platform-sdk-publish-dry-run:
    #!/usr/bin/env bash
    set -euo pipefail
    bash tool/platform_sdk_publish_dry_run.sh

xsoulspace-readiness scope="all" artifact="tool/artifacts/xsoulspace_production_readiness.json":
    #!/usr/bin/env bash
    set -euo pipefail
    dart tool/xsoulspace_production_readiness.dart --scope "{{scope}}" --output "{{artifact}}"

xsoulspace-public-gate artifact="tool/artifacts/xsoulspace_production_readiness.json":
    #!/usr/bin/env bash
    set -euo pipefail
    dart tool/xsoulspace_production_readiness.dart --scope public --output "{{artifact}}" --fail-on-blocked

xsoulspace-internal-gate artifact="tool/artifacts/xsoulspace_production_readiness.json":
    #!/usr/bin/env bash
    set -euo pipefail
    dart tool/xsoulspace_production_readiness.dart --scope internal --output "{{artifact}}" --fail-on-blocked

xsoulspace-gates artifact="tool/artifacts/xsoulspace_production_readiness.json":
    #!/usr/bin/env bash
    set -euo pipefail
    dart tool/xsoulspace_production_readiness.dart --scope all --output "{{artifact}}" --fail-on-blocked

xsoulspace-logger-chain-dry-run:
    #!/usr/bin/env bash
    set -euo pipefail
    packages=(
      "xsoulspace_logger"
      "xsoulspace_logger_triage"
      "xsoulspace_logger_io"
      "xsoulspace_logger_universal_storage"
      "xsoulspace_logger_flutter"
    )
    for pkg in "${packages[@]}"; do
      pkg_dir="pkgs/$pkg"
      [ -f "$pkg_dir/pubspec.yaml" ] || { echo "Missing package: $pkg"; exit 2; }
      echo "=== logger chain dry-run: $pkg ==="
      if rg -q "sdk:\\s*flutter" "$pkg_dir/pubspec.yaml"; then
        (cd "$pkg_dir" && flutter pub get && flutter pub publish --dry-run --ignore-warnings)
      else
        (cd "$pkg_dir" && dart pub get && dart pub publish --dry-run --ignore-warnings)
      fi
    done

xsoulspace-logger-chain-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    bash tool/xsoulspace_logger_chain_smoke.sh
