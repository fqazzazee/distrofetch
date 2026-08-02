#!/usr/bin/env bash
# Device enumeration: graphics, network interfaces, USB buses, Thunderbolt domains.
#
# Kept out of detect.sh because these break that module's contract. A probe in
# detect.sh answers one question with one line. A function here answers "what is
# attached" and prints **one line per device, or nothing at all** — a machine with no
# discrete GPU and a machine whose GPU could not be identified are different answers,
# and "unknown" cannot express the first.
#
# Every line is pipe-delimited with a fixed field count, so the renderer never parses
# free text. Fields that could not be determined are empty, never the string "unknown".
#
# Everything here reads sysfs, which is world-readable: no privilege, no ioctls, no
# helper binaries. The deliberate omissions are the identifiers that would turn a
# screenshot into a tracking token — MAC addresses and PCI serial numbers are never
# read, for the same reason dmi.sh never reads a DIMM serial.
#
# Sourced by bin/distrofetch.

# shellcheck shell=bash

# Overridable so the tests can point at fixture trees. Test seams, not features: these
# are read-only system paths the caller could read directly anyway.
: "${DF_SYS_PCI:=/sys/bus/pci/devices}"
: "${DF_SYS_NET:=/sys/class/net}"
: "${DF_SYS_USB:=/sys/bus/usb/devices}"
: "${DF_SYS_TBT:=/sys/bus/thunderbolt/devices}"

# Contents of a sysfs attribute with the trailing newline stripped, or nothing. sysfs
# reads can fail with EINVAL or ENODEV on a device that is asleep or being removed, so
# every read here tolerates failure.
_dev_read() {
  local value=""
  [ -r "$1" ] || return 0
  read -r value <"$1" 2>/dev/null || return 0
  printf '%s' "$value"
}

# The driver bound to a device, from the symlink sysfs leaves at device/driver.
_dev_driver() {
  local link
  # Two deliberate choices here.
  #
  # The -L test, because `readlink -f` on a path whose final component does not exist
  # still prints that path — so an unbound device, which is exactly the interesting
  # case, reported its driver as the literal string "driver".
  #
  # Plain `readlink` rather than `readlink -f`, because the link text already ends in
  # the driver name and resolving it requires the target to exist. That is true in real
  # sysfs and false in a fixture tree: git cannot store an empty directory, so a
  # checked-out fixture has the symlink but not the directory it points at, and -f
  # silently yields nothing.
  [ -L "$1/driver" ] || return 0
  link="$(readlink "$1/driver" 2>/dev/null)" || return 0
  [ -n "$link" ] || return 0
  link="${link%/}"
  printf '%s' "${link##*/}"
}

# A PCI ID as bare hex: sysfs writes them as 0x8086, pci.ids indexes them as 8086.
_dev_hex() {
  local v="$1"
  v="${v#0x}"
  printf '%s' "$v"
}

# --- graphics --------------------------------------------------------------

# One line per display adapter:  vendor|device|driver|kind
#
# kind is vga, 3d, or display. A laptop with switchable graphics reports the integrated
# adapter as vga and the discrete one as 3d, which is worth keeping: they are not two
# equal GPUs, and collapsing them would hide which one drives the panel.
detect_gpus() {
  local d class kind vendor device driver
  for d in "$DF_SYS_PCI"/*/; do
    class="$(_dev_read "$d/class")"
    case "$class" in
      0x0300*) kind=vga ;;
      0x0302*) kind=3d ;;
      0x0380*) kind=display ;;
      *) continue ;;
    esac
    vendor="$(_dev_hex "$(_dev_read "$d/vendor")")"
    device="$(_dev_hex "$(_dev_read "$d/device")")"
    driver="$(_dev_driver "$d")"
    printf '%s|%s|%s|%s\n' "$vendor" "$device" "$driver" "$kind"
  done
}

# --- network ---------------------------------------------------------------

# One line per physical interface:  name|kind|vendor|device|driver|state|speed_mbps
#
# Virtual interfaces are skipped by testing for a device symlink rather than by
# name-matching: docker0, br-*, tailscale0, veth*, and lo all lack one, and a blocklist
# of names would need extending for every new kind of virtual interface.
#
# The MAC address is never read. It is a durable, globally unique identifier for the
# machine, and this output is designed to be posted.
detect_nics() {
  local n name kind vendor device driver state speed
  for n in "$DF_SYS_NET"/*/; do
    name="${n%/}"
    name="${name##*/}"
    [ -e "$n/device" ] || continue

    if [ -d "$n/wireless" ] || [ -e "$n/phy80211" ]; then
      kind=wifi
    else
      kind=ethernet
    fi

    vendor="$(_dev_hex "$(_dev_read "$n/device/vendor")")"
    device="$(_dev_hex "$(_dev_read "$n/device/device")")"
    driver="$(_dev_driver "$n/device")"
    state="$(_dev_read "$n/operstate")"

    # speed is negotiated link rate in Mbit/s. It reads as -1 when the link is down and
    # is absent entirely on wireless, where there is no single negotiated rate.
    speed="$(_dev_read "$n/speed")"
    case "$speed" in
      '' | -*) speed="" ;;
    esac

    printf '%s|%s|%s|%s|%s|%s|%s\n' \
      "$name" "$kind" "$vendor" "$device" "$driver" "$state" "$speed"
  done
}

# --- USB -------------------------------------------------------------------

# One line per root hub:  bus|speed_mbps|version|ports
#
# A root hub is one controller's view of the bus, **not** a set of physical connectors.
# A single USB-C socket is usually wired to a USB 2.0 root hub and a USB 3.x one at the
# same time, so summing `maxchild` across buses over-counts the sockets on the chassis,
# often by double. The renderer says so rather than printing a port total.
detect_usb_buses() {
  local d bus speed version ports
  for d in "$DF_SYS_USB"/usb*/; do
    [ -d "$d" ] || continue
    bus="${d%/}"
    bus="${bus##*/}"
    speed="$(_dev_read "$d/speed")"
    version="$(_dev_read "$d/version")"
    # version is space-padded in sysfs: " 2.00".
    version="${version// /}"
    ports="$(_dev_read "$d/maxchild")"
    printf '%s|%s|%s|%s\n' "$bus" "$speed" "$version" "$ports"
  done
}

# Marketing name for a root hub's link speed, in Mbit/s. Named from the speed rather
# than from the `version` attribute because the version numbers are not a usable
# ordering: USB 3.2 Gen 1, Gen 2, and Gen 2x2 all report version 3.10 and differ only
# in speed, which is the thing anyone actually wants to know.
usb_speed_name() {
  case "$1" in
    1.5) printf 'USB 1.0 low speed' ;;
    12) printf 'USB 1.1 full speed' ;;
    480) printf 'USB 2.0' ;;
    5000) printf 'USB 3.2 Gen 1' ;;
    10000) printf 'USB 3.2 Gen 2' ;;
    20000) printf 'USB 3.2 Gen 2x2' ;;
    40000) printf 'USB4' ;;
    80000) printf 'USB4 v2' ;;
    '') return 0 ;;
    *) printf 'USB' ;;
  esac
}

# Mbit/s as the unit a person would use.
dev_speed_human() {
  local mbps="$1"
  case "$mbps" in
    '' | *[!0-9.]*) return 0 ;;
  esac
  case "$mbps" in
    *.*) printf '%s Mbps' "$mbps" ;;
    *)
      if [ "$mbps" -ge 1000 ]; then
        if [ $((mbps % 1000)) -eq 0 ]; then
          printf '%s Gbps' $((mbps / 1000))
        else
          printf '%s.%s Gbps' $((mbps / 1000)) $(((mbps % 1000) / 100))
        fi
      else
        printf '%s Mbps' "$mbps"
      fi
      ;;
  esac
}

# --- Thunderbolt / USB4 ----------------------------------------------------

# One line per domain:  domain|generation|security|iommu|vendor|device
#
# A domain is one Thunderbolt or USB4 controller. Nothing here counts *ports*: the
# mapping from domain to physical connector is board-specific and not exposed by the
# kernel, so a port count would be a guess dressed as a measurement. What can be stated
# is that the machine has Thunderbolt-capable hardware, of which generation, and under
# what security policy.
detect_thunderbolt() {
  local d domain gen security iommu vendor device router
  for d in "$DF_SYS_TBT"/domain*/; do
    [ -d "$d" ] || continue
    domain="${d%/}"
    domain="${domain##*/}"
    security="$(_dev_read "$d/security")"
    iommu="$(_dev_read "$d/iommu_dma_protection")"

    # The host router is the controller itself, numbered <domain>-0. Its generation is
    # what says Thunderbolt 3 versus 4, and the domain node does not carry it.
    router="$DF_SYS_TBT/${domain#domain}-0"
    gen="$(_dev_read "$router/generation")"
    vendor="$(_dev_read "$router/vendor_name")"
    device="$(_dev_read "$router/device_name")"

    printf '%s|%s|%s|%s|%s|%s\n' \
      "$domain" "$gen" "$security" "$iommu" "$vendor" "$device"
  done
}

# Devices plugged into a Thunderbolt domain, excluding the host routers themselves.
# One line per device:  id|vendor|device|authorized
detect_thunderbolt_devices() {
  local d id vendor device authorized
  for d in "$DF_SYS_TBT"/[0-9]*-[0-9]*/; do
    [ -d "$d" ] || continue
    id="${d%/}"
    id="${id##*/}"
    # <n>-0 is the host router, which is the controller, not something plugged in.
    case "$id" in
      *-0) continue ;;
    esac
    vendor="$(_dev_read "$d/vendor_name")"
    device="$(_dev_read "$d/device_name")"
    authorized="$(_dev_read "$d/authorized")"
    printf '%s|%s|%s|%s\n' "$id" "$vendor" "$device" "$authorized"
  done
}

# Thunderbolt generation as it is marketed, with the link rate people compare on.
tbt_generation_name() {
  case "$1" in
    1) printf 'Thunderbolt 1 (10 Gbps)' ;;
    2) printf 'Thunderbolt 2 (20 Gbps)' ;;
    3) printf 'Thunderbolt 3 (40 Gbps)' ;;
    4) printf 'Thunderbolt 4 / USB4 (40 Gbps)' ;;
    5) printf 'Thunderbolt 5 (80 Gbps)' ;;
    '') return 0 ;;
    *) printf 'Thunderbolt generation %s' "$1" ;;
  esac
}

# What the domain's security level means for a device someone plugs in. These are the
# kernel's `security` values; the wording matters because "none" reads as "no security
# feature present" when it actually means every device gets DMA on connect.
tbt_security_name() {
  case "$1" in
    none) printf 'none - devices connect with full PCIe access' ;;
    user) printf 'user - connections need approval' ;;
    secure) printf 'secure - approval plus device key' ;;
    dponly) printf 'dponly - DisplayPort only, no PCIe' ;;
    usbonly) printf 'usbonly - USB only, no PCIe' ;;
    nopcie) printf 'nopcie - PCIe tunnelling disabled' ;;
    '') return 0 ;;
    *) printf '%s' "$1" ;;
  esac
}
