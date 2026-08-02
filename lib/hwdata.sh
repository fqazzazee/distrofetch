#!/usr/bin/env bash
# Lookups against the bundled reference tables in lib/data/.
#
# Everything here answers a question the machine cannot answer about itself: when a
# distro release shipped, when its support ends, what microarchitecture a family/model
# pair names. That information is not on the system, so it is carried in tab-separated
# tables that ship with the tool.
#
# Two rules govern this module:
#
#   1. A live source always beats the table. /etc/os-release carries SUPPORT_END= on
#      Fedora, RHEL, and the RHEL rebuilds; where it exists it is authoritative and the
#      table is not consulted, because the table is a snapshot and the field is not.
#   2. A miss prints nothing rather than a guess. Bundled data goes stale, and a stale
#      "supported until" is worse than a blank: one is a gap, the other is wrong.
#
# Sourced by bin/distrofetch.

# shellcheck shell=bash

# Set by bin/distrofetch once the library directory is resolved.
: "${DISTROFETCH_DATA:=}"

# --- table access ----------------------------------------------------------

# Every non-comment, non-blank line of a table. Missing tables are not fatal: a partial
# install should degrade to fewer facts, not to a crash.
_hw_table() {
  local file="$DISTROFETCH_DATA/$1"
  [ -r "$file" ] || return 1
  grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$file" 2>/dev/null
}

# Version strings are more specific than the table: Rocky reports 9.8 where the table
# knows 9, Alpine reports 3.24.1 where it knows 3.24. Try the whole string, then drop
# one dotted component at a time, then the rolling-release wildcard.
_hw_version_candidates() {
  local v="$1"
  while [ -n "$v" ]; do
    printf '%s\n' "$v"
    case "$v" in
      *.*) v="${v%.*}" ;;
      *) break ;;
    esac
  done
  printf '*\n'
}

# --- distribution ----------------------------------------------------------

# Fields of /etc/os-release, which is shell syntax. Sourced in a subshell so a
# malformed or hostile file cannot leak variables into the caller — the same
# containment detect_os uses, and the reason SPEC.md documents this as the one place
# distrofetch executes code it did not ship.
hwdata_osrelease() {
  local key="$1"
  [ -r /etc/os-release ] || return 0
  (
    # shellcheck disable=SC1091  # runtime path, not present in the repo
    . /etc/os-release 2>/dev/null || exit 0
    printf '%s' "${!key:-}"
  )
}

# The table row for this distro, or nothing:  id  version  codename  released  eol  kind
hwdata_distro_row() {
  local id="$1" version="$2" cand line f_id f_ver
  [ -n "$id" ] || return 0
  while read -r cand; do
    while IFS= read -r line; do
      IFS=$'\t' read -r f_id f_ver _ <<<"$line"
      if [ "$f_id" = "$id" ] && [ "$f_ver" = "$cand" ]; then
        printf '%s\n' "$line"
        return 0
      fi
    done < <(_hw_table distro-releases.tsv || true)
  done < <(_hw_version_candidates "$version")
}

# Days from today to `date`, negative once it has passed. Empty if the date will not
# parse — busybox date does not take -d the way GNU date does, and a wrong number here
# would be reported as a support status.
hwdata_days_until() {
  local when="$1" target now
  [ -n "$when" ] && [ "$when" != '-' ] || return 0
  target="$(date -d "$when" +%s 2>/dev/null)" || return 0
  [ -n "$target" ] || return 0
  now="$(date +%s)"
  printf '%s' $(((target - now) / 86400))
}

# Support status as a sentence, from SUPPORT_END= if the distro ships it and the
# bundled table otherwise. Prints one of:
#   supported until 2027-05-19 (291 days)
#   END OF LIFE since 2024-06-30 (763 days ago)
#   rolling release — no end of life
hwdata_distro_support() {
  local id="$1" version="$2" eol="" kind="" days row table_eol=""
  eol="$(hwdata_osrelease SUPPORT_END)"

  row="$(hwdata_distro_row "$id" "$version")"
  if [ -n "$row" ]; then
    IFS=$'\t' read -r _ _ _ _ table_eol kind <<<"$row"
    [ -n "$eol" ] || eol="$table_eol"
  fi

  if [ "$kind" = rolling ]; then
    printf 'rolling release, no end of life'
    return 0
  fi
  if [ -z "$eol" ] || [ "$eol" = '-' ]; then
    return 0
  fi

  days="$(hwdata_days_until "$eol")"
  if [ -z "$days" ]; then
    printf 'supported until %s' "$eol"
  elif [ "$days" -lt 0 ]; then
    printf 'END OF LIFE since %s (%s days ago)' "$eol" "$((-days))"
  else
    printf 'supported until %s (%s days)' "$eol" "$days"
  fi
}

# 'ok', 'warn' when support ends within 90 days, or 'dead'. The dashboard colours the
# support line from this rather than re-parsing the sentence above.
hwdata_distro_support_level() {
  local id="$1" version="$2" eol days row table_eol="" kind=""
  eol="$(hwdata_osrelease SUPPORT_END)"
  row="$(hwdata_distro_row "$id" "$version")"
  if [ -n "$row" ]; then
    IFS=$'\t' read -r _ _ _ _ table_eol kind <<<"$row"
    [ "$kind" = rolling ] && {
      printf 'ok'
      return 0
    }
    [ -n "$eol" ] || eol="$table_eol"
  fi
  days="$(hwdata_days_until "$eol")"
  if [ -z "$days" ]; then
    printf 'ok'
  elif [ "$days" -lt 0 ]; then
    printf 'dead'
  elif [ "$days" -lt 90 ]; then
    printf 'warn'
  else
    printf 'ok'
  fi
}

hwdata_distro_released() {
  local row released
  row="$(hwdata_distro_row "$1" "$2")"
  [ -n "$row" ] || return 0
  IFS=$'\t' read -r _ _ _ released _ <<<"$row"
  # An `if` rather than `[ ] && printf`, which would return 1 from the function on a
  # missing date and take the caller down with it under set -e.
  if [ "$released" != '-' ]; then
    printf '%s' "$released"
  fi
}

# The codename, preferring the live VERSION_CODENAME= over the table.
hwdata_distro_codename() {
  local live row codename
  live="$(hwdata_osrelease VERSION_CODENAME)"
  if [ -n "$live" ]; then
    printf '%s' "$live"
    return 0
  fi
  row="$(hwdata_distro_row "$1" "$2")"
  [ -n "$row" ] || return 0
  IFS=$'\t' read -r _ _ codename _ <<<"$row"
  if [ "$codename" != '-' ]; then
    printf '%s' "$codename"
  fi
}

# --- CPU -------------------------------------------------------------------

# microarchitecture|launch year|process node for a vendor/family/model triple, or
# nothing. Exact model first, then the family wildcard.
hwdata_cpu_arch() {
  local vendor="$1" family="$2" model="$3" want line f_v f_f f_m arch launched process
  [ -n "$vendor" ] && [ -n "$family" ] || return 0
  for want in "$model" '*'; do
    while IFS= read -r line; do
      # Seven names for seven columns: read folds every trailing field into the last
      # variable, so omitting the gen column here appends it to the process node.
      IFS=$'\t' read -r f_v f_f f_m arch launched process _ <<<"$line"
      if [ "$f_v" = "$vendor" ] && [ "$f_f" = "$family" ] && [ "$f_m" = "$want" ]; then
        printf '%s|%s|%s' "$arch" "$launched" "$process"
        return 0
      fi
    done < <(_hw_table cpu-arch.tsv || true)
  done
}

# The generation ordinal for a CPU, or nothing.
#
# The model *string* wins where it carries an explicit marker, because family/model
# cannot always tell generations apart: Intel's 14th Gen desktop is Raptor Lake
# refreshed, so 13th and 14th Gen share model 183. The string says which one it is.
# Everything else falls back to the `gen` column of cpu-arch.tsv.
hwdata_cpu_gen_ordinal() {
  local model_name="$1" vendor="$2" family="$3" model="$4"
  local want line f_v f_f f_m gen

  # Server parts are off the consumer ladder, and family/model cannot always say so:
  # EPYC Naples and Ryzen Summit Ridge are both family 23 model 1. The brand string can,
  # and an EPYC reported as "Ryzen 5000" is a confidently wrong answer about someone's
  # hardware — which is exactly what a CI runner reported before this check existed.
  case "$model_name" in
    *EPYC* | *epyc* | *Xeon* | *XEON* | *xeon*) return 0 ;;
  esac

  # "13th Gen Intel(R) Core(TM) i7-1360P" -> 13. Intel has printed this marker in the
  # brand string since Skylake, and it is the only self-describing source available.
  case "$model_name" in
    *[0-9]'th Gen'* | *[0-9]'st Gen'* | *[0-9]'nd Gen'* | *[0-9]'rd Gen'*)
      gen="${model_name%%th Gen*}"
      gen="${gen%%st Gen*}"
      gen="${gen%%nd Gen*}"
      gen="${gen%%rd Gen*}"
      gen="${gen##* }"
      case "$gen" in
        '' | *[!0-9]*) ;;
        *)
          printf '%s' "$gen"
          return 0
          ;;
      esac
      ;;
  esac

  [ -n "$vendor" ] && [ -n "$family" ] || return 0
  for want in "$model" '*'; do
    while IFS= read -r line; do
      IFS=$'\t' read -r f_v f_f f_m _ _ _ gen <<<"$line"
      if [ "$f_v" = "$vendor" ] && [ "$f_f" = "$family" ] && [ "$f_m" = "$want" ]; then
        if [ -n "$gen" ] && [ "$gen" != '-' ]; then
          printf '%s' "$gen"
        fi
        return 0
      fi
    done < <(_hw_table cpu-arch.tsv || true)
  done
}

# label|year for a vendor's generation ordinal, or nothing.
hwdata_cpu_generation() {
  local vendor="$1" ordinal="$2" line f_v f_o label year
  [ -n "$vendor" ] && [ -n "$ordinal" ] || return 0
  while IFS= read -r line; do
    IFS=$'\t' read -r f_v f_o label year <<<"$line"
    if [ "$f_v" = "$vendor" ] && [ "$f_o" = "$ordinal" ]; then
      printf '%s|%s' "$label" "$year"
      return 0
    fi
  done < <(_hw_table cpu-generations.tsv || true)
}

# ordinal|label|year of the newest generation this table knows about for a vendor.
#
# Derived from the table's own maximum rather than a constant, so adding a generation
# is one line and every "N behind" recalculates. A stale table therefore *under*-reports
# how far behind a part is, which is why callers report the comparison basis by name.
hwdata_cpu_latest_generation() {
  local vendor="$1" line f_v f_o label year
  local best_o="" best_label="" best_year=""
  [ -n "$vendor" ] || return 0
  while IFS= read -r line; do
    IFS=$'\t' read -r f_v f_o label year <<<"$line"
    [ "$f_v" = "$vendor" ] || continue
    case "$f_o" in
      '' | *[!0-9]*) continue ;;
    esac
    if [ -z "$best_o" ] || [ "$f_o" -gt "$best_o" ]; then
      best_o="$f_o"
      best_label="$label"
      best_year="$year"
    fi
  done < <(_hw_table cpu-generations.tsv || true)
  if [ -n "$best_o" ]; then
    printf '%s|%s|%s' "$best_o" "$best_label" "$best_year"
  fi
}

# The vendor logo file name. Unlike distro logos this is a closed set — there are two
# x86 vendors — so anything else gets the generic chip rather than a name lookup.
hwdata_cpu_logo_name() {
  case "$1" in
    Intel) printf 'intel' ;;
    AMD) printf 'amd' ;;
    *) printf 'generic' ;;
  esac
}

# --- PCI names -------------------------------------------------------------

# Where pci.ids lives, or nothing. Fedora and Arch put it under /usr/share/hwdata,
# Debian under /usr/share/misc. It is part of the hwdata package and frequently absent
# from containers, which is why there is a fallback at all.
: "${DF_PCI_IDS:=}"

_hw_pci_ids_path() {
  local f
  if [ -n "$DF_PCI_IDS" ]; then
    [ -r "$DF_PCI_IDS" ] && printf '%s' "$DF_PCI_IDS"
    return 0
  fi
  for f in /usr/share/hwdata/pci.ids /usr/share/misc/pci.ids /usr/share/pci.ids; do
    if [ -r "$f" ]; then
      printf '%s' "$f"
      return 0
    fi
  done
}

# Short vendor name from the bundled table, or nothing.
_hw_pci_vendor_fallback() {
  local want="$1" line id name
  [ -n "$want" ] || return 0
  while IFS= read -r line; do
    IFS=$'\t' read -r id name <<<"$line"
    if [ "$id" = "$want" ]; then
      printf '%s' "$name"
      return 0
    fi
  done < <(_hw_table pci-vendors.tsv || true)
}

# "Intel Raptor Lake-P [Iris Xe Graphics]" for a vendor/device pair, degrading to
# "Intel [8086:a7a0]" and then to "[8086:a7a0]" as sources run out.
#
# pci.ids is 1.6 MB and roughly 25 000 lines, so it is never read line by line in the
# shell. sed extracts the one vendor block and grep picks the device out of it — both
# in C, both over a file the kernel has in page cache anyway. Measured at ~15 ms.
hwdata_pci_name() {
  # Initialised, not merely declared: `local x` leaves x *unset*, and under `set -u`
  # reading it is a fatal error. Every assignment below is inside a conditional, so on
  # a system with no pci.ids none of them run — which is two of the three CI images.
  local vendor="$1" device="$2" file="" vname="" dname="" line="" short=""
  [ -n "$vendor" ] || return 0

  file="$(_hw_pci_ids_path)"
  if [ -n "$file" ]; then
    line="$(grep -m1 "^$vendor  " "$file" 2>/dev/null)" || line=""
    vname="${line#"$vendor"  }"
    if [ -n "$device" ]; then
      # One sed, no pipeline. The range runs from this vendor's line to the next
      # vendor's line; device lines inside it are tab-indented, which is what
      # distinguishes them from vendor lines. `q` stops at the first match.
      #
      # This was `sed ... | grep -m1 ...` and looked correct: grep exits at the first
      # match, sed takes SIGPIPE, and under `set -o pipefail` the whole pipeline
      # reports failure — so the `|| dname=""` fallback fired on every *successful*
      # lookup and every device came out as a bare hex ID.
      dname="$(sed -n \
        "/^$vendor  /,/^[0-9a-f][0-9a-f][0-9a-f][0-9a-f]  /{/^	$device  /{s/^	$device  //p;q;};}" \
        "$file" 2>/dev/null)" || dname=""
    fi
  fi

  # The bundled short name wins for the *vendor* even when pci.ids is present, while
  # pci.ids still supplies the *device*. pci.ids gives legal entities — "Intel
  # Corporation", "Advanced Micro Devices, Inc. [AMD/ATI]" — and a panel row has better
  # uses for eleven columns than a corporate suffix nobody reads twice.
  short="$(_hw_pci_vendor_fallback "$vendor")"
  [ -n "$short" ] && vname="$short"

  if [ -n "$vname" ] && [ -n "$dname" ]; then
    printf '%s %s' "$vname" "$dname"
  elif [ -n "$vname" ]; then
    printf '%s [%s:%s]' "$vname" "$vendor" "$device"
  else
    printf '[%s:%s]' "$vendor" "$device"
  fi
}

# --- logos -----------------------------------------------------------------

# Distros that share a parent's artwork, or whose ID does not match a file name. Kept
# as a case rather than a table because it is control flow, not data — every arm is a
# judgement about which logo is *less* wrong, not a fact about the world.
hwdata_logo_name() {
  local id="$1" like="$2" word
  case "$id" in
    opensuse* | suse | sles)
      printf 'opensuse'
      return 0
      ;;
    pop | pop_os)
      printf 'pop'
      return 0
      ;;
    linuxmint | mint | lmde)
      printf 'linuxmint'
      return 0
      ;;
    rhel | redhat*)
      printf 'rhel'
      return 0
      ;;
    almalinux | alma)
      printf 'almalinux'
      return 0
      ;;
    rocky)
      printf 'rocky'
      return 0
      ;;
    centos)
      printf 'centos'
      return 0
      ;;
    endeavouros)
      printf 'endeavouros'
      return 0
      ;;
    manjaro*)
      printf 'manjaro'
      return 0
      ;;
    elementary)
      printf 'elementary'
      return 0
      ;;
  esac

  if [ -n "$id" ] && [ -r "$DISTROFETCH_LOGOS/$id.txt" ]; then
    printf '%s' "$id"
    return 0
  fi

  # ID_LIKE is a space-separated list, nearest relative first: a derivative that ships
  # no logo of its own borrows its parent's.
  for word in $like; do
    if [ -r "$DISTROFETCH_LOGOS/$word.txt" ]; then
      printf '%s' "$word"
      return 0
    fi
  done

  printf 'tux'
}
