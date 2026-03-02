# Root justfile – run `just` from repo root
# Install: brew install just  (or cargo install just)
# `just` or `just pub-get`: flutter pub get in all pkgs with pubspec.yaml

default:
    just pub-get

pub-get:
    #!/usr/bin/env bash
    for d in pkgs/*/; do
      if [ -d "$d" ] && [ -f "$d/pubspec.yaml" ]; then
        (cd "$d" && flutter pub get)
      fi
    done
