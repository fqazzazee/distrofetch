#!/usr/bin/env bash
# Build synthetic sysfs trees for the device enumeration tests.
#
# The machines this runs on cannot cover the cases that matter. A CI runner is a VM
# with no display adapter, no Thunderbolt, and one virtio NIC; the developer laptop has
# integrated graphics and no discrete GPU. Neither can exercise switchable graphics, a
# down ethernet link, a USB4 bus, or an unauthorised Thunderbolt device — and those are
# exactly the branches worth testing.
#
# So the trees are written here instead. Every file mirrors a real sysfs attribute,
# including the quirks: `speed` reads -1 on a down link, `version` is space-padded,
# `driver` is a symlink rather than a file.
#
#   tests/fixtures/make-sysfs-fixtures.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/sysfs"
rm -rf "$root"

# --- PCI: switchable graphics, plus devices that must NOT be matched --------

pci="$root/pci"
mkdir -p "$pci"

mkpci() {
  local slot="$1" class="$2" vendor="$3" device="$4" driver="$5"
  mkdir -p "$pci/$slot"
  printf '%s\n' "$class" >"$pci/$slot/class"
  printf '%s\n' "$vendor" >"$pci/$slot/vendor"
  printf '%s\n' "$device" >"$pci/$slot/device"
  if [ -n "$driver" ]; then
    mkdir -p "$pci/drivers/$driver"
    ln -sfn "../drivers/$driver" "$pci/$slot/driver"
  fi
}

# Integrated adapter driving the panel.
mkpci 0000:00:02.0 0x030000 0x8086 0xa7a0 i915
# Discrete adapter, reported as a 3D controller rather than VGA.
mkpci 0000:01:00.0 0x030200 0x10de 0x2684 nvidia
# A display controller with no driver bound.
mkpci 0000:02:00.0 0x038000 0x1002 0x744c ''
# Neither of these is a display device and both must be skipped: an audio controller
# whose class starts 0x04, and a bridge whose class starts 0x06.
mkpci 0000:00:1f.3 0x040300 0x8086 0x51c8 snd_hda_intel
mkpci 0000:00:1c.0 0x060400 0x8086 0x7a38 pcieport

# --- network: real NICs alongside virtual interfaces -----------------------

net="$root/net"
mkdir -p "$net"

mkiface() {
  local name="$1" vendor="$2" device="$3" driver="$4" state="$5" speed="$6" wifi="$7"
  mkdir -p "$net/$name/device"
  printf '%s\n' "$state" >"$net/$name/operstate"
  printf '%s\n' "$speed" >"$net/$name/speed"
  printf '%s\n' "$vendor" >"$net/$name/device/vendor"
  printf '%s\n' "$device" >"$net/$name/device/device"
  # Never read, and present so a test can prove it stays unread.
  printf '%s\n' 'de:ad:be:ef:00:01' >"$net/$name/address"
  mkdir -p "$net/drivers/$driver"
  ln -sfn "../../drivers/$driver" "$net/$name/device/driver"
  [ "$wifi" = wifi ] && mkdir -p "$net/$name/wireless"
  return 0
}

mkiface eth0 0x8086 0x15fb e1000e up 1000 wired
mkiface eth1 0x14e4 0x1657 tg3 down -1 wired
mkiface wlan0 0x8086 0x51f1 iwlwifi up '' wifi

# Virtual interfaces: no device symlink, so they must not be enumerated. Named after
# the real ones that show up on a developer machine.
for v in lo docker0 br-df56d9872e83 tailscale0 veth0; do
  mkdir -p "$net/$v"
  printf 'unknown\n' >"$net/$v/operstate"
  printf '%s\n' 'de:ad:be:ef:00:99' >"$net/$v/address"
done

# --- USB: four buses across three speed classes ----------------------------

usb="$root/usb"
mkdir -p "$usb"

mkbus() {
  local name="$1" speed="$2" version="$3" ports="$4"
  mkdir -p "$usb/$name"
  printf '%s\n' "$speed" >"$usb/$name/speed"
  # sysfs space-pads this attribute, and the parser has to cope.
  printf ' %s\n' "$version" >"$usb/$name/version"
  printf '%s\n' "$ports" >"$usb/$name/maxchild"
}

mkbus usb1 480 2.00 1
mkbus usb2 480 2.00 12
mkbus usb3 20000 3.10 3
mkbus usb4 40000 3.20 4
# A connected device, not a root hub: must not be counted as a bus.
mkdir -p "$usb/1-1"
printf '480\n' >"$usb/1-1/speed"

# --- Thunderbolt: two domains, one attached device -------------------------

tbt="$root/thunderbolt"
mkdir -p "$tbt"

mkdomain() {
  local n="$1" security="$2" iommu="$3" generation="$4"
  mkdir -p "$tbt/domain$n" "$tbt/$n-0"
  printf '%s\n' "$security" >"$tbt/domain$n/security"
  printf '%s\n' "$iommu" >"$tbt/domain$n/iommu_dma_protection"
  printf '%s\n' "$generation" >"$tbt/$n-0/generation"
  printf 'INTEL\n' >"$tbt/$n-0/vendor_name"
  printf 'Gen12\n' >"$tbt/$n-0/device_name"
}

mkdomain 0 user 1 4
mkdomain 1 none 0 3

# An attached device on domain 0, not authorised.
mkdir -p "$tbt/0-1"
printf 'CalDigit\n' >"$tbt/0-1/vendor_name"
printf 'TS4\n' >"$tbt/0-1/device_name"
printf '0\n' >"$tbt/0-1/authorized"

printf 'sysfs fixtures written to %s\n' "$root"
