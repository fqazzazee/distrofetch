#!/usr/bin/env bash
# Output layer: the palette, the falling-glyph animation, the banner, and the report.
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
DF_HEAD=""

# Five greens, dim to bright. The rain fades a stream through them as it falls and the
# banner uses them top to bottom, so the two share one visual vocabulary.
DF_SHADES=("" "" "" "" "")

# Set from --no-art. Off means the plain label/value report with no box and no banner,
# which is what anything parsing this output wants.
DF_ART=1

# Half-width katakana is what the film used, and half-width matters: every glyph has to
# occupy exactly one cell or the columns shear.
#
# ${var:i:1} slices characters only in a UTF-8 locale. Under LC_ALL=C bash slices bytes
# instead and each katakana glyph comes apart into three of them, so render_init falls
# back to the ASCII set rather than printing mojibake.
readonly DF_GLYPHS_UTF8='ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉ0123456789'
readonly DF_GLYPHS_ASCII='0123456789<>[]{}/\|=+*-_:;.$#%&@'
DF_GLYPHS="$DF_GLYPHS_ASCII"
DF_GLYPH_N=${#DF_GLYPHS_ASCII}

# Rendered by scripts/banner.sh rather than counted by hand; every row is 54 columns.
DF_BANNER=(
  '███  ████ ████ ████ ███  ████ ████ ████ ████ ████ █  █'
  '█  █  ██  █     ██  █  █ █  █ █    █     ██  █    █  █'
  '█  █  ██  ████  ██  ███  █  █ ███  ███   ██  █    ████'
  '█  █  ██     █  ██  █ █  █  █ █    █     ██  █    █  █'
  '███  ████ ████  ██  █  █ ████ █    ████  ██  ████ █  █'
)
readonly DF_BANNER
# A constant, not ${#DF_BANNER[0]} — the rows are multibyte and ${#} counts bytes
# outside a UTF-8 locale, which would throw off every width calculation below.
readonly DF_BANNER_WIDTH=54

# Field labels and the values behind them, filled by _df_collect. Kept as parallel
# arrays because the reveal animation redraws the same values many times and probing
# the machine once per frame would be absurd.
DF_LABELS=()
DF_VALUES=()

# Scratch output for the helpers that would otherwise need a subshell. Command
# substitution forks, and these run inside animation loops.
_df_out=""

render_init() {
  local color="$1" art="${2:-1}"

  if [ "$color" -eq 1 ]; then
    DF_DIM=$'\033[38;5;22m'
    DF_GREEN=$'\033[38;5;40m'
    DF_BRIGHT=$'\033[38;5;120m'
    DF_BOLD=$'\033[1m'
    DF_RESET=$'\033[0m'
    DF_HEAD=$'\033[1;38;5;231m'
    DF_SHADES=(
      $'\033[38;5;22m' $'\033[38;5;28m' $'\033[38;5;34m'
      $'\033[38;5;40m' $'\033[38;5;46m'
    )
  else
    DF_DIM="" DF_GREEN="" DF_BRIGHT="" DF_BOLD="" DF_RESET="" DF_HEAD=""
    DF_SHADES=("" "" "" "" "")
  fi

  DF_ART="$art"

  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8* | *utf8* | *UTF8* | *utf-8*)
      DF_GLYPHS="$DF_GLYPHS_UTF8"
      DF_GLYPH_N=${#DF_GLYPHS_UTF8}
      ;;
    *)
      DF_GLYPHS="$DF_GLYPHS_ASCII"
      DF_GLYPH_N=${#DF_GLYPHS_ASCII}
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Terminal geometry
# ---------------------------------------------------------------------------

# COLUMNS and LINES win over tput when they are set and numeric, the way less(1) and
# ls(1) treat them. Bash maintains them in interactive shells, terminal multiplexers
# and CI harnesses export them, and honouring them is what makes the narrow-terminal
# fallback testable without allocating a pty.
_df_geometry() {
  local env_value="$1" cap="$2" fallback="$3"
  case "$env_value" in
    '' | *[!0-9]*) ;;
    *)
      if [ "$env_value" -gt 0 ]; then
        printf '%s' "$env_value"
        return
      fi
      ;;
  esac
  tput "$cap" 2>/dev/null || printf '%s' "$fallback"
}

_df_cols() { _df_geometry "${COLUMNS:-}" cols 80; }
_df_rows() { _df_geometry "${LINES:-}" lines 24; }

# ---------------------------------------------------------------------------
# The rain
# ---------------------------------------------------------------------------

# Falling glyph streams for `duration` seconds. Only ever called when stdout is a
# terminal, so the cursor manipulation below is safe.
#
# Each column is one stream with its own position, speed, and trail length. A frame
# touches five cells per moving column — the white head, three fading cells behind it,
# and one erase at the end of the trail — rather than repainting the grid, which is
# what keeps this affordable in Bash. The trail cells get a fresh random glyph each
# time they are touched, which is where the shimmer comes from.
render_rain() {
  local duration="$1"
  local cols rows deadline frame=0 c h buf
  local -a head speed trail

  cols="$(_df_cols)"
  rows="$(_df_rows)"

  for ((c = 0; c < cols; c++)); do
    # Negative starts stagger the streams above the top edge so they do not all
    # arrive in the first frame.
    head[c]=$((-(RANDOM % rows)))
    speed[c]=$((RANDOM % 3 + 1))
    trail[c]=$((RANDOM % 10 + 12))
  done

  # The alternate screen buffer means the animation never touches the user's
  # scrollback: the terminal comes back exactly as it was, and the report then prints
  # into the normal buffer where it stays.
  printf '\033[?1049h\033[?25l\033[2J'
  trap 'printf "\033[?25h\033[?1049l\033[0m"; exit 130' INT TERM

  deadline=$((SECONDS + duration))
  while [ "$SECONDS" -lt "$deadline" ]; do
    buf=""
    for ((c = 0; c < cols; c++)); do
      if [ $((frame % speed[c])) -ne 0 ]; then
        continue
      fi

      h=$((head[c] + 1))
      head[c]=$h

      _df_cell "$h" "$c" "$DF_HEAD"
      buf+="$_df_out"
      _df_cell $((h - 1)) "$c" "${DF_SHADES[4]}"
      buf+="$_df_out"
      _df_cell $((h - 3)) "$c" "${DF_SHADES[3]}"
      buf+="$_df_out"
      _df_cell $((h - 6)) "$c" "${DF_SHADES[2]}"
      buf+="$_df_out"
      _df_cell $((h - 10)) "$c" "${DF_SHADES[1]}"
      buf+="$_df_out"

      _df_erase $((h - trail[c])) "$c"
      buf+="$_df_out"

      if [ $((h - trail[c])) -gt "$rows" ]; then
        head[c]=$((-(RANDOM % 12)))
        speed[c]=$((RANDOM % 3 + 1))
        trail[c]=$((RANDOM % 10 + 12))
      fi
    done

    printf '%s' "$buf"
    frame=$((frame + 1))
    sleep 0.045
  done

  trap - INT TERM
  printf '%s\033[?25h\033[?1049l' "$DF_RESET"
}

# One glyph at 1-based row/0-based column, or nothing at all when the row is off
# screen. Assigns to _df_out instead of printing: this runs cols*5 times per frame.
_df_cell() {
  local row="$1" col="$2" color="$3"
  _df_out=""
  if [ "$row" -lt 1 ]; then
    return
  fi
  _df_out=$'\033['"$row"';'"$((col + 1))"'H'"$color""${DF_GLYPHS:$((RANDOM % DF_GLYPH_N)):1}"
}

_df_erase() {
  local row="$1" col="$2"
  _df_out=""
  if [ "$row" -lt 1 ]; then
    return
  fi
  _df_out=$'\033['"$row"';'"$((col + 1))"'H '
}

# ---------------------------------------------------------------------------
# The report
# ---------------------------------------------------------------------------

# Probe once. Everything downstream reads these arrays.
_df_collect() {
  DF_LABELS=('OS:' 'Kernel:' 'Arch:' 'Uptime:' 'Packages:' 'Shell:' 'CPU:' 'Memory:')
  DF_VALUES=(
    "$(detect_os)" "$(detect_kernel)" "$(detect_arch)" "$(detect_uptime)"
    "$(detect_packages)" "$(detect_shell)" "$(detect_cpu)" "$(detect_memory)"
  )
}

# `keep` leading characters of src, the rest replaced by random glyphs. Spaces survive
# so the shape of the value is visible before the value is.
_df_scramble() {
  local src="$1" keep="$2" i ch out=""
  for ((i = 0; i < ${#src}; i++)); do
    ch="${src:i:1}"
    if [ "$i" -lt "$keep" ] || [ "$ch" = ' ' ]; then
      out+="$ch"
    else
      out+="${DF_GLYPHS:$((RANDOM % DF_GLYPH_N)):1}"
    fi
  done
  _df_out="$out"
}

# `n` copies of a single-column character, built by substitution so the count is exact
# regardless of how many bytes the character takes.
_df_repeat() {
  local n="$1" ch="$2"
  _df_out=""
  if [ "$n" -lt 1 ]; then
    return
  fi
  printf -v _df_out '%*s' "$n" ''
  _df_out="${_df_out// /$ch}"
}

# The width of the widest thing that has to fit inside the box.
_df_inner_width() {
  local header="$1" i plain w="$DF_BANNER_WIDTH"
  if [ "${#header}" -gt "$w" ]; then
    w="${#header}"
  fi
  for i in "${!DF_LABELS[@]}"; do
    printf -v plain '%-10s %s' "${DF_LABELS[$i]}" "${DF_VALUES[$i]}"
    if [ "${#plain}" -gt "$w" ]; then
      w="${#plain}"
    fi
  done
  printf '%s' "$w"
}

# One boxed line: a left border, `text` padded to `inner` visible columns, a right
# border. `width` is passed separately because text carries color escapes, and ${#}
# would count those.
_df_boxed() {
  local text="$1" width="$2" inner="$3"
  local pad=$((inner - width))
  if [ "$pad" -lt 0 ]; then
    pad=0
  fi
  printf '%s│%s %s%*s %s│%s\n' \
    "$DF_DIM" "$DF_RESET" "$text" "$pad" '' "$DF_DIM" "$DF_RESET"
}

_df_banner() {
  local inner="$1" i indent lead
  indent=$(((inner - DF_BANNER_WIDTH) / 2))
  _df_repeat "$indent" ' '
  lead="$_df_out"
  for i in "${!DF_BANNER[@]}"; do
    # The visible width is the indent plus the wordmark, not inner — _df_boxed pads
    # the remainder, and claiming inner here leaves the right edge short by exactly
    # the centring offset.
    _df_boxed "${DF_SHADES[$i]}${lead}${DF_BANNER[$i]}${DF_RESET}" \
      $((indent + DF_BANNER_WIDTH)) "$inner"
  done
}

# The eight field lines, with values revealed up to `keep` characters. A negative keep
# means no scrambling at all — the final frame, and the only frame in static output.
_df_fields() {
  local inner="$1" keep="$2" i value plain colored
  for i in "${!DF_LABELS[@]}"; do
    value="${DF_VALUES[$i]}"
    if [ "$keep" -ge 0 ]; then
      _df_scramble "$value" "$keep"
      value="$_df_out"
    fi
    # The plain copy exists only to be measured — the colored one is full of escapes
    # that ${#} would count as visible columns.
    printf -v plain '%-10s %s' "${DF_LABELS[$i]}" "$value"

    if [ "$DF_ART" -eq 1 ]; then
      # printf -v rather than $( ): this runs eight times per animation frame, and a
      # fork per line per frame is the difference between smooth and stuttering.
      printf -v colored '%s%-10s%s %s%s%s' \
        "$DF_GREEN" "${DF_LABELS[$i]}" "$DF_RESET" "$DF_BRIGHT" "$value" "$DF_RESET"
      _df_boxed "$colored" "${#plain}" "$inner"
    else
      printf '%s%-10s%s %s%s%s\n' \
        "$DF_GREEN" "${DF_LABELS[$i]}" "$DF_RESET" "$DF_BRIGHT" "$value" "$DF_RESET"
    fi
  done
}

# animate=1 reveals the values out of noise. Only meaningful on a terminal, since it
# redraws in place with cursor movement.
render_report() {
  local animate="${1:-0}"
  local header inner rule cols keep longest i

  _df_collect
  header="${USER:-$(id -un)}@$(detect_host)"

  # Art needs a terminal wide enough for the box. Falling back to the plain report is
  # better than wrapping every line at 61 columns.
  inner="$(_df_inner_width "$header")"
  if [ "$DF_ART" -eq 1 ]; then
    cols="$(_df_cols)"
    if [ "$cols" -lt $((inner + 4)) ]; then
      DF_ART=0
    fi
  fi

  if [ "$DF_ART" -eq 1 ]; then
    _df_repeat $((inner + 2)) '─'
    rule="$_df_out"
    printf '%s┌%s┐%s\n' "$DF_DIM" "$rule" "$DF_RESET"
    if [ "$animate" -eq 1 ]; then
      # Rows arrive one at a time, so the banner assembles rather than appearing.
      local -a rows=()
      mapfile -t rows < <(_df_banner "$inner")
      for i in "${!rows[@]}"; do
        printf '%s\n' "${rows[$i]}"
        sleep 0.06
      done
    else
      _df_banner "$inner"
    fi
    _df_boxed "$DF_BOLD$DF_BRIGHT$header$DF_RESET" "${#header}" "$inner"
    printf '%s├%s┤%s\n' "$DF_DIM" "$rule" "$DF_RESET"
  else
    printf '%s%s%s@%s%s%s\n' "$DF_BOLD$DF_BRIGHT" "${USER:-$(id -un)}" "$DF_RESET" \
      "$DF_BOLD$DF_BRIGHT" "$(detect_host)" "$DF_RESET"
    printf '%s%s%s\n' "$DF_DIM" '────────────────────────────────' "$DF_RESET"
  fi

  if [ "$animate" -eq 1 ]; then
    longest=0
    for i in "${!DF_VALUES[@]}"; do
      if [ "${#DF_VALUES[$i]}" -gt "$longest" ]; then
        longest="${#DF_VALUES[$i]}"
      fi
    done
    for ((keep = 0; keep < longest; keep += 2)); do
      _df_fields "$inner" "$keep"
      # Back to the top of the block for the next frame.
      printf '\033[%sA' "${#DF_LABELS[@]}"
      sleep 0.03
    done
  fi

  _df_fields "$inner" -1

  if [ "$DF_ART" -eq 1 ]; then
    printf '%s└%s┘%s\n' "$DF_DIM" "$rule" "$DF_RESET"
  fi
}
