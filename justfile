# Root justfile – run `just` from repo root
# Install: brew install just  (or cargo install just)
# `just` or `just pub-get`: flutter pub get in all pkgs with pubspec.yaml

default:
    just pub-get

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

publish-dry-run pkg:
    #!/usr/bin/env bash
    set -euo pipefail
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
      (cd "$pkg_dir" && flutter pub publish --dry-run)
    else
      (cd "$pkg_dir" && dart pub publish --dry-run)
    fi

publish-dry-run-all:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=0
    for d in pkgs/*/; do
      [ -f "$d/pubspec.yaml" ] || continue
      pkg="${d#pkgs/}"
      pkg="${pkg%/}"
      echo "=== $pkg ==="
      if rg -q "sdk:\\s*flutter" "$d/pubspec.yaml"; then
        (cd "$d" && flutter pub publish --dry-run) || failed=1
      else
        (cd "$d" && dart pub publish --dry-run) || failed=1
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
