#!/usr/bin/env bash
# Host introspection.
#
# Every function here prints exactly one line on stdout and never exits — facts we
# cannot determine come back as "unknown" so the renderer never has to branch. This
# module reads /etc, /proc, and /sys only: no network, no writes, no privilege needed.
#
# Sourced by bin/distrofetch.

# shellcheck shell=bash

detect_os() {
  local pretty=""
  if [ -r /etc/os-release ]; then
    # Sourced in a subshell so the caller's environment stays clean.
    pretty="$(
      # shellcheck disable=SC1091  # runtime path, not present in the repo
      . /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-${NAME:-}}"
    )" || pretty=""
  fi
  printf '%s\n' "${pretty:-unknown}"
}

detect_kernel() {
  uname -sr 2>/dev/null || printf 'unknown\n'
}

detect_arch() {
  uname -m 2>/dev/null || printf 'unknown\n'
}

detect_host() {
  local name=""
  if [ -r /etc/hostname ]; then
    read -r name </etc/hostname || name=""
  fi
  [ -n "$name" ] || name="$(uname -n 2>/dev/null || true)"
  printf '%s\n' "${name:-unknown}"
}

detect_shell() {
  local sh="${SHELL:-}"
  [ -n "$sh" ] || sh="$(command -v bash || true)"
  printf '%s\n' "${sh##*/}"
}

# Uptime as "3d 4h 17m". /proc/uptime is seconds-since-boot as a float.
detect_uptime() {
  local raw secs days hours mins out=""
  [ -r /proc/uptime ] || {
    printf 'unknown\n'
    return
  }
  read -r raw _ </proc/uptime || {
    printf 'unknown\n'
    return
  }
  secs="${raw%%.*}"
  case "$secs" in
    '' | *[!0-9]*)
      printf 'unknown\n'
      return
      ;;
  esac

  days=$((secs / 86400))
  hours=$(((secs % 86400) / 3600))
  mins=$(((secs % 3600) / 60))

  [ "$days" -gt 0 ] && out="${days}d "
  { [ "$days" -gt 0 ] || [ "$hours" -gt 0 ]; } && out="${out}${hours}h "
  out="${out}${mins}m"
  printf '%s\n' "$out"
}

# CPU model plus logical core count, e.g. "AMD Ryzen 9 7950X (32)".
detect_cpu() {
  local model="" cores=0 line
  [ -r /proc/cpuinfo ] || {
    printf 'unknown\n'
    return
  }
  while IFS= read -r line; do
    case "$line" in
      'model name'*)
        [ -n "$model" ] || model="${line#*: }"
        cores=$((cores + 1))
        ;;
      'Model'*) [ -n "$model" ] || model="${line#*: }" ;; # aarch64 has no "model name"
    esac
  done </proc/cpuinfo

  # ARM and some virtualised hosts omit "model name" entirely; fall back to a count.
  if [ "$cores" -eq 0 ]; then
    cores="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '0')"
  fi
  [ -n "$model" ] || model="unknown"

  if [ "$cores" -gt 0 ]; then
    printf '%s (%s)\n' "$model" "$cores"
  else
    printf '%s\n' "$model"
  fi
}

# "5.9 GiB / 31.2 GiB" — used is total minus available, which is what people mean.
detect_memory() {
  local total_kb=0 avail_kb=0 used_kb key val
  [ -r /proc/meminfo ] || {
    printf 'unknown\n'
    return
  }
  while read -r key val _; do
    case "$key" in
      MemTotal:) total_kb="$val" ;;
      MemAvailable:) avail_kb="$val" ;;
    esac
  done </proc/meminfo

  [ "$total_kb" -gt 0 ] || {
    printf 'unknown\n'
    return
  }
  used_kb=$((total_kb - avail_kb))
  printf '%s / %s\n' "$(_gib "$used_kb")" "$(_gib "$total_kb")"
}

# Kibibytes to GiB with one decimal, without depending on bc or awk.
_gib() {
  local kb="$1" whole tenth
  whole=$((kb / 1048576))
  tenth=$(((kb % 1048576) * 10 / 1048576))
  printf '%s.%s GiB' "$whole" "$tenth"
}

# Installed package count. This is the one probe that genuinely differs per distro,
# which is why the smoke-test matrix covers Arch, Debian, and Fedora.
detect_packages() {
  local count=""
  if command -v pacman >/dev/null 2>&1; then
    count="$(pacman -Qq 2>/dev/null | wc -l)"
    printf '%s (pacman)\n' "$count"
  elif command -v dpkg-query >/dev/null 2>&1; then
    count="$(dpkg-query -f '.\n' -W 2>/dev/null | wc -l)"
    printf '%s (dpkg)\n' "$count"
  elif command -v rpm >/dev/null 2>&1; then
    count="$(rpm -qa 2>/dev/null | wc -l)"
    printf '%s (rpm)\n' "$count"
  else
    printf 'unknown\n'
  fi
}
