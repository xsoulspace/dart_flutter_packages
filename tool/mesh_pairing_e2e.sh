#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/pkgs/universal_storage_mesh/example/mesh_pairing_app"
ARTIFACTS="$ROOT/tool/.mesh_pairing_e2e"
RELAY_PORT="${MESH_RELAY_PORT:-45910}"
if [[ -z "${WEB_PORT:-}" ]]; then
  WEB_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
fi
DDS_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
mkdir -p "$ARTIFACTS"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'E2E FAILED: %s\n' "$*" >&2; exit 1; }

cleanup() {
  log 'Cleaning up launched processes'
  [[ -n "${MAC_PID:-}" ]] && kill "$MAC_PID" 2>/dev/null || true
  [[ -n "${WEB_PID:-}" ]] && kill "$WEB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

log 'Analyzing app'
(cd "$ROOT" && HOME=/tmp DART_SUPPRESS_ANALYTICS=true flutter analyze \
  pkgs/universal_storage_mesh/example/mesh_pairing_app) >"$ARTIFACTS/analyze.log" || true
if rg -n '^  error • ' "$ARTIFACTS/analyze.log" >/dev/null; then
  cat "$ARTIFACTS/analyze.log"
  fail 'analyzer errors'
fi

log 'Stopping previous app instances'
pkill -f "$APP/build/macos/.*mesh_pairing_app.app" 2>/dev/null || true
pkill -f 'flutter_tools.snapshot run -d chrome' 2>/dev/null || true
sleep 1

log 'Building and launching macOS host'
(cd "$APP" && HOME=/tmp DART_SUPPRESS_ANALYTICS=true flutter run -d macos \
  --dart-define=MESH_PEER_ID=alice \
  --dart-define=MESH_HOST=true) >"$ARTIFACTS/macos.log" 2>&1 &
MAC_PID=$!

for _ in $(seq 1 120); do
  if lsof -nP -iTCP:"$RELAY_PORT" -sTCP:LISTEN | grep -q LISTEN; then break; fi
  sleep 1
done
lsof -nP -iTCP:"$RELAY_PORT" -sTCP:LISTEN | grep -q LISTEN ||
  { tail -100 "$ARTIFACTS/macos.log"; fail 'relay did not start'; }

log 'Launching web client'
(cd "$APP" && HOME=/tmp DART_SUPPRESS_ANALYTICS=true flutter run -d chrome \
  --web-port "$WEB_PORT" \
  --dart-define=MESH_PEER_ID=bob \
  --dart-define=MESH_HOST=false \
  --dart-define=MESH_RELAY_PORT="$RELAY_PORT") >"$ARTIFACTS/web.log" 2>&1 &
WEB_PID=$!

get_vm_uri() {
  local file=$1
  for _ in $(seq 1 300); do
    uri=$(rg -o 'A Dart VM Service on [^ ]+ is available at: (http://[^ ]+)' -r '$1' \
      "$file" 2>/dev/null | tail -1 || true)
    if [[ -z "$uri" ]]; then
      uri=$(rg -o '(ws://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_=-]+/ws)' "$file" 2>/dev/null |
        tail -1 || true)
      [[ -n "$uri" ]] && { printf '%s' "$uri"; return 0; }
    fi
    [[ -n "$uri" ]] && { printf '%s' "$uri"; return 0; }
    sleep 1
  done
  return 1
}

MAC_HTTP=$(get_vm_uri "$ARTIFACTS/macos.log") || { tail -100 "$ARTIFACTS/macos.log"; fail 'macOS VM URI missing'; }
WEB_HTTP=$(get_vm_uri "$ARTIFACTS/web.log") || { tail -100 "$ARTIFACTS/web.log"; fail 'web VM URI missing'; }
printf 'MAC_HTTP=%s\nWEB_HTTP=%s\n' "$MAC_HTTP" "$WEB_HTTP" >"$ARTIFACTS/uris.txt"
normalize_ws() {
  local uri=${1:-}
  uri="${uri%/}"
  [[ "$uri" == */ws ]] || uri="$uri/ws"
  printf '%s' "${uri/http:/ws:}"
}
MAC_WS=$(normalize_ws "$MAC_HTTP")
WEB_WS=$(normalize_ws "$WEB_HTTP")

fmtk_exec() {
  local target=$1 name=$2 args=${3:-{}}
  local json
  printf 'FMTK_TOOL_ARGS=[%s]\n' "$args" >&2 || true
  json=$(FMTK_TARGET_URI="$target" FMTK_TOOL_ARGS="$args" python3 -c \
    'import json,os; d=json.loads(os.environ["FMTK_TOOL_ARGS"]); d.setdefault("connection",{})["uri"]=os.environ["FMTK_TARGET_URI"]; print(json.dumps(d))')
  /tmp/fmtk-fixed exec --name "$name" --args "$json"
}

assert_ok() {
  local output=$1 step=$2
  python3 -c 'import json,sys; x=json.loads(sys.argv[1]); assert x.get("ok"), x' \
    "$output" || { printf '%s\n' "$output"; fail "$step failed"; }
}

wait_ready() {
  local target=$1 label=$2 output
  for attempt in $(seq 1 60); do
    # Re-resolve web targets because the debug service URI can rotate while
    # Chrome is starting.
    if [[ "$label" == web ]]; then
      web_http=$(rg -o 'A Dart VM Service on [^ ]+ is available at: (http://[^ ]+)' -r '$1' \
        "$ARTIFACTS/web.log" 2>/dev/null | tail -1)
      target=$(normalize_ws "$web_http")
    fi
    [[ -n "$target" ]] || { sleep 1; continue; }
    output=$(fmtk_exec "$target" get_extension_rpcs || true)
    if python3 -c 'import json,sys; x=json.loads(sys.argv[1]); assert x.get("ok"); assert any("mcp.toolkit" in e for e in x["data"])' \
      "$output" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  printf '%s\n' "$output"
  fail "$label toolkit not ready"
}

log 'Waiting for FMTK toolkits'
wait_ready "$MAC_WS" macOS
wait_ready "$WEB_WS" web

snapshot_texts() {
  local target=$1 output file
  output=$(fmtk_exec "$target" semantic_snapshot)
  assert_ok "$output" semantic_snapshot
  printf '%s\n' "$output" | python3 -c 'import json,sys; x=json.load(sys.stdin); print("\n".join(n.get("label","") for n in x["data"]["nodes"]))'
}

log 'Checking initial UI state'
MAC_TEXTS=$(snapshot_texts "$MAC_WS") || { printf '%s\n' "$MAC_TEXTS"; fail 'macOS snapshot failed'; }
WEB_TEXTS=$(snapshot_texts "$WEB_WS") || { printf '%s\n' "$WEB_TEXTS"; fail 'web snapshot failed'; }
printf '%s\n' "$MAC_TEXTS" > "$ARTIFACTS/mac_texts.txt"
printf '%s\n' "$WEB_TEXTS" > "$ARTIFACTS/web_texts.txt"

grep -q 'alice pairing\|ready — show or paste a pairing code' <<<"$MAC_TEXTS" ||
  { printf '%s\n' "$MAC_TEXTS"; fail 'macOS not on pairing page'; }
grep -q 'bob pairing\|ready — show or paste a pairing code' <<<"$WEB_TEXTS" ||
  { printf '%s\n' "$WEB_TEXTS"; fail 'web not on pairing page'; }
grep -q 'startup failed' <<<"$WEB_TEXTS" && fail 'web startup failed'

log 'Automating pairing through app tools'
WEB_HTTP=$(rg -o 'A Dart VM Service on [^ ]+ is available at: (http://[^ ]+)' -r '$1' \
  "$ARTIFACTS/web.log" 2>/dev/null | tail -1)
[[ -n "$WEB_HTTP" ]] || fail 'web VM URI missing before pairing'
WEB_WS=$(normalize_ws "$WEB_HTTP")
WEB_CODE_RAW=$(fmtk_exec "$WEB_WS" fmt_client_tool \
  '{"toolName":"pairing_code","arguments":{}}') || fail 'web pairing_code invocation failed'
assert_ok "$WEB_CODE_RAW" 'web pairing_code'
WEB_CODE=$(printf '%s\n' "$WEB_CODE_RAW" | python3 -c '
import json,sys
x=json.load(sys.stdin)
d=x["data"]
if isinstance(d.get("result"),dict):
    d=d["result"]
def find_base64(value):
    if isinstance(value, dict):
        if value.get("base64"):
            return value["base64"]
        for child in value.values():
            found = find_base64(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_base64(child)
            if found:
                return found
print(find_base64(d))
')
[[ -n "$WEB_CODE" ]] || { printf '%s\n' "$WEB_CODE_RAW"; fail 'web pairing code missing'; }

MAC_ACCEPT=$(fmtk_exec "$MAC_WS" fmt_client_tool "$(python3 -c 'import json,sys; print(json.dumps({"toolName":"accept_pairing","arguments":{"base64":sys.argv[1]}}))' "$WEB_CODE")") ||
  { printf '%s\n' "$MAC_ACCEPT"; fail 'macOS accept_pairing failed'; }
assert_ok "$MAC_ACCEPT" 'macOS accept_pairing'

MAC_TEXTS_AFTER_PAIRING=$(snapshot_texts "$MAC_WS")
grep -q 'paired with bob' <<<"$MAC_TEXTS_AFTER_PAIRING" ||
  { printf '%s\n' "$MAC_TEXTS_AFTER_PAIRING"; fail 'macOS did not pair'; }

WEB_SYNC=$(fmtk_exec "$WEB_WS" fmt_client_tool '{"toolName":"sync","arguments":{}}')
assert_ok "$WEB_SYNC" 'web sync'
MAC_SYNC=$(fmtk_exec "$MAC_WS" fmt_client_tool '{"toolName":"sync","arguments":{}}')
assert_ok "$MAC_SYNC" 'macOS sync'

log 'Validating paired/synced state'

check_errors() {
  local target=$1 label=$2 output
  output=$(fmtk_exec "$target" get_app_errors)
  assert_ok "$output" "$label errors"
  printf '%s\n' "$output" > "$ARTIFACTS/$label-errors.json"
  if python3 -c 'import json,sys; x=json.loads(sys.argv[1]); errs=x["data"].get("errors",[]); assert not errs, errs' \
    "$output" 2>/dev/null; then
    log "$label has no captured app errors"
  else
    cat "$ARTIFACTS/$label-errors.json"
    fail "$label app errors found"
  fi
}

log 'Checking runtime errors'
check_errors "$MAC_WS" macos
check_errors "$WEB_WS" web

log 'E2E harness completed successfully'
