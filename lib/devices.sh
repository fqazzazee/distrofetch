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
: "${DF_SYS_BLOCK:=/sys/block}"
: "${DF_SYS_EDAC:=/sys/devices/system/edac/mc}"

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
    [ -d "$d" ] || continue
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
  local n name kind vendor device driver state speed carrier

  for n in "$DF_SYS_NET"/*/; do
    # An unmatched glob is left literal by bash, so an empty or missing directory
    # would otherwise be reported as an interface named "*". The old device-symlink
    # test happened to filter it; nothing does now that virtual interfaces are kept.
    [ -d "$n" ] || continue
    name="${n%/}"
    name="${name##*/}"

    # -e follows the symlink and fails on a dangling one, which is what a device
    # mid-removal or an unbound driver leaves behind. -L catches those: the interface
    # is still hardware and still worth reporting.
    if [ -e "$n/device" ] || [ -L "$n/device" ]; then
      if [ -d "$n/wireless" ] || [ -e "$n/phy80211" ]; then
        kind=wifi
      else
        kind=ethernet
      fi
      vendor="$(_dev_hex "$(_dev_read "$n/device/vendor")")"
      device="$(_dev_hex "$(_dev_read "$n/device/device")")"
      driver="$(_dev_driver "$n/device")"
    else
      # No backing device: a bridge, tunnel, loopback, or container veth. Reported
      # rather than skipped — "why is my ethernet missing" is answered by seeing every
      # interface the kernel has, and a filtered list cannot answer it.
      kind="$(_dev_virtual_kind "$n" "$name")"
      vendor=""
      device=""
      driver=""
    fi

    state="$(_dev_read "$n/operstate")"

    # carrier is 1 with a cable in and 0 without. Reading it on a down interface
    # returns EINVAL, which is why a missing value means "not applicable" here and not
    # "no link".
    carrier="$(_dev_read "$n/carrier")"

    # speed is the negotiated link rate in Mbit/s. It reads as -1 when the link is down
    # and is absent on wireless, where there is no single negotiated rate.
    speed="$(_dev_read "$n/speed")"
    case "$speed" in
      '' | -*) speed="" ;;
    esac

    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$name" "$kind" "$vendor" "$device" "$driver" "$state" "$speed" "$carrier"
  done
}

# What kind of virtual interface this is, from the directories the kernel creates for
# each type. Name matching would need extending for every new kind; these do not.
_dev_virtual_kind() {
  local dir="$1" name="$2" type
  type="$(_dev_read "$dir/type")"
  [ "$type" = 772 ] && {
    printf 'loopback'
    return 0
  }
  [ -d "$dir/bridge" ] && {
    printf 'bridge'
    return 0
  }
  [ -d "$dir/bonding" ] && {
    printf 'bond'
    return 0
  }
  [ -e "$dir/tun_flags" ] && {
    printf 'tunnel'
    return 0
  }
  case "$name" in
    veth* | vnet*) printf 'veth' ;;
    wg*) printf 'wireguard' ;;
    *) printf 'virtual' ;;
  esac
}

# --- memory topology -------------------------------------------------------

# channels|controllers|slots from EDAC, or nothing.
#
# EDAC is the only unprivileged source for memory topology: SMBIOS carries it too, but
# behind mode 0400. Each memory controller exposes one directory per DIMM slot with a
# `dimm_location` reading "channel 0 slot 1", so counting distinct controller/channel
# pairs gives the channel count without any privilege at all.
#
# The count is of channels the controllers expose, not of channels populated — on a
# soldered LPDDR5 machine those are the same thing, and on a socketed board an empty
# channel is still a channel the board has.
detect_memory_channels() {
  local mc d location chan controllers=0 slots=0 seen=""
  local channels=0

  [ -d "$DF_SYS_EDAC" ] || return 0

  for mc in "$DF_SYS_EDAC"/mc[0-9]*/; do
    [ -d "$mc" ] || continue
    controllers=$((controllers + 1))
    for d in "$mc"dimm[0-9]*/; do
      [ -d "$d" ] || continue
      slots=$((slots + 1))
      location="$(_dev_read "$d/dimm_location")"
      # "channel 0 slot 1" -> 0. Anything else is left alone and simply not counted.
      case "$location" in
        channel\ *)
          chan="${location#channel }"
          chan="${chan%% *}"
          # A channel is only distinct within its own controller.
          case " $seen " in
            *" ${mc}:${chan} "*) ;;
            *)
              seen="$seen ${mc}:${chan}"
              channels=$((channels + 1))
              ;;
          esac
          ;;
      esac
    done
  done

  [ "$controllers" -gt 0 ] || return 0
  printf '%s|%s|%s' "$channels" "$controllers" "$slots"
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

# --- PCIe links ------------------------------------------------------------

# PCIe generation from the link speed sysfs reports, which is a transfer rate string
# like "16.0 GT/s PCIe". The rate is what the hardware negotiates; the generation is
# what the rate is called, and is the number on the box.
pcie_gen_from_speed() {
  local speed="${1%% *}"
  case "$speed" in
    2.5) printf '1.0' ;;
    5.0 | 5) printf '2.0' ;;
    8.0 | 8) printf '3.0' ;;
    16.0 | 16) printf '4.0' ;;
    32.0 | 32) printf '5.0' ;;
    64.0 | 64) printf '6.0' ;;
    *) return 0 ;;
  esac
}

# "PCIe 4.0 x4", or "PCIe 4.0 x4 (of 4.0 x4)" when the device is running below what it
# and the slot are both capable of — an NVMe drive in the wrong slot is a common and
# invisible performance problem, and the two numbers side by side are what reveal it.
#
# Reads the standard PCI link attributes, so this works for any PCI device: the NVMe
# controller behind a namespace, a network card, a GPU.
pcie_link() {
  local dir="$1" cur_speed max_speed cur_width max_width cur_gen max_gen out=""
  cur_speed="$(_dev_read "$dir/current_link_speed")"
  max_speed="$(_dev_read "$dir/max_link_speed")"
  cur_width="$(_dev_read "$dir/current_link_width")"
  max_width="$(_dev_read "$dir/max_link_width")"

  cur_gen="$(pcie_gen_from_speed "$cur_speed")"
  max_gen="$(pcie_gen_from_speed "$max_speed")"
  [ -n "$cur_gen" ] || return 0

  # "PCIe Gen 4 x4 (4 lanes)" rather than "PCIe 4.0 x4": the generation is what a drive
  # is sold as, and the lane count is the other half of the bandwidth that people are
  # usually trying to find out.
  out="PCIe Gen ${cur_gen%%.*}"
  case "$cur_width" in
    '' | 0 | *[!0-9]*) ;;
    *) out="$out x$cur_width ($cur_width lane$([ "$cur_width" = 1 ] || printf s))" ;;
  esac

  # Only mention the maximum when it differs, so the common case stays short.
  if [ -n "$max_gen" ] && { [ "$max_gen" != "$cur_gen" ] || [ "$max_width" != "$cur_width" ]; }; then
    case "$max_width" in
      '' | 0 | 255 | *[!0-9]*) out="$out, capable of Gen ${max_gen%%.*}" ;;
      *) out="$out, capable of Gen ${max_gen%%.*} x$max_width" ;;
    esac
  fi
  printf '%s' "$out"
}

# --- storage ---------------------------------------------------------------

# One line per whole disk:  name|size_sectors|rotational|model|transport|pcie
#
# Only real disks. loop, ram, zram, device-mapper, and optical devices are skipped:
# they are either not hardware or not something with a capacity worth reporting, and a
# machine with twenty snap mounts would otherwise print twenty loop devices.
#
# The serial number at device/serial is never read, for the same reason a DIMM serial
# is not: it is a durable identifier and this output is designed to be posted.
detect_disks() {
  local b name size rot model transport pcie devdir
  for b in "$DF_SYS_BLOCK"/*/; do
    [ -d "$b" ] || continue
    name="${b%/}"
    name="${name##*/}"
    case "$name" in
      loop* | ram* | zram* | dm-* | sr* | md* | fd*) continue ;;
    esac

    size="$(_dev_read "$b/size")"
    rot="$(_dev_read "$b/queue/rotational")"
    model="$(_dev_read "$b/device/model")"
    # sysfs pads the SCSI model field to a fixed width.
    model="${model%"${model##*[![:space:]]}"}"

    transport=""
    pcie=""
    case "$name" in
      nvme*)
        transport=nvme
        # /sys/block/nvme0n1/device is the controller; its own device is the PCI
        # function that carries the link attributes.
        devdir="$b/device/device"
        [ -d "$devdir" ] && pcie="$(pcie_link "$devdir")"
        [ -n "$model" ] || model="$(_dev_read "$b/device/model")"
        ;;
      mmcblk*) transport=mmc ;;
      *)
        if [ -e "$b/device" ]; then
          transport=sata
        fi
        ;;
    esac

    printf '%s|%s|%s|%s|%s|%s\n' \
      "$name" "$size" "$rot" "$model" "$transport" "$pcie"
  done
}

# 512-byte sectors as the capacity printed on the drive. Decimal units, deliberately:
# a "1 TB" drive is 1000 GB to its manufacturer and 931 GiB to the kernel, and the
# number someone can match against the label is the useful one.
disk_size_human() {
  local sectors="$1" bytes
  case "$sectors" in
    '' | 0 | *[!0-9]*) return 0 ;;
  esac
  bytes=$((sectors * 512))
  if [ "$bytes" -ge 1000000000000 ]; then
    printf '%s.%s TB' $((bytes / 1000000000000)) $(((bytes % 1000000000000) / 100000000000))
  elif [ "$bytes" -ge 1000000000 ]; then
    printf '%s GB' $((bytes / 1000000000))
  else
    printf '%s MB' $((bytes / 1000000))
  fi
}

# --- link classification from device names ---------------------------------
#
# Neither of these facts is in sysfs, and the tools that would report them need
# privilege: ethtool's link-settings ioctl returns EPERM to an unprivileged caller, and
# `iw phy info` is a separate dependency. What *is* available is the device name from
# pci.ids, which frequently carries the answer, because vendors put it there.
#
# So these read a label rather than measuring anything, and say nothing when the label
# says nothing. A blank is a gap; a guessed Wi-Fi generation is a wrong fact about
# someone's hardware.

# "Wi-Fi 7", "Wi-Fi 6E", "Wi-Fi 6", "Wi-Fi 5", or nothing.
#
# pci.ids names discrete parts with the generation — "Wi-Fi 6E(802.11ax) AX210",
# "MT7925 (RZ717) Wi-Fi 7 160MHz" — so matching the marketing name covers them. The
# 802.11 revision is the fallback for names that carry it instead.
wifi_generation() {
  local name="$1"
  case "$name" in
    *'Wi-Fi 7'* | *'WiFi 7'* | *802.11be*) printf 'Wi-Fi 7 (802.11be)' ;;
    *'Wi-Fi 6E'* | *'WiFi 6E'*) printf 'Wi-Fi 6E (802.11ax, 6 GHz)' ;;
    *'Wi-Fi 6'* | *'WiFi 6'* | *802.11ax*) printf 'Wi-Fi 6 (802.11ax)' ;;
    *'Wi-Fi 5'* | *'WiFi 5'* | *802.11ac*) printf 'Wi-Fi 5 (802.11ac)' ;;
    *'Wi-Fi 4'* | *802.11n*) printf 'Wi-Fi 4 (802.11n)' ;;
    *) return 0 ;;
  esac
}

# Whether this is an Intel CNVi part, where the generation is genuinely not knowable
# from the PCI ID.
#
# CNVi splits the wireless MAC — which lives in the PCH and is what the PCI ID names —
# from the RF module, a separate M.2 part that is what actually determines whether the
# link is Wi-Fi 6 or 6E. Two machines reporting the same PCI ID can have different
# wireless generations. Reporting a generation here would be a guess, so instead the
# panel explains why there is not one.
wifi_is_cnvi() {
  case "$1" in
    *CNVi* | *cnvi*) return 0 ;;
    *) return 1 ;;
  esac
}

# The rated line speed a wired NIC's name claims, or nothing. This is the ceiling the
# hardware is sold as; `speed` in sysfs is what the link actually negotiated, and the
# gap between them is a cable or a switch port.
ethernet_rated_speed() {
  local name="$1"
  case "$name" in
    *100GbE* | *100-Gigabit* | *'100 Gigabit'*) printf '100 Gbps' ;;
    *40GbE* | *40-Gigabit* | *'40 Gigabit'*) printf '40 Gbps' ;;
    *25GbE* | *25-Gigabit* | *'25 Gigabit'*) printf '25 Gbps' ;;
    *10GbE* | *10-Gigabit* | *'10 Gigabit'* | *X550* | *X540* | *X520*) printf '10 Gbps' ;;
    # 2.5 before 5: *5GbE* also matches "2.5GbE", and a 2.5 GbE NIC reported as
    # 5 Gbps is a wrong fact rather than a missing one.
    *2.5GbE* | *2.5G* | *'2.5 Gigabit'* | *I225* | *I226*) printf '2.5 Gbps' ;;
    *5GbE* | *'5 Gigabit'*) printf '5 Gbps' ;;
    *Gigabit* | *GbE*) printf '1 Gbps' ;;
    *'Fast Ethernet'* | *100BaseTX*) printf '100 Mbps' ;;
    *) return 0 ;;
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
