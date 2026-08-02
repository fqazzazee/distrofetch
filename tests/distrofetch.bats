#!/usr/bin/env bats
#
# CLI contract plus the detection probes. The probes assert shape, never content —
# this suite has to pass on Arch, Debian, and Fedora runners with different hardware.

setup() {
  DF="$BATS_TEST_DIRNAME/../bin/distrofetch"
  # shellcheck source=../lib/detect.sh
  . "$BATS_TEST_DIRNAME/../lib/detect.sh"
}

# ${#str} counts characters in a UTF-8 locale and bytes otherwise. distrofetch itself
# copes either way — it measures ASCII values and uses a constant for the multibyte
# banner — but the column-alignment tests below cannot measure anything without it.
require_utf8() {
  local box='│'
  if [ "${#box}" -ne 1 ]; then
    skip "needs a UTF-8 locale to measure column widths (LANG=${LANG:-unset})"
  fi
}

@test "--version prints a semver-looking string" {
  run "$DF" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--help mentions every documented flag" {
  run "$DF" --help
  [ "$status" -eq 0 ]
  for flag in --no-rain --no-art --no-logo --logo --list-logos --no-color \
    --duration --version --help; do
    [[ "$output" == *"$flag"* ]]
  done
}

@test "an unknown option exits 2 and explains itself on stderr" {
  run "$DF" --definitely-not-a-flag
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "--duration rejects a non-numeric value" {
  run "$DF" --duration soon
  [ "$status" -eq 2 ]
}

@test "--duration requires a value" {
  run "$DF" --duration
  [ "$status" -eq 2 ]
}

@test "--duration 0 is accepted and prints the report" {
  COLUMNS=120 run "$DF" --duration 0 --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"SYSTEM"* ]]
}

@test "the help text documents 0 as the default duration" {
  run "$DF" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"default: 0"* ]]
}

# A non-zero duration must still be inert off a terminal — this is what keeps the
# animation out of pipes, cron, and CI logs regardless of flags.
@test "a non-zero duration still emits no escapes when stdout is not a terminal" {
  run "$DF" --duration 5
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "the dashboard runs clean and labels every field" {
  COLUMNS=120 run "$DF" --no-color
  [ "$status" -eq 0 ]
  for label in OS Kernel Arch Uptime Packages Shell Model Vendor Topology \
    Cache Features RAM Swap Board Firmware Support; do
    [[ "$output" == *"$label"* ]]
  done
}

# bats captures output through a pipe, so every case below runs with stdout off a TTY.
# That is exactly the condition --color=always exists to override.

@test "--color=always emits escapes even off a terminal" {
  run "$DF" --color=always
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033'* ]]
}

@test "--color=never emits no escapes" {
  run "$DF" --color=never
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "--color=auto is plain off a terminal" {
  run "$DF" --color=auto
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "--color accepts a space-separated value" {
  run "$DF" --color always
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033'* ]]
}

@test "--color rejects an unknown value and names the valid ones" {
  run "$DF" --color=sometimes
  [ "$status" -eq 2 ]
  [[ "$output" == *"always"* ]]
  [[ "$output" == *"never"* ]]
  [[ "$output" == *"auto"* ]]
}

@test "--color requires a value" {
  run "$DF" --color
  [ "$status" -eq 2 ]
}

# The rain positions the cursor and clears the screen; forcing color must not smuggle
# that into a pipe.
@test "--color=always does not enable the animation off a terminal" {
  run "$DF" --color=always --duration 5
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033[2J'* ]]
  [[ "$output" != *$'\033[?25l'* ]]
}

@test "--no-color emits no ANSI escapes" {
  run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

# --- dashboard layout -----------------------------------------------------

@test "the default output is the dashboard: panels, a logo, and every section" {
  COLUMNS=120 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"┌"* ]]
  [[ "$output" == *"└"* ]]
  for section in SYSTEM DISTRIBUTION PROCESSOR MEMORY MACHINE; do
    [[ "$output" == *"$section"* ]]
  done
}

@test "--no-logo keeps the panels and drops the art" {
  COLUMNS=120 run "$DF" --no-color --no-logo
  [ "$status" -eq 0 ]
  [[ "$output" == *"┌"* ]]
  [[ "$output" == *"PROCESSOR"* ]]
}

@test "--no-art drops the frame and the logo but keeps every field" {
  run "$DF" --no-art --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *"┌"* ]]
  [[ "$output" != *"│"* ]]
  for label in OS: Kernel: Arch: Uptime: Packages: Shell: CPU: Memory: Swap: \
    Cores: Cache: Support: Machine: Firmware:; do
    [[ "$output" == *"$label"* ]]
  done
}

@test "--no-art emits no escapes when color is off" {
  run "$DF" --no-art --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

# Below the fallback threshold the panels cannot hold their own content, and wrapping
# every line is worse than not drawing them.
@test "a terminal too narrow for panels falls back to the plain list" {
  COLUMNS=40 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *"┌"* ]]
  [[ "$output" == *"OS:"* ]]
}

@test "a wide terminal lays the panels out in two columns" {
  COLUMNS=160 run "$DF" --no-color
  [ "$status" -eq 0 ]
  # SYSTEM and DISTRIBUTION share a line only in the two-column layout.
  [[ "$output" == *"SYSTEM"*"DISTRIBUTION"* ]]
  local paired=0 line
  for line in "${lines[@]}"; do
    if [[ "$line" == *SYSTEM*DISTRIBUTION* ]]; then paired=1; fi
  done
  [ "$paired" -eq 1 ]
}

@test "a narrow-but-not-tiny terminal stacks the panels in one column" {
  COLUMNS=70 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"┌"* ]]
  local paired=0 line
  for line in "${lines[@]}"; do
    if [[ "$line" == *SYSTEM*DISTRIBUTION* ]]; then paired=1; fi
  done
  [ "$paired" -eq 0 ]
}

# Every panel border has to land in the same column, or the grid visibly shears. This
# is the assertion that caught the header rule being one short and the logo column
# being budgeted two spaces where it joins with one.
@test "every panel line ends at the same column, at every width" {
  require_utf8
  local width edge first line plain
  for width in 60 70 80 100 120 140 200; do
    COLUMNS=$width run "$DF" --no-color
    [ "$status" -eq 0 ]
    first=""
    for line in "${lines[@]}"; do
      plain="${line%"${line##*[![:space:]]}"}"
      case "$plain" in
        *│ | *┐ | *┘) ;;
        *) continue ;;
      esac
      edge="${#plain}"
      if [ -z "$first" ]; then first="$edge"; fi
      [ "$edge" -eq "$first" ]
    done
    [ -n "$first" ]
  done
}

@test "no line exceeds the terminal width" {
  require_utf8
  local width line
  for width in 60 80 100 140; do
    COLUMNS=$width run "$DF" --no-color
    [ "$status" -eq 0 ]
    for line in "${lines[@]}"; do
      [ "${#line}" -le "$width" ]
    done
  done
}

# --- logo selection -------------------------------------------------------

@test "--list-logos names files that exist" {
  run "$DF" --list-logos
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -gt 10 ]
  local name
  for name in "${lines[@]}"; do
    [ -r "$BATS_TEST_DIRNAME/../lib/logos/$name.txt" ]
  done
}

@test "--list-logos includes the generic fallback" {
  run "$DF" --list-logos
  [[ "$output" == *tux* ]]
}

@test "--logo selects a specific logo regardless of the running distro" {
  COLUMNS=120 run "$DF" --no-color --logo=arch
  [ "$status" -eq 0 ]
  # The arch logo's last row is unmistakable.
  [[ "$output" == *"/_-''"* ]]
}

@test "--logo accepts a space-separated value" {
  COLUMNS=120 run "$DF" --no-color --logo tux
  [ "$status" -eq 0 ]
  [[ "$output" == *"|o_o |"* ]]
}

@test "an unknown logo name is a usage error naming the way to list them" {
  run "$DF" --logo=definitely-not-a-distro
  [ "$status" -eq 2 ]
  [[ "$output" == *"--list-logos"* ]]
}

# A logo name is joined to a directory and a suffix, so a path would escape it.
@test "--logo rejects a path rather than following it" {
  run "$DF" --logo=../../etc/passwd
  [ "$status" -eq 2 ]
  run "$DF" --logo=/etc/passwd
  [ "$status" -eq 2 ]
}

@test "--logo requires a value" {
  run "$DF" --logo
  [ "$status" -eq 2 ]
}

# Logos are measured with ${#}, which counts bytes outside a UTF-8 locale. Keeping them
# ASCII is what makes the logo column the same width in every locale.
@test "every bundled logo is pure ASCII and fits the layout budget" {
  local f rows cols
  for f in "$BATS_TEST_DIRNAME"/../lib/logos/*.txt; do
    # Single-quoted so the shell does not touch the range, and LC_ALL=C so the
    # bracket expression matches bytes: any byte outside printable ASCII fails.
    run env LC_ALL=C grep -c '[^ -~]' "$f"
    [ "$output" -eq 0 ]
    rows="$(wc -l <"$f")"
    cols="$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$f")"
    [ "$rows" -le 20 ]
    [ "$cols" -le 30 ]
  done
}

# --- processor panel -------------------------------------------------------

@test "the processor panel reports a generation and how current it is" {
  COLUMNS=140 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"Generation"* ]]
  [[ "$output" == *"Currency"* ]]
}

@test "the vendor logo appears in the processor panel on a wide terminal" {
  COLUMNS=140 run "$DF" --no-color
  [ "$status" -eq 0 ]
  # One of the three bundled marks has to be there.
  [[ "$output" == *"|_|_| |_|"* || "$output" == *"/_/ \\_\\_|"* || "$output" == *"|CPU|"* ]]
}

# The logo costs 22 columns inside the panel. Below the threshold every value clips to
# make room for it, and a legible fact beats a legible logo.
@test "the vendor logo drops out before the values start clipping" {
  COLUMNS=64 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROCESSOR"* ]]
  [[ "$output" != *"|CPU|"* ]]
  [[ "$output" != *"|_|_| |_|"* ]]
  # The panel still carries its facts.
  [[ "$output" == *"Micro-arch"* ]]
}

@test "--no-logo removes the vendor logo as well as the distro one" {
  COLUMNS=140 run "$DF" --no-color --no-logo
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROCESSOR"* ]]
  [[ "$output" != *"|_|_| |_|"* ]]
  [[ "$output" != *"|CPU|"* ]]
}

@test "the plain report carries the generation on one line" {
  run "$DF" --no-art --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"CPU gen:"* ]]
}

@test "every bundled vendor logo is pure ASCII and fits the panel gutter" {
  local f rows cols
  for f in "$BATS_TEST_DIRNAME"/../lib/cpu-logos/*.txt; do
    run env LC_ALL=C grep -c '[^ -~]' "$f"
    [ "$output" -eq 0 ]
    rows="$(wc -l <"$f")"
    cols="$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$f")"
    [ "$rows" -le 10 ]
    [ "$cols" -le 24 ]
  done
}

# --- hardware and release facts -------------------------------------------

@test "the dashboard reports a support status for this distro" {
  COLUMNS=120 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"Support"* ]]
}

# Memory module detail is root-only. An unprivileged run must say why rather than
# printing "unknown", which reads as a failed probe.
@test "memory modules report their reason when the raw tables are unreadable" {
  COLUMNS=120 DF_DMI_ENTRIES=/nonexistent run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"no SMBIOS tables"* ]]
  [[ "$output" != *"Modules   unknown"* ]]
}

@test "memory modules are listed when the raw tables can be read" {
  COLUMNS=140 DF_DMI_ENTRIES="$BATS_TEST_DIRNAME/fixtures/dmi-entries" \
    run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"DDR5"* ]]
  [[ "$output" == *"SK Hynix"* ]]
  [[ "$output" == *"populated"* ]]
  [[ "$output" != *SERIAL-DO-NOT-PRINT* ]]
}

@test "detection probes each return exactly one non-empty line" {
  for probe in detect_os detect_kernel detect_arch detect_host \
    detect_shell detect_uptime detect_cpu detect_memory detect_packages; do
    run "$probe"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "${#lines[@]}" -eq 1 ]
  done
}

@test "memory reports as 'used / total' in GiB" {
  run detect_memory
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]\ GiB\ /\ [0-9]+\.[0-9]\ GiB$ ]] || [ "$output" = "unknown" ]
}
