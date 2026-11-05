#!/usr/bin/env bash
# fetch_hf.sh — curl-based Hugging Face fetch into hub-cache layout.
# Usage: fetch_hf.sh <org/name> <dest-root>
# Creates <dest-root>/models--<org>--<name>/snapshots/main/ with config,
# tokenizer and weight files, then writes a textual sha256 receipt.
# Never runs interpreters from the download dir; files are data only.
set -euo pipefail

repo="${1:?usage: fetch_hf.sh <org/name> <dest-root>}"
root="${2:?usage: fetch_hf.sh <org/name> <dest-root>}"
org="${repo%%/*}"; name="${repo##*/}"
dest="$root/models--${org}--${name}/snapshots/main"
base="https://huggingface.co/$repo/resolve/main"
mkdir -p "$dest"

fetch() { # fetch <file> [optional]
  local f="$1" opt="${2:-}"
  if curl -L -f --retry 3 --retry-all-errors -sS -o "$dest/$f" "$base/$f"; then
    echo "fetched $f"
  elif [ -n "$opt" ]; then
    echo "optional-missing $f"
  else
    echo "FAILED $f" >&2; return 1
  fi
}

fetch config.json
fetch generation_config.json optional
fetch tokenizer.json optional
fetch tokenizer_config.json optional
fetch vocab.json optional
fetch merges.txt optional
fetch special_tokens_map.json optional

shards=""
if fetch model.safetensors.index.json optional; then
  shards="$(python3 -I -c '
import json,sys
idx=json.load(open(sys.argv[1]))
seen=[]
for f in idx["weight_map"].values():
    if f not in seen: seen.append(f)
print("\n".join(seen))' "$dest/model.safetensors.index.json")"
fi
if [ -n "$shards" ]; then
  while IFS= read -r s; do fetch "$s"; done <<< "$shards"
else
  fetch model.safetensors
fi

( cd "$dest" && shasum -a 256 ./* | sort -k2 ) > "$dest/../../FETCH-RECEIPT.sha256"
echo "receipt: $dest/../../FETCH-RECEIPT.sha256"
