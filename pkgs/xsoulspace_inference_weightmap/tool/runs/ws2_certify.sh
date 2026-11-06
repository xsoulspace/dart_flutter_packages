#!/bin/sh
# ws2_certify.sh - thin glue wrapper: exec the stdlib-only python certifier
# in isolated mode (-I: no cwd/site imports; probe scratch law). All
# arguments pass through verbatim:
#   --rust-digest JSON --py-digest JSON --tolerance JSON --out JSONL
# The NAMED error vocabulary and exit codes live in ws2_certify.py.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 -I "$script_dir/ws2_certify.py" "$@"
