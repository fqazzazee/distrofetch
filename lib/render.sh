#!/usr/bin/env bash
# Output layer: the palette, the falling-glyph animation, and the report itself.
#
# Kept separate from detect.sh so the probes can be tested without a terminal, and so
# the animation can be skipped entirely without touching detection logic.
#
# Sourced by bin/distrofetch.

# shellcheck shell=bash

# Populated by render_init. Empty strings when color is off, which makes every
# printf below work unchanged in a pipe.
DF_DIM=""
DF_GREEN=""
DF_BRIGHT=""
DF_BOLD=""
DF_RESET=""

# Glyphs for the rain. Half-width katakana is what the film used; ASCII digits fill in
# so the effect still reads on a terminal without a CJK font.
readonly DF_GLYPHS='ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉ0123456789'

render_init() {
  local color="$1"
  if [ "$color" -eq 1 ]; then
    DF_DIM=$'\033[38;5;22m'
    DF_GREEN=$'\033[38;5;40m'
    DF_BRIGHT=$'\033[38;5;120m'
    DF_BOLD=$'\033[1m'
    DF_RESET=$'\033[0m'
  else
    DF_DIM="" DF_GREEN="" DF_BRIGHT="" DF_BOLD="" DF_RESET=""
  fi
}

# One random glyph from DF_GLYPHS.
_glyph() {
  local n=${#DF_GLYPHS}
  printf '%s' "${DF_GLYPHS:$((RANDOM % n)):1}"
}

# Falling glyphs for `duration` seconds, then clear. Only ever called when stdout is a
# terminal, so the cursor manipulation below is safe.
render_rain() {
  local duration="$1"
  local cols rows deadline col
  cols="$(tput cols 2>/dev/null || printf '80')"
  rows="$(tput lines 2>/dev/null || printf '24')"
  deadline=$((SECONDS + duration))

  printf '\033[?25l' # hide cursor
  # Restore the terminal even if the user hits Ctrl-C mid-animation.
  trap 'printf "\033[?25h\033[0m\n"; exit 130' INT TERM

  while [ "$SECONDS" -lt "$deadline" ]; do
    col=$((RANDOM % cols + 1))
    printf '\033[%s;%sH%s%s' "$((RANDOM % rows + 1))" "$col" "$DF_GREEN" "$(_glyph)"
    printf '\033[%s;%sH%s%s' "$((RANDOM % rows + 1))" "$((RANDOM % cols + 1))" "$DF_DIM" "$(_glyph)"
    sleep 0.02
  done

  trap - INT TERM
  printf '%s\033[?25h\033[2J\033[H' "$DF_RESET"
}

# One "key: value" line, padded so the values line up.
_field() {
  printf '%s%-10s%s %s%s%s\n' "$DF_GREEN" "$1" "$DF_RESET" "$DF_BRIGHT" "$2" "$DF_RESET"
}

render_report() {
  local host
  host="$(detect_host)"

  printf '%s%s%s@%s%s%s\n' "$DF_BOLD$DF_BRIGHT" "${USER:-$(id -un)}" "$DF_RESET" \
    "$DF_BOLD$DF_BRIGHT" "$host" "$DF_RESET"
  printf '%s%s%s\n' "$DF_DIM" '────────────────────────────────' "$DF_RESET"

  _field 'OS:' "$(detect_os)"
  _field 'Kernel:' "$(detect_kernel)"
  _field 'Arch:' "$(detect_arch)"
  _field 'Uptime:' "$(detect_uptime)"
  _field 'Packages:' "$(detect_packages)"
  _field 'Shell:' "$(detect_shell)"
  _field 'CPU:' "$(detect_cpu)"
  _field 'Memory:' "$(detect_memory)"
}
