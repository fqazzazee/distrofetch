#!/usr/bin/env bash
# Output layer: the palette, the falling-glyph animation, and the dashboard.
#
# Kept separate from detect.sh so the probes can be tested without a terminal, and so
# the animation can be skipped entirely without touching detection logic.
#
# The dashboard is built from panels. A panel is an array of lines, every one padded to
# the same visible width, so panels can be set side by side by concatenating them line
# for line. Width is tracked separately from the strings because the strings carry ANSI
# escapes, and because ${#} counts bytes rather than characters outside a UTF-8 locale
# — every border character here is multibyte. The rule that follows from both: never
# measure a rendered line, only the plain text that went into it.
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
DF_WARN=""
DF_ALERT=""

# Five greens, dim to bright. The rain fades a stream through them as it falls.
DF_SHADES=("" "" "" "" "")

# Set from --no-art. Off means a flat list of "Label: value" lines with no panels and
# no logo, which is what anything parsing this output wants.
DF_ART=1

# Set from --logo / --no-logo. A name selects a specific logo regardless of the distro.
DF_LOGO=auto

# Set from --no-clear. The dashboard is meant to be looked at whole, so by default it
# starts from a clean screen; anything scripting against this uses --no-art anyway.
DF_CLEAR=1

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

# Scratch output for the helpers that would otherwise need a subshell. Command
# substitution forks, and some of these run inside the animation loop.
_df_out=""

# Field separator for panel rows. A literal unit separator, because values legitimately
# contain every printable character — DIMM records are pipe-delimited, paths contain
# colons, and CPU model strings contain both.
readonly DF_FS=$'\037'

render_init() {
  local color="$1" art="${2:-1}"

  if [ "$color" -eq 1 ]; then
    DF_DIM=$'\033[38;5;22m'
    DF_GREEN=$'\033[38;5;40m'
    DF_BRIGHT=$'\033[38;5;120m'
    DF_BOLD=$'\033[1m'
    DF_RESET=$'\033[0m'
    DF_HEAD=$'\033[1;38;5;231m'
    DF_WARN=$'\033[38;5;214m'
    DF_ALERT=$'\033[1;38;5;196m'
    DF_SHADES=(
      $'\033[38;5;22m' $'\033[38;5;28m' $'\033[38;5;34m'
      $'\033[38;5;40m' $'\033[38;5;46m'
    )
  else
    DF_DIM="" DF_GREEN="" DF_BRIGHT="" DF_BOLD="" DF_RESET="" DF_HEAD=""
    DF_WARN="" DF_ALERT=""
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
  # scrollback: the terminal comes back exactly as it was, and the dashboard then
  # prints into the normal buffer where it stays.
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
# Small string helpers
# ---------------------------------------------------------------------------

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

# Truncate to `n` visible columns, marking the cut with an ASCII ellipsis. The marker
# is "..." rather than U+2026 so that a truncated line stays measurable with ${#} in
# any locale.
_df_clip() {
  local s="$1" n="$2"
  if [ "$n" -lt 4 ]; then
    _df_out="${s:0:$n}"
    return
  fi
  if [ "${#s}" -le "$n" ]; then
    _df_out="$s"
  else
    _df_out="${s:0:$((n - 3))}..."
  fi
}

# ---------------------------------------------------------------------------
# Panels
# ---------------------------------------------------------------------------
#
# A panel is an array of equal-width lines:
#
#   ┌─ PROCESSOR ──────────────────┐
#   │ Model     13th Gen Intel ... │
#   └──────────────────────────────┘
#
# Rows arrive as key<FS>value<FS>level strings. level is '', 'warn', or 'alert' and
# only tints the value; the layout never changes with it, so a coloured line and a
# plain one still occupy the same columns.

# _df_panel OUTVAR TITLE WIDTH KEYW ARTVAR ROW...
#
# ARTVAR names an array of ASCII art lines to run down the left of the panel's interior,
# or `-` for none. The art is measured with ${#} and so must be ASCII — see the header
# of this file. Content is indented past it and the usable width shrinks to match, so a
# panel with art and one without still close at the same column.
_df_panel() {
  local -n _panel_out="$1"
  local title="$2" width="$3" keyw="$4" art_name="$5"
  shift 5

  local inner=$((width - 4))
  local row key value level plain pad rule title_rule tint
  local -a art=()
  local art_w=0 art_i=0 lead line

  if [ "$art_name" != '-' ]; then
    local -n _art_src="$art_name"
    art=("${_art_src[@]}")
    for line in "${art[@]}"; do
      if [ "${#line}" -gt "$art_w" ]; then
        art_w="${#line}"
      fi
    done
    # Two spaces between art and content, so the gutter reads as deliberate.
    [ "$art_w" -gt 0 ] && inner=$((inner - art_w - 2))
  fi

  _panel_out=()

  # ┌─ TITLE ──…──┐ — the fixed part is "┌─ " plus " " plus "┐", five columns, so the
  # filler is width - 5 - len(title). Getting this off by one shortens only the top
  # border, which reads as a rendering glitch rather than as arithmetic.
  _df_repeat $((width - 5 - ${#title})) '─'
  title_rule="$_df_out"
  _panel_out+=("${DF_DIM}┌─ ${DF_RESET}${DF_BOLD}${DF_BRIGHT}${title}${DF_RESET}${DF_DIM} ${title_rule}┐${DF_RESET}")

  for row in "$@"; do
    IFS="$DF_FS" read -r key value level <<<"$row"

    case "$level" in
      warn) tint="$DF_WARN" ;;
      alert) tint="$DF_ALERT" ;;
      *) tint="$DF_BRIGHT" ;;
    esac

    # The art column, padded to its own width, or blank once the art runs out.
    lead=""
    if [ "$art_w" -gt 0 ]; then
      line=""
      if [ "$art_i" -lt "${#art[@]}" ]; then
        line="${art[$art_i]}"
      fi
      printf -v lead '%s%-*s%s  ' "$DF_GREEN" "$art_w" "$line" "$DF_RESET"
      art_i=$((art_i + 1))
    fi

    if [ -z "$key" ]; then
      # A keyless row spans the full inner width — used for DIMM lines and notes.
      _df_clip "$value" "$inner"
      value="$_df_out"
      plain="$value"
      pad=$((inner - ${#plain}))
      [ "$pad" -lt 0 ] && pad=0
      _panel_out+=("${DF_DIM}│${DF_RESET} ${lead}${tint}${value}${DF_RESET}$(printf '%*s' "$pad" '') ${DF_DIM}│${DF_RESET}")
      continue
    fi

    _df_clip "$value" $((inner - keyw - 1))
    value="$_df_out"
    printf -v plain '%-*s %s' "$keyw" "$key" "$value"
    pad=$((inner - ${#plain}))
    [ "$pad" -lt 0 ] && pad=0
    _panel_out+=("${DF_DIM}│${DF_RESET} ${lead}${DF_GREEN}$(printf '%-*s' "$keyw" "$key")${DF_RESET} ${tint}${value}${DF_RESET}$(printf '%*s' "$pad" '') ${DF_DIM}│${DF_RESET}")
  done

  # Art taller than the row list keeps going: the logo is not worth truncating, and a
  # panel that swallows half its own artwork looks like a bug.
  while [ "$art_i" -lt "${#art[@]}" ]; do
    printf -v lead '%s%-*s%s  ' "$DF_GREEN" "$art_w" "${art[$art_i]}" "$DF_RESET"
    _df_blank_line "$inner"
    _panel_out+=("${DF_DIM}│${DF_RESET} ${lead}${_df_out} ${DF_DIM}│${DF_RESET}")
    art_i=$((art_i + 1))
  done

  _df_repeat $((width - 2)) '─'
  rule="$_df_out"
  _panel_out+=("${DF_DIM}└${rule}┘${DF_RESET}")
}

# A blank line of exactly `width` visible columns, for padding a short panel up to the
# height of a taller neighbour.
_df_blank_line() {
  printf -v _df_out '%*s' "$1" ''
}

# An empty interior row of a panel: borders, nothing between them.
_df_panel_blank() {
  local width="$1"
  _df_blank_line $((width - 4))
  _df_out="${DF_DIM}│${DF_RESET} ${_df_out} ${DF_DIM}│${DF_RESET}"
}

# Grow the shorter of two panels with empty interior rows so both close on the same
# line. Two panels side by side with ragged bottoms read as a rendering fault rather
# than as one panel simply having less to say.
_df_equalize() {
  local a_name="$1" b_name="$2" aw="$3" bw="$4"
  local -n _a="$a_name"
  local -n _b="$b_name"
  local na=${#_a[@]} nb=${#_b[@]}

  if [ "$na" -lt "$nb" ]; then
    _df_pad_panel "$a_name" "$aw" "$nb"
  elif [ "$nb" -lt "$na" ]; then
    _df_pad_panel "$b_name" "$bw" "$na"
  fi
}

# Grow one panel to `target` lines by inserting blank interior rows above its footer.
# Split out rather than rebinding a nameref inside a branch: a second `local -n` on the
# same name in one scope is a trap, and this path is only exercised by whichever panel
# happens to be shorter.
_df_pad_panel() {
  # shellcheck disable=SC2178  # nameref to an array, not a string assignment
  local -n _p="$1"
  local width="$2" target="$3"
  local n=${#_p[@]}

  if [ "$n" -ge "$target" ] || [ "$n" -lt 2 ]; then
    return 0
  fi

  local -a body=("${_p[@]:0:n-1}")
  local footer="${_p[n - 1]}"
  _df_panel_blank "$width"
  while [ "${#body[@]}" -lt $((target - 1)) ]; do
    body+=("$_df_out")
  done
  _p=("${body[@]}" "$footer")
}

# ---------------------------------------------------------------------------
# Data collection
# ---------------------------------------------------------------------------

DF_D_ID=""
DF_D_VERSION=""

# Device enumerations, read once. The dashboard is built more than once when it has to
# be condensed to fit the terminal, and re-walking sysfs for each attempt would triple
# the syscalls for output that is thrown away.
DF_GPUS=()
DF_NICS=()
DF_USB=()
DF_TBT=()
DF_TBT_DEVS=()
DF_DISKS=()

# How much detail the panels carry: 2 full, 1 compact, 0 minimal. Lowered until the
# dashboard fits the terminal — see _df_fit_detail.
DF_DETAIL=2

_df_collect_devices() {
  mapfile -t DF_GPUS < <(detect_gpus)
  mapfile -t DF_NICS < <(detect_nics)
  mapfile -t DF_USB < <(detect_usb_buses)
  mapfile -t DF_TBT < <(detect_thunderbolt)
  mapfile -t DF_TBT_DEVS < <(detect_thunderbolt_devices)
  mapfile -t DF_DISKS < <(detect_disks)
}
DF_LOGO_LINES=()
DF_LOGO_WIDTH=0

DF_CPU_LOGO_LINES=()

# The vendor logo for the processor panel. Same ASCII rule as the distro logos, and the
# same switch: --no-logo turns off all art, not just the distro column.
_df_load_cpu_logo() {
  local name line
  DF_CPU_LOGO_LINES=()
  [ "$DF_LOGO" != none ] || return 0

  name="$(hwdata_cpu_logo_name "$(detect_cpu_vendor)")"
  [ -r "$DISTROFETCH_CPU_LOGOS/$name.txt" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    DF_CPU_LOGO_LINES+=("$line")
  done <"$DISTROFETCH_CPU_LOGOS/$name.txt"
}

# Load the logo art. Logos are strictly ASCII so ${#} measures them correctly in any
# locale — the same reason the frame's width is computed rather than measured.
_df_load_logo() {
  local name line
  DF_LOGO_LINES=()
  DF_LOGO_WIDTH=0

  case "$DF_LOGO" in
    none) return 0 ;;
    auto) name="$(hwdata_logo_name "$DF_D_ID" "$(detect_distro_like)")" ;;
    *) name="$DF_LOGO" ;;
  esac

  if [ ! -r "$DISTROFETCH_LOGOS/$name.txt" ]; then
    # An explicit --logo that does not exist is a usage error the caller already
    # reported; auto never lands here because hwdata_logo_name falls back to tux.
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    DF_LOGO_LINES+=("$line")
    # Not `[ ... ] && DF_LOGO_WIDTH=...`: that leaves the loop, and so the function,
    # returning 1 on the last short line, which under set -e kills the caller.
    if [ "${#line}" -gt "$DF_LOGO_WIDTH" ]; then
      DF_LOGO_WIDTH="${#line}"
    fi
  done <"$DISTROFETCH_LOGOS/$name.txt"
}

# ---------------------------------------------------------------------------
# The dashboard
# ---------------------------------------------------------------------------

# Whether a panel has nothing to report — its only content row is a "none present"
# style answer. At the tightest density these are dropped entirely: a panel whose one
# row says "no Thunderbolt controller" costs three lines to say nothing, and on a
# container that is three of them.
_df_panel_is_empty() {
  # shellcheck disable=SC2178  # nameref to an array, not a string assignment
  local -n _p="$1"
  local n="${#_p[@]}" i

  # Two borders and at least one content row. Every content row has to be a "none"
  # answer, not just the first — the peripherals panel says it twice, once for USB and
  # once for Thunderbolt, and checking only row one left it on screen.
  [ "$n" -ge 3 ] || return 1
  for ((i = 1; i < n - 1; i++)); do
    case "${_p[$i]}" in
      *'none present'* | *'none with a hardware device'* | *'no host controllers'* | \
        *'no Thunderbolt or USB4 controller'* | *'no disks'* | *'Disks'*'none'*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# The dashboard, sized to the terminal.
#
# Built at full detail and rebuilt at lower detail until it fits the height. Rebuilding
# is cheap: every probe and every sysfs walk is cached, and only the row formatting is
# redone. The order of attempts is strictly decreasing in information, so the result is
# always the most complete layout that fits.
render_dashboard() {
  local cols width logo_w body_w rows avail attempt paired half half2 height
  # shellcheck disable=SC2034  # filled through namerefs by the _df_build_* helpers
  local -a p_system p_distro p_cpu p_mem p_machine p_gpu p_net p_periph p_storage
  # shellcheck disable=SC2034  # filled through a nameref by _df_which_panels
  local -a shown=()
  local dense=0

  DF_D_ID="$(detect_distro_id)"
  DF_D_VERSION="$(detect_distro_version)"
  _df_collect_devices

  cols="$(_df_cols)"
  # Capped because panels stretched across an ultrawide terminal are unreadable: the
  # eye has to travel the whole line to pair a key with its value.
  width=$((cols - 2))
  [ "$width" -gt 130 ] && width=130

  if [ "$width" -lt 56 ]; then
    # Nothing fits. The flat list is the honest fallback.
    render_plain
    return
  fi

  _df_load_logo
  _df_load_cpu_logo
  logo_w="$DF_LOGO_WIDTH"
  body_w=$((width - logo_w - 1))
  # Below this the panels are narrower than their own content; drop the art instead.
  if [ "$body_w" -lt 52 ]; then
    DF_LOGO_LINES=()
    logo_w=0
    body_w="$width"
  fi

  # One line held back for the shell prompt that will land under this.
  rows="$(_df_rows)"
  avail=$((rows - 1))

  paired=0
  [ "$body_w" -ge 108 ] && paired=1
  half=$(((body_w - 1) / 2))
  half2=$((body_w - 1 - half))

  # detail:dense:drop-logo. Two columns of panels is a bigger loss of legibility than
  # dropping a row, so every detail level is tried stacked before anything is paired;
  # the logo goes last because it is the one thing here that is decoration.
  local saved_logo=("${DF_LOGO_LINES[@]}")
  local drop_logo
  for attempt in 2:0:0 1:0:0 0:0:0 1:1:0 0:1:0 0:1:1; do
    IFS=: read -r DF_DETAIL dense drop_logo <<<"$attempt"
    [ "$paired" -eq 1 ] || dense=0
    if [ "$drop_logo" -eq 1 ]; then
      DF_LOGO_LINES=()
      logo_w=0
      body_w="$width"
      half=$(((body_w - 1) / 2))
      half2=$((body_w - 1 - half))
    else
      DF_LOGO_LINES=("${saved_logo[@]}")
    fi

    # System and distribution share a row only when the body is wide enough for two
    # columns; at narrower widths they are full-width panels like everything else.
    if [ "$paired" -eq 1 ]; then
      _df_build_system p_system "$half"
      _df_build_distro p_distro "$half2"
    else
      _df_build_system p_system "$body_w"
      _df_build_distro p_distro "$body_w"
    fi

    # First pass at full width. This is what decides which panels have anything to
    # say, and that decision has to come before widths are assigned — dropping an
    # empty panel shifts every later one to the other side of the pairing, and a panel
    # built at full width sitting in a half-width slot overruns the frame.
    _df_build_cpu p_cpu "$body_w"
    _df_build_memory p_mem "$body_w"
    _df_build_storage p_storage "$body_w"
    _df_build_graphics p_gpu "$body_w"
    _df_build_network p_net "$body_w"
    _df_build_peripherals p_periph "$body_w"
    _df_build_machine p_machine "$body_w"

    _df_which_panels shown "$attempt"

    if [ "$dense" -eq 1 ]; then
      _df_rebuild_paired shown "$half" "$half2" "$body_w"
    fi
    height="$(_df_measure "$paired" "$dense" "$half" shown)"

    if [ "$height" -le "$avail" ]; then
      break
    fi
  done

  # Clearing is the last thing before drawing, so a failed run leaves the screen it
  # found intact. Only on a terminal: an escape in a pipe is exactly what the non-TTY
  # checks exist to prevent.
  if [ "$DF_CLEAR" -eq 1 ] && [ -t 1 ]; then
    printf '\033[H\033[2J'
  fi

  _df_header "$width"

  if [ "$paired" -eq 1 ]; then
    _df_equalize p_system p_distro "$half" "$half2"
    _df_logo_beside p_system p_distro "$logo_w" "$half" "$half2"
  else
    _df_logo_stack p_system "$logo_w" "$body_w"
    _df_indent_panel p_distro "$logo_w"
  fi
  _df_emit_body "$dense" "$logo_w" "$half" "$half2" shown
}

# Which panels survive this attempt. At the tightest densities a panel with nothing to
# report is dropped rather than printed as three lines of "none".
_df_which_panels() {
  local -n _shown="$1"
  local attempt="$2"
  local name
  _shown=()
  for name in p_cpu p_mem p_storage p_gpu p_net p_periph p_machine; do
    if [ "$DF_DETAIL" -eq 0 ] && _df_panel_is_empty "$name"; then
      continue
    fi
    _shown+=("$name")
  done
}

# Rebuild the panels that will sit in a pair at the width of their slot, left column
# first. An odd final panel keeps the full width, since it has the row to itself.
_df_rebuild_paired() {
  # shellcheck disable=SC2178  # nameref to an array, not a string assignment
  local -n _shown="$1"
  local half="$2" half2="$3" body_w="$4"
  local i n="${#_shown[@]}" w

  for ((i = 0; i < n; i++)); do
    if [ "$i" -eq $((n - 1)) ] && [ $((n % 2)) -eq 1 ]; then
      w="$body_w"
    elif [ $((i % 2)) -eq 0 ]; then
      w="$half"
    else
      w="$half2"
    fi
    _df_build_by_name "${_shown[$i]}" "$w"
  done
}

# Dispatch to the builder that owns a panel array. The mapping lives in one place so
# the fit loop can rebuild any panel at any width without knowing what it holds.
_df_build_by_name() {
  case "$1" in
    p_cpu) _df_build_cpu p_cpu "$2" ;;
    p_mem) _df_build_memory p_mem "$2" ;;
    p_storage) _df_build_storage p_storage "$2" ;;
    p_gpu) _df_build_graphics p_gpu "$2" ;;
    p_net) _df_build_network p_net "$2" ;;
    p_periph) _df_build_peripherals p_periph "$2" ;;
    p_machine) _df_build_machine p_machine "$2" ;;
  esac
}

# Height of a layout without rendering it.
_df_measure() {
  local is_paired="$1" dense="$2" half="$3"
  # shellcheck disable=SC2178  # nameref to an array, not a string assignment
  local -n _shown="$4"
  local -n _sys=p_system
  local -n _dist=p_distro
  local total=3 first name i
  # 3 = title line, rule, blank.

  if [ "$is_paired" -eq 1 ]; then
    first="${#_sys[@]}"
    [ "${#_dist[@]}" -gt "$first" ] && first="${#_dist[@]}"
  else
    first=$((${#_sys[@]} + ${#_dist[@]}))
  fi
  [ "${#DF_LOGO_LINES[@]}" -gt "$first" ] && first="${#DF_LOGO_LINES[@]}"
  total=$((total + first))

  if [ "$dense" -eq 1 ]; then
    i=0
    while [ "$i" -lt "${#_shown[@]}" ]; do
      total=$((total + $(_df_pair_height "${_shown[$i]}" "${_shown[$((i + 1))]:-}")))
      i=$((i + 2))
    done
  else
    for name in "${_shown[@]}"; do
      # shellcheck disable=SC2178  # nameref to an array, not a string assignment
      local -n _p="$name"
      total=$((total + ${#_p[@]}))
    done
  fi
  printf '%s' "$total"
}

_df_pair_height() {
  local -n _a="$1"
  local h="${#_a[@]}"
  if [ -n "$2" ]; then
    local -n _b="$2"
    [ "${#_b[@]}" -gt "$h" ] && h="${#_b[@]}"
  fi
  printf '%s' "$h"
}

# Emit the panels below the first row, stacked or two across.
_df_emit_body() {
  local dense="$1" logo_w="$2" half="$3" half2="$4"
  # shellcheck disable=SC2178  # nameref to an array, not a string assignment
  local -n _shown="$5"
  local i name a b

  if [ "$dense" -ne 1 ]; then
    for name in "${_shown[@]}"; do
      _df_indent_panel "$name" "$logo_w"
    done
    return 0
  fi

  i=0
  while [ "$i" -lt "${#_shown[@]}" ]; do
    a="${_shown[$i]}"
    b="${_shown[$((i + 1))]:-}"
    if [ -n "$b" ]; then
      _df_equalize "$a" "$b" "$half" "$half2"
      _df_indent_pair "$a" "$b" "$logo_w" "$half" "$half2"
    else
      _df_indent_panel "$a" "$logo_w"
    fi
    i=$((i + 2))
  done
}

# The top bar: wordmark on the left, user@host on the right, one rule under both.
_df_header() {
  local width="$1" host user left right pad
  user="${USER:-$(id -un)}"
  host="$(detect_host)"
  left="distrofetch $DISTROFETCH_VERSION"
  right="$user@$host"
  pad=$((width - ${#left} - ${#right}))
  [ "$pad" -lt 1 ] && pad=1

  printf '%s%s%s%*s%s%s%s\n' \
    "$DF_BOLD$DF_BRIGHT" "$left" "$DF_RESET" "$pad" '' \
    "$DF_BOLD$DF_BRIGHT" "$right" "$DF_RESET"
  _df_repeat "$width" '─'
  printf '%s%s%s\n\n' "$DF_DIM" "$_df_out" "$DF_RESET"
}

# Print the logo column beside two panels set side by side.
_df_logo_beside() {
  local -n _a="$1"
  local -n _b="$2"
  local logo_w="$3" aw="$4" bw="$5"
  local -a joined=()
  local i n=${#_a[@]} m=${#_b[@]} lline

  [ "$m" -gt "$n" ] && n="$m"
  for ((i = 0; i < n; i++)); do
    if [ "$i" -lt "${#_a[@]}" ]; then lline="${_a[$i]}"; else
      _df_blank_line "$aw"
      lline="$_df_out"
    fi
    if [ "$i" -lt "${#_b[@]}" ]; then
      joined+=("$lline ${_b[$i]}")
    else
      joined+=("$lline")
    fi
  done
  _df_emit_with_logo joined "$logo_w"
}

# Print the logo column beside one panel.
_df_logo_stack() {
  # shellcheck disable=SC2178  # nameref to an array, not a string assignment
  local -n _p="$1"
  local logo_w="$2"
  local -a joined=("${_p[@]}")
  _df_emit_with_logo joined "$logo_w"
}

# Zip the logo art into the left margin of an already-composed block of lines. The art
# is vertically centred against the block when the block is taller.
_df_emit_with_logo() {
  local -n _block="$1"
  local logo_w="$2"
  local n=${#_block[@]} l=${#DF_LOGO_LINES[@]}
  local i offset=0 art pad

  if [ "$logo_w" -eq 0 ] || [ "$l" -eq 0 ]; then
    for ((i = 0; i < n; i++)); do
      printf '%s\n' "${_block[$i]}"
    done
    return
  fi

  [ "$n" -gt "$l" ] && offset=$(((n - l) / 2))
  # A logo taller than the block extends the block rather than being cut off.
  [ "$l" -gt "$n" ] && n="$l"

  for ((i = 0; i < n; i++)); do
    art=""
    if [ "$i" -ge "$offset" ] && [ $((i - offset)) -lt "$l" ]; then
      art="${DF_LOGO_LINES[$((i - offset))]}"
    fi
    pad=$((logo_w - ${#art}))
    [ "$pad" -lt 0 ] && pad=0
    if [ "$i" -lt "${#_block[@]}" ]; then
      printf '%s%s%s%*s %s\n' "$DF_GREEN" "$art" "$DF_RESET" "$pad" '' "${_block[$i]}"
    else
      printf '%s%s%s\n' "$DF_GREEN" "$art" "$DF_RESET"
    fi
  done
}

# Indent a panel to sit under the logo column.
_df_indent_panel() {
  # shellcheck disable=SC2178  # nameref to an array, not a string assignment
  local -n _p="$1"
  local indent="$2" line lead
  # An indent of zero means there is no logo column at all. Printing "$lead $line"
  # anyway would prepend a space to every line and shift the panel one column right of
  # the ones drawn without an indent.
  if [ "$indent" -le 0 ]; then
    for line in "${_p[@]}"; do
      printf '%s\n' "$line"
    done
    return 0
  fi
  _df_blank_line "$indent"
  lead="$_df_out"
  for line in "${_p[@]}"; do
    printf '%s %s\n' "$lead" "$line"
  done
}

_df_indent_pair() {
  local -n _a="$1"
  local -n _b="$2"
  local indent="$3" aw="$4"
  local i n=${#_a[@]} m=${#_b[@]} lline lead sep
  if [ "$indent" -le 0 ]; then
    lead=""
    sep=""
  else
    _df_blank_line "$indent"
    lead="$_df_out"
    sep=" "
  fi

  [ "$m" -gt "$n" ] && n="$m"
  for ((i = 0; i < n; i++)); do
    if [ "$i" -lt "${#_a[@]}" ]; then lline="${_a[$i]}"; else
      _df_blank_line "$aw"
      lline="$_df_out"
    fi
    if [ "$i" -lt "${#_b[@]}" ]; then
      printf '%s%s%s %s\n' "$lead" "$sep" "$lline" "${_b[$i]}"
    else
      printf '%s%s%s\n' "$lead" "$sep" "$lline"
    fi
  done
}

# --- individual panels -----------------------------------------------------

_df_build_system() {
  local -n _out="$1"
  local w="$2"
  local -a rows=()
  rows+=("OS${DF_FS}$(detect_os)")
  rows+=("Kernel${DF_FS}$(detect_kernel)")
  [ "$DF_DETAIL" -ge 1 ] && rows+=("Arch${DF_FS}$(detect_arch)")
  rows+=("Uptime${DF_FS}$(detect_uptime)")
  [ "$DF_DETAIL" -ge 1 ] && rows+=("Shell${DF_FS}$(detect_shell)")
  rows+=("Packages${DF_FS}$(detect_packages)")
  _df_panel _out SYSTEM "$w" 9 - "${rows[@]}"
}

_df_build_distro() {
  local -n _out="$1"
  local w="$2"
  local released support level codename version
  released="$(hwdata_distro_released "$DF_D_ID" "$DF_D_VERSION")"
  support="$(hwdata_distro_support "$DF_D_ID" "$DF_D_VERSION")"
  level="$(hwdata_distro_support_level "$DF_D_ID" "$DF_D_VERSION")"
  codename="$(hwdata_distro_codename "$DF_D_ID" "$DF_D_VERSION")"
  version="$DF_D_VERSION"

  case "$level" in
    dead) level=alert ;;
    warn) level=warn ;;
    *) level="" ;;
  esac

  local -a rows=()
  rows+=("ID${DF_FS}$DF_D_ID")
  rows+=("Version${DF_FS}${version:-rolling}")
  [ "$DF_DETAIL" -ge 2 ] && rows+=("Codename${DF_FS}${codename:-none}")
  [ "$DF_DETAIL" -ge 1 ] && rows+=("Released${DF_FS}${released:-unknown}")
  rows+=("Support${DF_FS}${support:-unknown}${DF_FS}$level")
  _df_panel _out DISTRIBUTION "$w" 9 - "${rows[@]}"
}

_df_build_cpu() {
  local -n _out="$1"
  local w="$2"
  local arch_row arch launched process microline
  local vendor ordinal gen_row gen_label gen_year
  local latest latest_o latest_label latest_year genline behind

  vendor="$(detect_cpu_vendor)"

  arch_row="$(hwdata_cpu_arch "$(detect_cpu_vendor_id)" \
    "$(detect_cpu_family)" "$(detect_cpu_model_id)")"
  IFS='|' read -r arch launched process <<<"$arch_row"

  if [ -n "$arch" ]; then
    microline="$arch"
    [ -n "$launched" ] && microline="$microline, launched $launched"
    [ -n "$process" ] && microline="$microline, $process"
  else
    # No table row. Saying nothing is correct; inventing a codename is not.
    microline="not in the bundled table"
  fi

  # --- generation, and how far behind it is ---
  ordinal="$(hwdata_cpu_gen_ordinal "$(detect_cpu_model_name)" \
    "$(detect_cpu_vendor_id)" "$(detect_cpu_family)" "$(detect_cpu_model_id)")"
  gen_row="$(hwdata_cpu_generation "$vendor" "$ordinal")"
  IFS='|' read -r gen_label gen_year <<<"$gen_row"

  latest="$(hwdata_cpu_latest_generation "$vendor")"
  IFS='|' read -r latest_o latest_label latest_year <<<"$latest"

  if [ -n "$gen_label" ]; then
    genline="$gen_label"
    [ -n "$gen_year" ] && genline="$genline, released $gen_year"
  elif [ -n "$ordinal" ]; then
    # An ordinal with no row: the part reports a generation the table has not caught up
    # with, which is worth saying plainly rather than hiding.
    genline="generation $ordinal, not yet in the bundled table"
  else
    genline="not on the consumer generation ladder"
  fi

  # The vendor logo costs 22 columns. Below this the values start clipping to make
  # room for it, and a legible fact beats a legible logo — so the art is the thing
  # that goes, the same way the distro column drops out on a narrow terminal.
  local art=DF_CPU_LOGO_LINES
  if [ "$w" -lt 86 ]; then
    art='-'
  fi

  local -a rows=()
  rows+=("Model${DF_FS}$(detect_cpu)")
  [ "$DF_DETAIL" -ge 2 ] && rows+=("Vendor${DF_FS}$vendor")
  rows+=("Generation${DF_FS}$genline")
  rows+=("$(_df_currency_row "$ordinal" "$latest_o" "$latest_label" "$latest_year")")
  [ "$DF_DETAIL" -ge 1 ] && rows+=("Micro-arch${DF_FS}$microline")
  [ "$DF_DETAIL" -ge 2 ] && rows+=("Signature${DF_FS}$(detect_cpu_signature)")
  rows+=("Topology${DF_FS}$(detect_cpu_topology)")
  [ "$DF_DETAIL" -ge 1 ] && rows+=("Clock${DF_FS}$(detect_cpu_freq)")
  [ "$DF_DETAIL" -ge 2 ] && rows+=("Cache${DF_FS}$(detect_cpu_cache)")
  [ "$DF_DETAIL" -ge 1 ] && rows+=("Features${DF_FS}$(detect_cpu_features)")

  _df_panel _out PROCESSOR "$w" 10 "$art" "${rows[@]}"
}

# The "N generations behind" row.
#
# The comparison target is named rather than just counted, because the count is only as
# current as lib/data/cpu-generations.tsv: a stale table under-reports, and "3 behind
# Core Ultra Series 2 (2024)" lets the reader notice that the basis is out of date in a
# way that a bare "3 generations behind" does not.
_df_currency_row() {
  local ordinal="$1" latest_o="$2" latest_label="$3" latest_year="$4"
  local behind level=""

  # "unknown" would be wrong here: for a server part the Generation row has already
  # said why there is no ordinal, and repeating it as a failed lookup reads as a bug.
  if [ -z "$ordinal" ]; then
    printf 'Currency%snot applicable' "$DF_FS"
    return 0
  fi
  if [ -z "$latest_o" ]; then
    printf 'Currency%sunknown' "$DF_FS"
    return 0
  fi

  behind=$((latest_o - ordinal))
  if [ "$behind" -le 0 ]; then
    printf 'Currency%scurrent: %s is the newest known generation' \
      "$DF_FS" "$latest_label"
    return 0
  fi

  # Four generations is roughly six years of Intel or eight of AMD: far enough that
  # security and performance guidance written today assumes something newer.
  [ "$behind" -ge 4 ] && level=warn

  printf '%s%s%s generation%s behind %s (%s)%s%s' \
    Currency "$DF_FS" "$behind" "$([ "$behind" -eq 1 ] || printf 's')" \
    "$latest_label" "$latest_year" "$DF_FS" "$level"
}

_df_build_memory() {
  local -n _out="$1"
  local w="$2"
  local -a rows=()
  local line locator size type ff speed cfg maker size_gib slots populated=0

  rows+=("RAM${DF_FS}$(detect_memory)")
  [ "$DF_DETAIL" -ge 1 ] && rows+=("Swap${DF_FS}$(detect_swap)")

  if dmi_raw_readable; then
    slots="$(dmi_slot_count)"
    while IFS='|' read -r locator size type ff speed cfg maker; do
      [ -n "$locator" ] || continue
      populated=$((populated + 1))
      size_gib=$((size / 1024))
      if [ "$size_gib" -ge 1 ]; then
        size="${size_gib} GiB"
      else
        size="${size} MiB"
      fi
      # Rated and configured speed differ whenever XMP/EXPO is off, which is the
      # single most useful thing this panel can tell someone.
      if [ "$cfg" -gt 0 ] && [ "$speed" -gt 0 ] && [ "$cfg" -ne "$speed" ]; then
        speed="${cfg} MT/s (rated ${speed})"
      elif [ "$cfg" -gt 0 ]; then
        speed="${cfg} MT/s"
      else
        speed="speed unknown"
      fi
      if [ "$DF_DETAIL" -ge 1 ]; then
        rows+=("${DF_FS}${locator}: ${size} ${type:+$type }${ff:+$ff }@ ${speed}${maker:+ - $maker}")
      fi
    done < <(dmi_dimms)
    rows+=("Slots${DF_FS}${populated} of ${slots} populated")
  else
    rows+=("Modules${DF_FS}$(dmi_raw_reason)${DF_FS}warn")
  fi

  _df_panel _out MEMORY "$w" 9 - "${rows[@]}"
}

_df_build_machine() {
  local -n _out="$1"
  local w="$2"
  local -a rows=()
  rows+=("Model${DF_FS}$(detect_machine)")
  [ "$DF_DETAIL" -ge 2 ] && rows+=("Board${DF_FS}$(detect_board)")
  [ "$DF_DETAIL" -ge 1 ] && rows+=("Firmware${DF_FS}$(detect_bios)")
  _df_panel _out MACHINE "$w" 9 - "${rows[@]}"
}

_df_build_graphics() {
  local -n _out="$1"
  local w="$2"
  local -a rows=()
  local rec vendor device driver kind name label

  for rec in "${DF_GPUS[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r vendor device driver kind <<<"$rec"
    name="$(hwdata_pci_name "$vendor" "$device")"
    case "$kind" in
      3d) label="3D" ;;
      display) label="Display" ;;
      *) label="GPU" ;;
    esac
    if [ "$DF_DETAIL" -ge 1 ] && [ -n "$driver" ]; then
      rows+=("${label}${DF_FS}${name} (${driver})")
    else
      rows+=("${label}${DF_FS}${name}")
    fi
  done

  if [ "${#rows[@]}" -eq 0 ]; then
    # No display-class device at all is normal on a server or in a container, and is a
    # different answer from "there is one and I could not name it".
    rows+=("GPU${DF_FS}none present")
  fi

  _df_panel _out GRAPHICS "$w" 9 - "${rows[@]}"
}

_df_build_storage() {
  local -n _out="$1"
  local w="$2"
  local -a rows=()
  local rec name size rot model transport pcie kind detail

  for rec in "${DF_DISKS[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r name size rot model transport pcie <<<"$rec"

    # rotational is the only reliable SSD/HDD signal in sysfs, and it is exact: the
    # kernel sets it from whether the device advertises a rotation rate.
    if [ "$rot" = 0 ]; then
      kind=SSD
    elif [ "$rot" = 1 ]; then
      kind=HDD
    else
      kind=disk
    fi
    [ "$transport" = nvme ] && kind=NVMe

    detail="$(disk_size_human "$size") ${kind}"
    [ -n "$model" ] && detail="$detail ${model}"
    # The PCIe link is the interesting part of an NVMe drive: a Gen4 drive in a Gen3
    # slot halves its throughput and nothing else on the system says so.
    if [ "$DF_DETAIL" -ge 1 ] && [ -n "$pcie" ]; then
      detail="$detail - $pcie"
    fi
    rows+=("${name}${DF_FS}${detail}")
  done

  if [ "${#rows[@]}" -eq 0 ]; then
    rows+=("Disks${DF_FS}none present")
  fi

  _df_panel _out STORAGE "$w" 9 - "${rows[@]}"
}

_df_build_network() {
  local -n _out="$1"
  local w="$2"
  local -a rows=()
  local rec name kind vendor device driver state speed model link gen rated

  for rec in "${DF_NICS[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r name kind vendor device driver state speed <<<"$rec"
    model="$(hwdata_pci_name "$vendor" "$device")"

    if [ "$kind" = wifi ]; then
      gen="$(wifi_generation "$model")"
      if [ -n "$gen" ]; then
        link="$gen"
      elif wifi_is_cnvi "$model"; then
        # Not a gap in the lookup — a gap in what the PCI ID can express. CNVi puts the
        # wireless MAC in the chipset and the radio in a separate module, so two
        # machines with this same ID can be Wi-Fi 6 and Wi-Fi 6E.
        link="CNVi, generation set by the RF module not the PCI ID"
      else
        link="Wi-Fi"
      fi
      [ -n "$state" ] && link="$link, $state"
    else
      rated="$(ethernet_rated_speed "$model")"
      link="$state"
      if [ -n "$speed" ]; then
        link="$link at $(dev_speed_human "$speed")"
      fi
      # Rated versus negotiated is the pair that identifies a bad cable or a switch
      # port stuck at 100 Mbps, and neither number says it alone.
      if [ -n "$rated" ]; then
        if [ -n "$speed" ] && [ "$rated" = "$(dev_speed_human "$speed")" ]; then
          link="$link (at its rated speed)"
        else
          link="$link, rated $rated"
        fi
      fi
    fi

    if [ "$DF_DETAIL" -ge 1 ] && [ -n "$driver" ]; then
      rows+=("${name}${DF_FS}${model} (${driver}) - ${link}")
    else
      rows+=("${name}${DF_FS}${model} - ${link}")
    fi
  done

  if [ "${#rows[@]}" -eq 0 ]; then
    rows+=("Interfaces${DF_FS}none with a hardware device")
  fi

  _df_panel _out NETWORK "$w" 9 - "${rows[@]}"
}

_df_build_peripherals() {
  local -n _out="$1"
  local w="$2"
  local -a rows=() order=()
  local rec bus speed version ports name key best=0 total_ports=0
  local domain gen security iommu tvendor tdevice
  local id dvendor ddevice authorized found_tbt=0 tbt_summary=""
  declare -A count ports_total label

  # Grouped by speed class rather than listed per controller. Four lines saying
  # "usb1: USB 2.0 ... usb3: USB 2.0 ..." carry one fact between them; the useful
  # question is what speeds this machine can do and how many ports run at each.
  for rec in "${DF_USB[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r bus speed version ports <<<"$rec"
    name="$(usb_speed_name "$speed")"
    key="${speed:-0}"
    case "$speed" in
      '' | *[!0-9]*) ;;
      *) [ "$speed" -gt "$best" ] && best="$speed" ;;
    esac
    if [ -z "${count[$key]:-}" ]; then
      order+=("$key")
      count[$key]=0
      ports_total[$key]=0
      label[$key]="${name:-USB} ($(dev_speed_human "$speed"))"
    fi
    count[$key]=$((count[$key] + 1))
    ports_total[$key]=$((ports_total[$key] + ${ports:-0}))
    total_ports=$((total_ports + ${ports:-0}))
  done

  if [ "${#order[@]}" -gt 0 ]; then
    # Root-hub port counts do not sum to the sockets on the chassis: one USB-C
    # connector is wired to a 2.0 root hub and a 3.x one at once, so the total is
    # routinely double the number of holes in the case. Saying so costs a clause and
    # stops the number being read as something it is not.
    rows+=("USB${DF_FS}fastest $(dev_speed_human "$best"); root ports are per controller, not sockets")
    if [ "$DF_DETAIL" -ge 1 ]; then
      for key in "${order[@]}"; do
        rows+=("${DF_FS}  ${label[$key]}: ${count[$key]} controller$([ "${count[$key]}" = 1 ] || printf s), ${ports_total[$key]} root port$([ "${ports_total[$key]}" = 1 ] || printf s)")
      done
    fi
  else
    rows+=("USB${DF_FS}no host controllers")
  fi

  for rec in "${DF_TBT[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r domain gen security iommu tvendor tdevice <<<"$rec"
    found_tbt=1
    if [ "$DF_DETAIL" -ge 2 ]; then
      rows+=("Thunderbolt${DF_FS}${domain}: $(tbt_generation_name "$gen")${tvendor:+, ${tvendor} ${tdevice}}")
      rows+=("${DF_FS}  security: $(tbt_security_name "$security"); IOMMU DMA protection $(if [ "$iommu" = 1 ]; then printf on; else printf off; fi)")
    else
      # Condensed: one line for however many domains, since they are almost always
      # identical controllers on the same chip.
      tbt_summary="$(tbt_generation_name "$gen"), security $security"
    fi
  done

  if [ "$found_tbt" -eq 0 ]; then
    rows+=("Thunderbolt${DF_FS}no Thunderbolt or USB4 controller")
  elif [ -n "$tbt_summary" ]; then
    rows+=("Thunderbolt${DF_FS}${#DF_TBT[@]} domain$([ "${#DF_TBT[@]}" = 1 ] || printf s): ${tbt_summary}")
  fi

  for rec in "${DF_TBT_DEVS[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r id dvendor ddevice authorized <<<"$rec"
    rows+=("${DF_FS}  attached ${id}: ${dvendor} ${ddevice}$(if [ "$authorized" = 1 ]; then printf ' (authorised)'; else printf ' (not authorised)'; fi)")
  done

  _df_panel _out PERIPHERALS "$w" 11 - "${rows[@]}"
}

# ---------------------------------------------------------------------------
# The plain report
# ---------------------------------------------------------------------------

# --no-art, and the fallback for a terminal too narrow for panels. One fact per line,
# no frame, no logo: greppable, diffable, and stable for anything parsing it.
render_plain() {
  local support
  # render_plain is also the narrow-terminal fallback, reached before any collection.
  [ "${#DF_DISKS[@]}" -gt 0 ] || _df_collect_devices

  printf '%s%s%s@%s%s%s\n' "$DF_BOLD$DF_BRIGHT" "${USER:-$(id -un)}" "$DF_RESET" \
    "$DF_BOLD$DF_BRIGHT" "$(detect_host)" "$DF_RESET"
  printf '%s%s%s\n' "$DF_DIM" '────────────────────────────────' "$DF_RESET"

  DF_D_ID="${DF_D_ID:-$(detect_distro_id)}"
  DF_D_VERSION="${DF_D_VERSION:-$(detect_distro_version)}"
  support="$(hwdata_distro_support "$DF_D_ID" "$DF_D_VERSION")"

  _df_plain_field 'OS:' "$(detect_os)"
  _df_plain_field 'Kernel:' "$(detect_kernel)"
  _df_plain_field 'Arch:' "$(detect_arch)"
  _df_plain_field 'Uptime:' "$(detect_uptime)"
  _df_plain_field 'Packages:' "$(detect_packages)"
  _df_plain_field 'Shell:' "$(detect_shell)"
  _df_plain_field 'Released:' "$(hwdata_distro_released "$DF_D_ID" "$DF_D_VERSION")"
  _df_plain_field 'Support:' "$support"
  _df_plain_field 'CPU:' "$(detect_cpu)"
  _df_plain_field 'CPU gen:' "$(_df_plain_generation)"
  _df_plain_field 'Cores:' "$(detect_cpu_topology)"
  _df_plain_field 'Clock:' "$(detect_cpu_freq)"
  _df_plain_field 'Cache:' "$(detect_cpu_cache)"
  _df_plain_field 'Memory:' "$(detect_memory)"
  _df_plain_field 'Swap:' "$(detect_swap)"
  _df_plain_field 'Disks:' "$(_df_plain_disks)"
  _df_plain_field 'GPU:' "$(_df_plain_gpus)"
  _df_plain_field 'Network:' "$(_df_plain_nics)"
  _df_plain_field 'USB:' "$(_df_plain_usb)"
  _df_plain_field 'TBolt:' "$(_df_plain_tbt)"
  _df_plain_field 'Machine:' "$(detect_machine)"
  _df_plain_field 'Firmware:' "$(detect_bios)"
}

# The generation facts as one line, for the plain report.
_df_plain_generation() {
  local vendor ordinal gen_row gen_label gen_year latest latest_o latest_label out=""
  vendor="$(detect_cpu_vendor)"
  ordinal="$(hwdata_cpu_gen_ordinal "$(detect_cpu_model_name)" \
    "$(detect_cpu_vendor_id)" "$(detect_cpu_family)" "$(detect_cpu_model_id)")"
  [ -n "$ordinal" ] || return 0

  gen_row="$(hwdata_cpu_generation "$vendor" "$ordinal")"
  IFS='|' read -r gen_label gen_year <<<"$gen_row"
  [ -n "$gen_label" ] || return 0
  out="$gen_label ($gen_year)"

  latest="$(hwdata_cpu_latest_generation "$vendor")"
  IFS='|' read -r latest_o latest_label _ <<<"$latest"
  if [ -n "$latest_o" ] && [ "$latest_o" -gt "$ordinal" ]; then
    out="$out, $((latest_o - ordinal)) behind $latest_label"
  fi
  printf '%s' "$out"
}

# The device lists as one line each, for the plain report. Multiple devices are joined
# with "; " rather than wrapped, so the one-fact-per-line contract holds.
# The device lists as one line each, for the plain report. Multiple devices are joined
# with "; " rather than wrapped, so the one-fact-per-line contract holds. All of these
# read the caches that _df_collect_devices filled, so nothing walks sysfs twice.
_df_plain_disks() {
  local rec name size rot model transport pcie kind out=""
  for rec in "${DF_DISKS[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r name size rot model transport pcie <<<"$rec"
    if [ "$transport" = nvme ]; then
      kind=NVMe
    elif [ "$rot" = 1 ]; then
      kind=HDD
    else
      kind=SSD
    fi
    out="${out:+$out; }${name} $(disk_size_human "$size") ${kind}${model:+ $model}${pcie:+ $pcie}"
  done
  printf '%s' "${out:-none}"
}

_df_plain_gpus() {
  local rec vendor device driver kind out=""
  for rec in "${DF_GPUS[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r vendor device driver kind <<<"$rec"
    out="${out:+$out; }$(hwdata_pci_name "$vendor" "$device")${driver:+ ($driver)}"
  done
  printf '%s' "${out:-none present}"
}

_df_plain_nics() {
  local rec name kind vendor device driver state speed out="" entry model
  for rec in "${DF_NICS[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r name kind vendor device driver state speed <<<"$rec"
    model="$(hwdata_pci_name "$vendor" "$device")"
    entry="$name $model $state"
    [ -n "$speed" ] && entry="$entry $(dev_speed_human "$speed")"
    if [ "$kind" = wifi ]; then
      entry="$entry $(wifi_generation "$model")"
    else
      entry="$entry $(ethernet_rated_speed "$model")"
    fi
    out="${out:+$out; }${entry% }"
  done
  printf '%s' "${out:-none}"
}

_df_plain_usb() {
  local rec bus speed version ports out=""
  for rec in "${DF_USB[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r bus speed version ports <<<"$rec"
    out="${out:+$out; }${bus} $(usb_speed_name "$speed") $(dev_speed_human "$speed") ${ports:-0} root ports"
  done
  printf '%s' "${out:-none}"
}

_df_plain_tbt() {
  local rec domain gen security iommu tvendor tdevice out=""
  for rec in "${DF_TBT[@]}"; do
    [ -n "$rec" ] || continue
    IFS='|' read -r domain gen security iommu tvendor tdevice <<<"$rec"
    out="${out:+$out; }${domain} $(tbt_generation_name "$gen") security=$security"
  done
  printf '%s' "${out:-none}"
}

_df_plain_field() {
  local value="$2"
  [ -n "$value" ] || value="unknown"
  printf '%s%-10s%s %s%s%s\n' "$DF_GREEN" "$1" "$DF_RESET" "$DF_BRIGHT" "$value" "$DF_RESET"
}

# Entry point from bin/distrofetch.
render_report() {
  if [ "$DF_ART" -eq 1 ]; then
    render_dashboard
  else
    render_plain
  fi
}
