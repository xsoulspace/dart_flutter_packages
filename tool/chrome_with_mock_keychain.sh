#!/usr/bin/env bash
set -euo pipefail

CHROME_BIN="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

if [[ ! -x "${CHROME_BIN}" ]]; then
  echo "Chrome binary not found or not executable: ${CHROME_BIN}" >&2
  echo "Set CHROME_BIN or CHROME_EXECUTABLE to a valid Chrome binary." >&2
  exit 127
fi

exec "${CHROME_BIN}" --use-mock-keychain "$@"
