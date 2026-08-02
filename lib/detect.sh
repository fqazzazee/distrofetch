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

# Swap as "used / total", or "none" when there is no swap configured. A machine with
# no swap is a fact worth seeing, not a missing value.
detect_swap() {
  local total_kb=0 free_kb=0 key val
  [ -r /proc/meminfo ] || {
    printf 'unknown\n'
    return
  }
  while read -r key val _; do
    case "$key" in
      SwapTotal:) total_kb="$val" ;;
      SwapFree:) free_kb="$val" ;;
    esac
  done </proc/meminfo

  if [ "$total_kb" -le 0 ]; then
    printf 'none\n'
    return
  fi
  printf '%s / %s\n' "$(_gib $((total_kb - free_kb)))" "$(_gib "$total_kb")"
}

# --- distribution identity -------------------------------------------------
#
# detect_os prints the human-readable name; these print the machine-readable fields the
# release table and the logo picker key on.

_df_osrelease_field() {
  local key="$1" out=""
  [ -r /etc/os-release ] || {
    printf '\n'
    return
  }
  out="$(
    # shellcheck disable=SC1091  # runtime path, not present in the repo
    . /etc/os-release 2>/dev/null && printf '%s' "${!key:-}"
  )" || out=""
  printf '%s\n' "$out"
}

detect_distro_id() {
  local id
  id="$(_df_osrelease_field ID)"
  printf '%s\n' "${id:-unknown}"
}

detect_distro_version() {
  local v
  v="$(_df_osrelease_field VERSION_ID)"
  printf '%s\n' "$v"
}

detect_distro_like() {
  _df_osrelease_field ID_LIKE
}

# --- CPU detail ------------------------------------------------------------
#
# /proc/cpuinfo is parsed once into these globals rather than once per probe: on a
# many-core machine the file is hundreds of kilobytes and each probe would re-read it.

DF_CPU_LOADED=0
DF_CPU_VENDOR=""
DF_CPU_FAMILY=""
DF_CPU_MODEL_ID=""
DF_CPU_STEPPING=""
DF_CPU_MICROCODE=""
DF_CPU_MODEL_NAME=""
DF_CPU_THREADS=0
DF_CPU_CORES=0
DF_CPU_MHZ=""
DF_CPU_FLAGS=""

_df_cpuinfo_load() {
  local line key value
  [ "$DF_CPU_LOADED" -eq 0 ] || return 0
  DF_CPU_LOADED=1
  [ -r /proc/cpuinfo ] || return 0

  while IFS= read -r line; do
    case "$line" in
      *:*) ;;
      *) continue ;;
    esac
    key="${line%%:*}"
    value="${line#*: }"
    # Strip the tab padding /proc/cpuinfo uses to align its colons.
    key="${key%"${key##*[![:space:]]}"}"
    case "$key" in
      processor) DF_CPU_THREADS=$((DF_CPU_THREADS + 1)) ;;
      vendor_id) [ -n "$DF_CPU_VENDOR" ] || DF_CPU_VENDOR="$value" ;;
      'cpu family') [ -n "$DF_CPU_FAMILY" ] || DF_CPU_FAMILY="$value" ;;
      model) [ -n "$DF_CPU_MODEL_ID" ] || DF_CPU_MODEL_ID="$value" ;;
      'model name') [ -n "$DF_CPU_MODEL_NAME" ] || DF_CPU_MODEL_NAME="$value" ;;
      stepping) [ -n "$DF_CPU_STEPPING" ] || DF_CPU_STEPPING="$value" ;;
      microcode) [ -n "$DF_CPU_MICROCODE" ] || DF_CPU_MICROCODE="$value" ;;
      'cpu cores') [ -n "$DF_CPU_CORES" ] && [ "$DF_CPU_CORES" -gt 0 ] || DF_CPU_CORES="$value" ;;
      'cpu MHz') [ -n "$DF_CPU_MHZ" ] || DF_CPU_MHZ="${value%%.*}" ;;
      flags | Features) [ -n "$DF_CPU_FLAGS" ] || DF_CPU_FLAGS=" $value " ;;
    esac
  done </proc/cpuinfo
}

detect_cpu_vendor() {
  _df_cpuinfo_load
  case "$DF_CPU_VENDOR" in
    GenuineIntel) printf 'Intel\n' ;;
    AuthenticAMD) printf 'AMD\n' ;;
    '') printf 'unknown\n' ;;
    *) printf '%s\n' "$DF_CPU_VENDOR" ;;
  esac
}

detect_cpu_vendor_id() {
  _df_cpuinfo_load
  printf '%s\n' "$DF_CPU_VENDOR"
}

# The unmodified brand string. detect_cpu appends a core count; the generation parser
# needs the string exactly as the CPU reports it.
detect_cpu_model_name() {
  _df_cpuinfo_load
  printf '%s\n' "$DF_CPU_MODEL_NAME"
}

detect_cpu_family() {
  _df_cpuinfo_load
  printf '%s\n' "$DF_CPU_FAMILY"
}

detect_cpu_model_id() {
  _df_cpuinfo_load
  printf '%s\n' "$DF_CPU_MODEL_ID"
}

# "family 6, model 186, stepping 2, microcode 0x6134" — the identity a bug report needs
# and the key the microarchitecture table is indexed by.
detect_cpu_signature() {
  _df_cpuinfo_load
  local out=""
  [ -n "$DF_CPU_FAMILY" ] && out="family $DF_CPU_FAMILY"
  [ -n "$DF_CPU_MODEL_ID" ] && out="${out:+$out, }model $DF_CPU_MODEL_ID"
  [ -n "$DF_CPU_STEPPING" ] && out="${out:+$out, }stepping $DF_CPU_STEPPING"
  [ -n "$DF_CPU_MICROCODE" ] && out="${out:+$out, }ucode $DF_CPU_MICROCODE"
  printf '%s\n' "${out:-unknown}"
}

# Total logical CPUs the kernel knows about, from /sys/devices/system/cpu/present —
# a range list like "0-15" or "0-3,8-11". /proc/cpuinfo cannot answer this: it lists
# only *online* CPUs, so on a laptop that parks cores the count changes between reads.
_df_cpu_present() {
  local spec part lo hi total=0
  [ -r /sys/devices/system/cpu/present ] || return 1
  read -r spec </sys/devices/system/cpu/present || return 1
  local IFS=,
  for part in $spec; do
    case "$part" in
      *-*)
        lo="${part%%-*}"
        hi="${part##*-}"
        total=$((total + hi - lo + 1))
        ;;
      '') ;;
      *) total=$((total + 1)) ;;
    esac
  done
  [ "$total" -gt 0 ] || return 1
  printf '%s' "$total"
}

# "12 cores / 16 threads", or just the thread count when the kernel does not report
# physical cores — which is the normal case on aarch64 and inside some hypervisors.
#
# When some CPUs are offline the online count is appended rather than substituted: on a
# machine parking cores for power, silently reporting 15 of 16 threads looks like a
# detection bug every other time you run it.
detect_cpu_topology() {
  _df_cpuinfo_load
  local present online="$DF_CPU_THREADS" out=""
  present="$(_df_cpu_present)" || present="$online"

  if [ "${DF_CPU_CORES:-0}" -gt 0 ] && [ "$present" -gt 0 ]; then
    if [ "$DF_CPU_CORES" -eq "$present" ]; then
      out="$DF_CPU_CORES cores (no SMT)"
    else
      out="$DF_CPU_CORES cores / $present threads"
    fi
  elif [ "$present" -gt 0 ]; then
    out="$present threads"
  else
    printf 'unknown\n'
    return
  fi

  if [ "$online" -gt 0 ] && [ "$online" -lt "$present" ]; then
    out="$out ($online online)"
  fi
  printf '%s\n' "$out"
}

# "1.6 GHz now, 2.2 GHz max". The max comes from cpufreq where the driver exposes it;
# /proc/cpuinfo's "cpu MHz" is the instantaneous clock and moves between reads.
detect_cpu_freq() {
  _df_cpuinfo_load
  local max_khz="" out="" max_mhz
  if [ -r /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq ]; then
    read -r max_khz </sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq || max_khz=""
  fi
  [ -n "$DF_CPU_MHZ" ] && out="$(_ghz "$DF_CPU_MHZ") now"
  if [ -n "$max_khz" ] && [ "$max_khz" -gt 0 ]; then
    max_mhz=$((max_khz / 1000))
    out="${out:+$out, }$(_ghz "$max_mhz") max"
  fi
  printf '%s\n' "${out:-unknown}"
}

# Megahertz to GHz with one decimal, without bc or awk.
_ghz() {
  local mhz="$1"
  printf '%s.%s GHz' $((mhz / 1000)) $(((mhz % 1000) / 100))
}

# "48K L1d, 32K L1i, 1280K L2, 18432K L3" as reported for cpu0. L1 and L2 are per core
# on every current design; L3 is shared across the package.
detect_cpu_cache() {
  local d level type size out="" label
  for d in /sys/devices/system/cpu/cpu0/cache/index*; do
    if [ ! -r "$d/level" ] || [ ! -r "$d/size" ]; then
      continue
    fi
    read -r level <"$d/level" || continue
    read -r size <"$d/size" || continue
    type=""
    [ -r "$d/type" ] && read -r type <"$d/type"
    case "$type" in
      Data) label="L${level}d" ;;
      Instruction) label="L${level}i" ;;
      *) label="L${level}" ;;
    esac
    out="${out:+$out, }$size $label"
  done
  printf '%s\n' "${out:-unknown}"
}

# The instruction-set extensions worth knowing about, in rough order of how much they
# change what software will run. Everything else in the flags list is noise here.
detect_cpu_features() {
  _df_cpuinfo_load
  local out=""
  [ -n "$DF_CPU_FLAGS" ] || {
    printf 'unknown\n'
    return
  }
  case "$DF_CPU_FLAGS" in *' avx512f '*) out="${out:+$out, }AVX-512" ;; esac
  case "$DF_CPU_FLAGS" in
    *' avx2 '*) out="${out:+$out, }AVX2" ;;
    *' avx '*) out="${out:+$out, }AVX" ;;
  esac
  case "$DF_CPU_FLAGS" in *' aes '*) out="${out:+$out, }AES-NI" ;; esac
  case "$DF_CPU_FLAGS" in *' sha_ni '*) out="${out:+$out, }SHA-NI" ;; esac
  case "$DF_CPU_FLAGS" in
    *' vmx '*) out="${out:+$out, }VT-x" ;;
    *' svm '*) out="${out:+$out, }AMD-V" ;;
  esac
  printf '%s\n' "${out:-none detected}"
}

# --- machine and firmware --------------------------------------------------
#
# These read /sys/class/dmi/id, which is world-readable. dmi.sh filters the placeholder
# strings firmware ships when a field was never populated.

detect_machine() {
  local vendor product
  vendor="$(dmi_id sys_vendor)"
  product="$(dmi_id product_name)"
  if [ -z "$vendor" ] && [ -z "$product" ]; then
    printf 'unknown\n'
    return
  fi
  printf '%s\n' "${vendor:+$vendor }${product}"
}

detect_board() {
  local vendor name
  vendor="$(dmi_id board_vendor)"
  name="$(dmi_id board_name)"
  if [ -z "$vendor" ] && [ -z "$name" ]; then
    printf 'unknown\n'
    return
  fi
  printf '%s\n' "${vendor:+$vendor }${name}"
}

# "UP3404VA.301 (2023-05-11)". DMI dates are MM/DD/YYYY; ISO order sorts and does not
# depend on the reader's locale to disambiguate.
detect_bios() {
  local version date out=""
  version="$(dmi_id bios_version)"
  date="$(dmi_id bios_date)"
  case "$date" in
    [0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9])
      date="${date:6:4}-${date:0:2}-${date:3:2}"
      ;;
  esac
  out="$version"
  [ -n "$date" ] && out="${out:+$out }($date)"
  printf '%s\n' "${out:-unknown}"
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
