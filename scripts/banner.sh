#!/usr/bin/env bash
# Regenerate the DF_BANNER rows in lib/render.sh.
#
# The banner is five rows of block characters that have to stay column-aligned. Laying
# them out by hand means counting spaces across eleven letters and getting it wrong;
# this composes them from a per-letter table instead and prints the rows ready to
# paste. Run it if you change the wordmark.
#
#   scripts/banner.sh

set -euo pipefail

# Each letter is five rows of four columns, separated by |.
declare -A GLYPHS=(
  [D]="███ |█  █|█  █|█  █|███ "
  [I]="████| ██ | ██ | ██ |████"
  [S]="████|█   |████|   █|████"
  [T]="████| ██ | ██ | ██ | ██ "
  [R]="███ |█  █|███ |█ █ |█  █"
  [O]="████|█  █|█  █|█  █|████"
  [F]="████|█   |███ |█   |█   "
  [E]="████|█   |███ |█   |████"
  [C]="████|█   |█   |█   |████"
  [H]="█  █|█  █|████|█  █|█  █"
)

WORD="${1:-DISTROFETCH}"

for row in 0 1 2 3 4; do
  line=""
  for ((i = 0; i < ${#WORD}; i++)); do
    ch="${WORD:i:1}"
    if [ -z "${GLYPHS[$ch]:-}" ]; then
      printf 'banner.sh: no glyph for %s\n' "$ch" >&2
      exit 1
    fi
    IFS='|' read -r -a parts <<<"${GLYPHS[$ch]}"
    [ -z "$line" ] || line+=" "
    line+="${parts[$row]}"
  done
  printf "  '%s'\n" "$line"
  width="${#line}"
done

printf '\n# DF_BANNER_WIDTH must be %s\n' "$width"
