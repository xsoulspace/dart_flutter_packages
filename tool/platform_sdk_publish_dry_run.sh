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

# In local monorepo flows we keep path overrides in pubspec_overrides.yaml.
# These produce publish warnings; default to ignoring warnings for dry-run.
IGNORE_WARNINGS="${IGNORE_WARNINGS:-1}"

for pkg in "${PACKAGES[@]}"; do
  echo "--- ${pkg} ---"

  args=(pub publish --dry-run)
  if [[ "${IGNORE_WARNINGS}" == "1" ]]; then
    args+=(--ignore-warnings)
  fi

  if rg -q "sdk:\s*flutter" "${pkg}/pubspec.yaml"; then
    (cd "${pkg}" && flutter "${args[@]}")
  else
    (cd "${pkg}" && dart "${args[@]}")
  fi
done

echo "platform_sdk_publish_dry_run: OK"
