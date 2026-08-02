#!/usr/bin/env bash
# DMI/SMBIOS access, in two tiers.
#
# Tier one is /sys/class/dmi/id/* — plain text files, world-readable on every distro
# tested, giving board, chassis, and firmware identity. That is where the machine and
# BIOS facts come from and it needs no privilege.
#
# Tier two is the raw SMBIOS structures under /sys/firmware/dmi/entries/. Those are
# mode 0400 on every mainline kernel, so per-DIMM manufacturer, type, and speed are
# readable only by root. distrofetch does not require root and never asks for it; it
# reports what it can see and says plainly when the rest needs elevation. Running
# `sudo distrofetch` fills the gap.
#
# The parser is deliberately hand-rolled rather than shelling out to dmidecode: a
# runtime dependency is a promise broken, and od(1) is coreutils.
#
# Sourced by bin/distrofetch.

# shellcheck shell=bash

# Overridable so the tests can point at fixtures. This is a test seam, not a feature:
# both paths are read-only system data that the caller could read directly anyway, so
# redirecting them grants nothing a user does not already have.
: "${DF_DMI_ID:=/sys/class/dmi/id}"
: "${DF_DMI_ENTRIES:=/sys/firmware/dmi/entries}"

# Bytes of the entry currently being parsed, one per array slot. Reset per entry.
_df_dmi_bytes=()

# --- tier one: unprivileged identity ---------------------------------------

# Contents of a /sys/class/dmi/id file, or the empty string. Firmware routinely fills
# these with placeholder junk — a board with no vendor set reports "To Be Filled By
# O.E.M.", which is worse than nothing because it looks like data.
dmi_id() {
  local field="$1" value=""
  [ -r "$DF_DMI_ID/$field" ] || return 0
  read -r -d '' value <"$DF_DMI_ID/$field" || true
  value="${value%"${value##*[![:space:]]}"}"
  case "$value" in
    '' | 'To Be Filled By O.E.M.' | 'To be filled by O.E.M.' | \
      'System manufacturer' | 'System Product Name' | 'Default string' | \
      'Not Applicable' | 'Not Specified' | 'None' | 'Unknown' | 'N/A' | 'O.E.M.')
      return 0
      ;;
  esac
  printf '%s' "$value"
}

# --- tier two: raw SMBIOS structures ---------------------------------------

# Whether the raw structures can be read at all. A false answer is the normal case for
# an unprivileged run and is not an error.
dmi_raw_readable() {
  local f
  for f in "$DF_DMI_ENTRIES"/17-*/raw; do
    [ -r "$f" ] && return 0
  done
  return 1
}

# Why tier two is unavailable, for the one line the dashboard prints instead of DIMMs.
dmi_raw_reason() {
  if [ ! -d "$DF_DMI_ENTRIES" ]; then
    printf 'no SMBIOS tables (virtual machine or non-x86 firmware)'
  elif ! compgen -G "$DF_DMI_ENTRIES/17-*" >/dev/null 2>&1; then
    printf 'firmware exposes no memory device records'
  else
    printf 'needs root: run sudo distrofetch'
  fi
}

# Read one entry into _df_dmi_bytes. od -v keeps duplicate lines, which matters because
# runs of identical bytes are common and * elision would shift every later offset.
_df_dmi_load() {
  local file="$1" b
  _df_dmi_bytes=()
  [ -r "$file" ] || return 1
  while read -r b; do
    # An `if`, not `[ -n "$b" ] && ...`: as the last statement in the loop body that
    # would leave the loop returning 1 on a trailing blank line, and set -e would take
    # the caller down with it.
    if [ -n "$b" ]; then
      _df_dmi_bytes+=("$b")
    fi
  done < <(od -An -v -tu1 -w1 "$file" 2>/dev/null | tr -d ' ')
  [ "${#_df_dmi_bytes[@]}" -ge 4 ] || return 1
}

# Little-endian word at `off`.
_df_dmi_word() {
  local off="$1"
  if [ $((off + 1)) -ge "${#_df_dmi_bytes[@]}" ]; then
    printf '0'
    return
  fi
  printf '%s' $((_df_dmi_bytes[off] | (_df_dmi_bytes[off + 1] << 8)))
}

# Little-endian dword at `off`.
_df_dmi_dword() {
  local off="$1"
  if [ $((off + 3)) -ge "${#_df_dmi_bytes[@]}" ]; then
    printf '0'
    return
  fi
  printf '%s' $((_df_dmi_bytes[off] | (_df_dmi_bytes[off + 1] << 8) | (\
  _df_dmi_bytes[off + 2] << 16) | (_df_dmi_bytes[off + 3] << 24)))
}

# The `n`th string of the entry. Strings are NUL-separated and start immediately after
# the formatted area, whose length is byte 1. Index 0 means "no string", which is not
# the same as an empty one.
_df_dmi_str() {
  local want="$1" i len count=1 esc="" oct out byte
  [ "$want" -gt 0 ] || return 0
  len="${_df_dmi_bytes[1]}"
  i="$len"
  while [ "$i" -lt "${#_df_dmi_bytes[@]}" ]; do
    byte="${_df_dmi_bytes[i]}"
    if [ "$byte" -eq 0 ]; then
      if [ "$count" -eq "$want" ]; then
        break
      fi
      # A NUL immediately after a NUL terminates the string set: the wanted index is
      # past the end, which firmware does when a field is genuinely unset.
      if [ -z "$esc" ] && [ "$count" -gt 1 ]; then
        return 0
      fi
      count=$((count + 1))
      esc=""
    else
      # printf -v is a builtin, so this stays fork-free; $(printf ...) here would cost
      # one subshell per character of every string on the board.
      printf -v oct '\\%03o' "$byte"
      esc+="$oct"
    fi
    i=$((i + 1))
  done
  printf -v out '%b' "$esc"
  # Firmware pads unset strings with spaces rather than leaving them empty.
  out="${out#"${out%%[![:space:]]*}"}"
  out="${out%"${out##*[![:space:]]}"}"
  case "$out" in
    'Unknown' | 'Not Specified' | 'None' | '' | '0000' | 'NO DIMM') return 0 ;;
  esac
  printf '%s' "$out"
}

# SMBIOS 3.x table 7.18.2. Only the values a person would recognise are named; anything
# else prints as its raw code so a bug report can identify it.
_df_dmi_memtype() {
  case "$1" in
    18) printf 'DDR' ;;
    19) printf 'DDR2' ;;
    20) printf 'DDR2 FB-DIMM' ;;
    24) printf 'DDR3' ;;
    26) printf 'DDR4' ;;
    27) printf 'LPDDR' ;;
    28) printf 'LPDDR2' ;;
    29) printf 'LPDDR3' ;;
    30) printf 'LPDDR4' ;;
    32) printf 'HBM' ;;
    33) printf 'HBM2' ;;
    34) printf 'DDR5' ;;
    35) printf 'LPDDR5' ;;
    36) printf 'HBM3' ;;
    1 | 2) return 0 ;;
    *) printf 'type %s' "$1" ;;
  esac
}

# Form factor, table 7.18.1 — enough to tell a laptop SODIMM from a desktop DIMM.
# These are the spec's hex codes in decimal: DIMM is 09h, SODIMM is 0Dh. Reading them
# off as 8 and 12 lands on "Proprietary Card" and "RIMM".
_df_dmi_formfactor() {
  case "$1" in
    9) printf 'DIMM' ;;
    10) printf 'TSOP' ;;
    12) printf 'RIMM' ;;
    13) printf 'SODIMM' ;;
    14) printf 'SRIMM' ;;
    15) printf 'FB-DIMM' ;;
    16) printf 'Die' ;;
    *) return 0 ;;
  esac
}

# One line per populated memory device:
#   DIMM A1|16 GiB|DDR5|5200|SK Hynix|HMCG78AGBSA095N
#
# Empty slots are skipped: on a four-slot board with two sticks, printing two "empty"
# rows is noise, and the slot count is reported separately.
#
# The serial number at offset 0x18 is deliberately never read. This output is designed
# to be screenshotted and posted, and a DIMM serial is a durable hardware identifier.
dmi_dimms() {
  local file size_raw size_mb speed cfg_speed type_code ff_code
  local locator manufacturer part type ff

  for file in "$DF_DMI_ENTRIES"/17-*/raw; do
    [ -r "$file" ] || continue
    _df_dmi_load "$file" || continue
    [ "${_df_dmi_bytes[0]}" -eq 17 ] || continue

    size_raw="$(_df_dmi_word 12)"
    # 0 means the slot is empty; 0xFFFF means the firmware does not know.
    [ "$size_raw" -eq 0 ] && continue
    [ "$size_raw" -eq 65535 ] && continue

    if [ "$size_raw" -eq 32767 ]; then
      # 0x7FFF is the escape to the 32-bit Extended Size field, in MB.
      size_mb="$(_df_dmi_dword 28)"
    elif [ $((size_raw & 32768)) -ne 0 ]; then
      # Bit 15 set means the value is in kilobytes, not megabytes.
      size_mb=$(((size_raw & 32767) / 1024))
    else
      size_mb="$size_raw"
    fi
    [ "$size_mb" -gt 0 ] || continue

    type_code="${_df_dmi_bytes[18]:-0}"
    ff_code="${_df_dmi_bytes[14]:-0}"
    speed="$(_df_dmi_word 21)"
    cfg_speed="$(_df_dmi_word 32)"
    locator="$(_df_dmi_str "${_df_dmi_bytes[16]:-0}")"
    manufacturer="$(_df_dmi_str "${_df_dmi_bytes[23]:-0}")"
    part="$(_df_dmi_str "${_df_dmi_bytes[26]:-0}")"
    type="$(_df_dmi_memtype "$type_code")"
    ff="$(_df_dmi_formfactor "$ff_code")"

    # Configured speed is what the stick actually runs at; rated speed is what it is
    # capable of. They differ whenever XMP/EXPO is off, which is worth seeing.
    [ "$cfg_speed" -gt 0 ] || cfg_speed="$speed"

    printf '%s|%s|%s|%s|%s|%s|%s\n' \
      "${locator:-slot}" "$size_mb" "${type:-}" "${ff:-}" \
      "$speed" "$cfg_speed" "${manufacturer:-}${part:+ ($part)}"
  done
}

# Total number of memory slots the board exposes, populated or not.
dmi_slot_count() {
  local n=0 d
  for d in "$DF_DMI_ENTRIES"/17-*; do
    [ -d "$d" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}
