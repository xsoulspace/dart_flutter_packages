#!/usr/bin/env bash
# wm_pyenv.sh — resolve the MLX venv python for the Qwen3.5 boundary scripts.
#
# The venv lives at $HOME/.local/share/wm-mlx (override: WM_MLX_VENV_DIR).
# This script RESOLVES, it never CREATES: another process owns installation.
#
# Usage:
#   WM_PY=$(tool/nursery/wm_pyenv.sh) || exit $?
#   "$WM_PY" tool/nursery/wm_qwen35_generate.py ...
#
# Exit codes (NAMED, never silent):
#   0  resolved; the python path is printed on stdout (single line)
#   2  VENV_MISSING — the venv python is not present or not executable;
#      stderr carries the exact uv commands to create it
set -u

VENV_DIR="${WM_MLX_VENV_DIR:-$HOME/.local/share/wm-mlx}"
PY="$VENV_DIR/bin/python"

if [ -x "$PY" ]; then
  printf '%s\n' "$PY"
  exit 0
fi

cat >&2 <<EOF
VENV_MISSING: no executable MLX venv python at $PY
This script never creates the venv (another process owns installation).
To create it:
  uv venv "$HOME/.local/share/wm-mlx" --python 3.12
  uv pip install --python "$HOME/.local/share/wm-mlx/bin/python" mlx-lm
EOF
exit 2
