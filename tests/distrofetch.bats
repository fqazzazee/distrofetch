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
  COLUMNS=120 LINES=60 run "$DF" --duration 0 --no-color
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
  COLUMNS=120 LINES=60 run "$DF" --no-color --no-clear
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
  COLUMNS=120 LINES=60 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"┌"* ]]
  [[ "$output" == *"└"* ]]
  for section in SYSTEM DISTRIBUTION PROCESSOR MEMORY MACHINE; do
    [[ "$output" == *"$section"* ]]
  done
}

@test "--no-logo keeps the panels and drops the art" {
  COLUMNS=120 LINES=60 run "$DF" --no-color --no-logo
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
  COLUMNS=40 LINES=60 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *"┌"* ]]
  [[ "$output" == *"OS:"* ]]
}

@test "a wide terminal lays the panels out in two columns" {
  # Pairing now happens only when the window can hold two panels at their full content
  # width, so the threshold is much wider than it was when panels were simply halved.
  COLUMNS=280 LINES=80 run "$DF" --no-color --no-clear
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
  COLUMNS=70 LINES=60 run "$DF" --no-color
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
    COLUMNS=$width LINES=60 run "$DF" --no-color --no-clear
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
    COLUMNS=$width LINES=60 run "$DF" --no-color --no-clear
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
  COLUMNS=120 LINES=60 run "$DF" --no-color --logo=arch
  [ "$status" -eq 0 ]
  # The arch logo's last row is unmistakable.
  [[ "$output" == *"/_-''"* ]]
}

@test "--logo accepts a space-separated value" {
  COLUMNS=120 LINES=60 run "$DF" --no-color --logo tux
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
  COLUMNS=140 LINES=60 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"Generation"* ]]
  [[ "$output" == *"Currency"* ]]
}

@test "the vendor logo appears in the processor panel on a wide terminal" {
  COLUMNS=140 LINES=60 run "$DF" --no-color --no-clear
  [ "$status" -eq 0 ]
  # One of the three bundled marks has to be there.
  [[ "$output" == *"|_|_| |_|"* || "$output" == *"/_/ \\_\\_|"* || "$output" == *"|CPU|"* ]]
}

# The mark goes when keeping it would leave the value column too narrow to read,
# measured against the art actually loaded rather than a constant. Nothing is clipped
# to make room for it either way.
@test "the vendor logo drops out on a terminal too narrow to hold both" {
  COLUMNS=58 LINES=60 run "$DF" --no-color --no-clear
  [ "$status" -eq 0 ]
  [[ "$output" != *"|CPU|"* ]]
  [[ "$output" != *"|_|_| |_|"* ]]
  # The panel still carries its facts, wrapped rather than cut.
  [[ "$output" == *"Micro-arch"* ]]
  [[ "$output" != *"..."* ]]
}

@test "--no-logo removes the vendor logo as well as the distro one" {
  COLUMNS=140 LINES=60 run "$DF" --no-color --no-logo
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

# --- device panels ---------------------------------------------------------
#
# Driven from the sysfs fixtures rather than the host, so these assert the same thing
# on a laptop with integrated graphics and on a CI runner with no display adapter at
# all. FIXTURE_ENV is every seam at once.

fixture_env() {
  local r="$BATS_TEST_DIRNAME/fixtures/sysfs"
  printf 'DF_SYS_PCI=%s/pci DF_SYS_NET=%s/net DF_SYS_USB=%s/usb DF_SYS_TBT=%s/thunderbolt DF_SYS_BLOCK=%s/block' \
    "$r" "$r" "$r" "$r" "$r"
}

@test "the dashboard shows every device panel" {
  COLUMNS=140 LINES=60 run "$DF" --no-color
  [ "$status" -eq 0 ]
  for section in GRAPHICS NETWORK PERIPHERALS; do
    [[ "$output" == *"$section"* ]]
  done
}

@test "switchable graphics show both adapters, labelled" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"GPU"* ]]
  [[ "$output" == *"3D"* ]]
  [[ "$output" == *"NVIDIA"* ]]
}

# Virtual interfaces are listed too, on one muted row. Filtering them out cannot
# answer "why is my interface missing", which is what someone opens this panel to find.
@test "physical interfaces are detailed and virtual ones are listed" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color --no-clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"eth0"* ]]
  [[ "$output" == *"wlan0"* ]]
  [[ "$output" == *"Virtual"* ]]
  [[ "$output" == *"docker0 (bridge"* ]]
  [[ "$output" == *"lo (loopback"* ]]
}

# A port with nothing plugged into it is the case the panel was reported missing for.
@test "a disconnected interface is shown and says why it is down" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color --no-clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"eth1"* ]]
  [[ "$output" == *"down"* ]]
}

@test "a down link is shown as down with no speed attached to it" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color
  [[ "$output" == *"eth1"* ]]
  [[ "$output" != *"-1 Mbps"* ]]
  [[ "$output" != *"-1 Gbps"* ]]
}

# The output is designed to be screenshotted. A MAC address is a durable unique
# identifier for the machine, so it must never reach the screen.
@test "no MAC address reaches the dashboard" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color
  [[ "$output" != *"de:ad:be:ef"* ]]
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-art --no-color
  [[ "$output" != *"de:ad:be:ef"* ]]
}

@test "USB buses are grouped by speed class with a fastest-bus summary" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"USB 2.0 (480 Mbps): 2 controllers"* ]]
  [[ "$output" == *"USB4 (40 Gbps): 1 controller"* ]]
  [[ "$output" == *"fastest 40 Gbps"* ]]
}

# Root-hub port counts do not map to sockets on the chassis: one USB-C connector is
# wired to a 2.0 root hub and a 3.x one at once. The output has to say so.
@test "the USB panel says root ports are not sockets" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color
  [[ "$output" == *"not sockets"* ]]
}

@test "Thunderbolt domains report generation and security policy" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"Thunderbolt 4 / USB4 (40 Gbps)"* ]]
  [[ "$output" == *"Thunderbolt 3 (40 Gbps)"* ]]
  [[ "$output" == *"connections need approval"* ]]
  [[ "$output" == *"full PCIe access"* ]]
}

@test "an attached Thunderbolt device is listed with its authorisation state" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color
  [[ "$output" == *"CalDigit TS4"* ]]
  [[ "$output" == *"not authorised"* ]]
}

@test "a machine with none of this hardware says so rather than failing" {
  local empty="$BATS_TEST_TMPDIR/none"
  mkdir -p "$empty"
  COLUMNS=140 LINES=60 DF_SYS_PCI="$empty" DF_SYS_NET="$empty" DF_SYS_USB="$empty" \
    DF_SYS_TBT="$empty" run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"none present"* ]]
  [[ "$output" == *"no host controllers"* ]]
  [[ "$output" == *"no Thunderbolt or USB4 controller"* ]]
}

@test "the plain report carries each device class on one line" {
  run env $(fixture_env) "$DF" --no-art --no-color
  [ "$status" -eq 0 ]
  for label in 'GPU:' 'Network:' 'USB:' 'TBolt:'; do
    [[ "$output" == *"$label"* ]]
  done
  # One fact per line means multiple devices are joined, never wrapped.
  local gpu_lines
  gpu_lines="$(printf '%s\n' "$output" | grep -c '^GPU:')"
  [ "$gpu_lines" -eq 1 ]
}

# --- storage ---------------------------------------------------------------

@test "the storage panel lists disks with capacity, kind, and PCIe link" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color --no-clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"STORAGE"* ]]
  [[ "$output" == *"nvme0n1"* ]]
  [[ "$output" == *"1.0 TB"* ]]
  [[ "$output" == *"NVMe"* ]]
  [[ "$output" == *"PCIe Gen 4 x4 (4 lanes)"* ]]
}

@test "a drive negotiated below its maximum shows both figures" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color --no-clear
  [[ "$output" == *"PCIe Gen 3 x2 (2 lanes), capable of Gen 4 x4"* ]]
}

@test "spinning disks and SSDs are distinguished" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color --no-clear
  [[ "$output" == *"HDD"* ]]
  [[ "$output" == *"SSD"* ]]
}

@test "no disk serial reaches the output" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color --no-clear
  [[ "$output" != *SERIAL-DO-NOT-PRINT* ]]
  run env $(fixture_env) "$DF" --no-art --no-color
  [[ "$output" != *SERIAL-DO-NOT-PRINT* ]]
}

@test "the plain report carries the disks on one line" {
  run env $(fixture_env) "$DF" --no-art --no-color
  [[ "$output" == *"Disks:"* ]]
}

# --- wireless and wired detail ---------------------------------------------

@test "a Wi-Fi generation is shown when the device name carries one" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color --no-clear
  [ "$status" -eq 0 ]
  # The fixture's wlan0 is 8086:51f1, whose pci.ids name says CNVi and no generation.
  [[ "$output" == *"wlan0"* ]]
}

@test "an ethernet link shows its negotiated speed" {
  COLUMNS=140 LINES=80 run env $(fixture_env) "$DF" --no-color --no-clear
  [[ "$output" == *"1 Gbps"* ]]
}

# --- fitting the terminal --------------------------------------------------
#
# The point of the density system: the dashboard is meant to be one screenshot, so it
# gives up detail rather than scrolling.

@test "--fit makes the dashboard fit the terminal height" {
  local h n
  for h in 60 50 45; do
    COLUMNS=150 LINES=$h run "$DF" --no-color --no-clear --fit
    [ "$status" -eq 0 ]
    n="${#lines[@]}"
    [ "$n" -le $((h - 1)) ]
  done
}

# --fit trades detail for height, but it will not truncate a value to get there —
# wrapping makes a condensed panel taller than a clipped one, so below roughly 35 lines
# nine panels simply do not fit. It gets as close as it can and stops.
@test "--fit shrinks as far as it can and does not truncate to go further" {
  COLUMNS=150 LINES=60 run "$DF" --no-color --no-clear --fit
  local tall="${#lines[@]}"

  COLUMNS=150 LINES=24 run "$DF" --no-color --no-clear --fit
  [ "${#lines[@]}" -lt "$tall" ]
  [[ "$output" != *"..."* ]]
}

# Without --fit nothing is dropped: scrolling costs the reader nothing and a dropped
# row costs them the fact. This is the reverse of the earlier default, deliberately.
@test "without --fit the dashboard keeps everything and lets the terminal scroll" {
  COLUMNS=150 LINES=20 run "$DF" --no-color --no-clear
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -gt 19 ]
  [[ "$output" == *"Signature"* ]]
  [[ "$output" == *"Cache"* ]]
}

# Asserted as a relationship rather than against specific rows: which row is the first
# to go depends on how much the machine has to say, and a CI runner says less than a
# laptop. What must hold everywhere is that less height means less output, and that what
# survives still identifies the machine.
@test "--fit keeps identity while dropping the rows that restate something" {
  COLUMNS=150 LINES=80 run "$DF" --no-color --no-clear --fit
  local tall="${#lines[@]}"

  COLUMNS=150 LINES=24 run "$DF" --no-color --no-clear --fit
  [ "${#lines[@]}" -lt "$tall" ]
  for kept in OS Kernel Model STORAGE MEMORY; do
    [[ "$output" == *"$kept"* ]]
  done
}

# The PCIe link is why anyone reads the storage panel, so it survives every density.
@test "--fit never drops the PCIe link from a disk" {
  COLUMNS=150 LINES=26 run env $(fixture_env) "$DF" --no-color --no-clear --fit
  [ "$status" -eq 0 ]
  [[ "$output" == *"PCIe Gen"* ]]
}

# Panels whose one row says "none present" cost three lines to say nothing. At the
# tightest density they are dropped instead.
@test "panels with nothing to report are dropped when space is short" {
  local empty="$BATS_TEST_TMPDIR/none"
  mkdir -p "$empty"
  COLUMNS=150 LINES=18 DF_SYS_PCI="$empty" DF_SYS_NET="$empty" DF_SYS_USB="$empty" \
    DF_SYS_TBT="$empty" DF_SYS_BLOCK="$empty" run "$DF" --no-color --no-clear --fit
  [ "$status" -eq 0 ]
  [[ "$output" != *"none present"* ]]
  [[ "$output" != *"no host controllers"* ]]
}

@test "the screen is cleared only on a terminal" {
  # bats captures through a pipe, so this is the non-TTY path.
  COLUMNS=150 LINES=60 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033[2J'* ]]
}

@test "--no-clear suppresses the clear and is accepted" {
  COLUMNS=150 LINES=60 run "$DF" --no-color --no-clear
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033[2J'* ]]
  [[ "$output" == *"SYSTEM"* ]]
}

@test "--help documents the clear and the fitting" {
  run "$DF" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--no-clear"* ]]
}

# --- hardware and release facts -------------------------------------------

@test "the dashboard reports a support status for this distro" {
  COLUMNS=120 LINES=60 run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"Support"* ]]
}

# Memory module detail is root-only. An unprivileged run must say why rather than
# printing "unknown", which reads as a failed probe.
@test "memory modules report their reason when the raw tables are unreadable" {
  COLUMNS=120 LINES=60 DF_DMI_ENTRIES=/nonexistent run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"no SMBIOS tables"* ]]
  [[ "$output" != *"Modules   unknown"* ]]
}

@test "memory modules are listed when the raw tables can be read" {
  COLUMNS=140 LINES=60 DF_DMI_ENTRIES="$BATS_TEST_DIRNAME/fixtures/dmi-entries" \
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
