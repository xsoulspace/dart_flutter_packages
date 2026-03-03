#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PACKAGES=(
  "pkgs/xsoulspace_platform_core_interface"
  "pkgs/xsoulspace_platform_social_interface"
  "pkgs/xsoulspace_platform_gamification_interface"
  "pkgs/xsoulspace_platform_multiplayer_interface"
  "pkgs/xsoulspace_platform_foundation"
  "pkgs/xsoulspace_platform_purchases_bridge"
  "pkgs/xsoulspace_platform_ads_bridge"
  "pkgs/xsoulspace_platform_monetization_bridge"
  "pkgs/xsoulspace_vkplay_js"
  "pkgs/xsoulspace_ysdk_games_js"
  "pkgs/xsoulspace_crazygames_js"
  "pkgs/xsoulspace_discord_js"
  "pkgs/xsoulspace_platform_steam"
  "pkgs/xsoulspace_platform_vkplay"
  "pkgs/xsoulspace_platform_yandex_games"
  "pkgs/xsoulspace_platform_crazygames"
  "pkgs/xsoulspace_platform_discord"
  "pkgs/xsoulspace_monetization_yandex_games"
  "pkgs/xsoulspace_monetization_ads_crazygames"
  "pkgs/xsoulspace_platform_yandex_games_purchases"
  "pkgs/xsoulspace_platform_crazygames_ads"
  "pkgs/xsoulspace_vkplay_server_api"
  "pkgs/xsoulspace_discord_server_api"
)

WRAPPER_PACKAGES=(
  "pkgs/xsoulspace_vkplay_js"
  "pkgs/xsoulspace_ysdk_games_js"
  "pkgs/xsoulspace_crazygames_js"
  "pkgs/xsoulspace_discord_js"
)

echo "=== Repository gates ==="
for pkg in "${PACKAGES[@]}"; do
  pubspec="${pkg}/pubspec.yaml"
  if rg -q "^\s*path:\s*\.\./" "${pubspec}"; then
    echo "FAIL: local path dependency found in ${pubspec}"
    rg -n "^\s*path:\s*\.\./" "${pubspec}" || true
    exit 1
  fi

  for required in README.md CHANGELOG.md LICENSE; do
    if [[ ! -f "${pkg}/${required}" ]]; then
      echo "FAIL: missing ${required} in ${pkg}"
      exit 1
    fi
  done
done

echo "=== Package checks ==="
for pkg in "${PACKAGES[@]}"; do
  echo "--- ${pkg} ---"
  if rg -q "sdk:\s*flutter" "${pkg}/pubspec.yaml"; then
    (cd "${pkg}" && flutter pub get)
    (cd "${pkg}" && flutter analyze --no-fatal-infos --no-fatal-warnings)
    (cd "${pkg}" && flutter test)
  else
    (cd "${pkg}" && dart pub get)
    (cd "${pkg}" && dart analyze)
    (cd "${pkg}" && dart test)
  fi
done

echo "=== Wrapper generator/browser checks ==="
for pkg in "${WRAPPER_PACKAGES[@]}"; do
  echo "--- ${pkg} ---"
  (cd "${pkg}" && dart run tool/generate.dart --check)
  (cd "${pkg}" && dart test -p chrome)
done

echo "platform_sdk_verify: OK"
