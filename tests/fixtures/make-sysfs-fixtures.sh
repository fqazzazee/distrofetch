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
    # Only the symlink, not the directory it names. git cannot store an empty
    # directory, so anything that has to survive a checkout must be a file or a link.
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
  ln -sfn "../../drivers/$driver" "$net/$name/device/driver"
  # A file inside, not just the directory: an empty `wireless/` would not survive a
  # git checkout and every wireless interface would come back as ethernet.
  if [ "$wifi" = wifi ]; then
    mkdir -p "$net/$name/wireless"
    printf '0000   0   0   0    0     0      0      0      0        0\n' \
      >"$net/$name/wireless/status"
  fi
  return 0
}

mkiface eth0 0x8086 0x15fb e1000e up 1000 wired
mkiface eth1 0x14e4 0x1657 tg3 down -1 wired
mkiface wlan0 0x8086 0x51f1 iwlwifi up '' wifi

# Virtual interfaces: no device symlink, so they must not be enumerated. Named after
# the real ones that show up on a developer machine.
# Each kind is identified by the directories the kernel creates for it, not by name,
# so the fixture has to create those directories for the classification to be exercised.
mkvirtual() {
  local name="$1" type="$2" marker="$3"
  mkdir -p "$net/$name"
  printf 'unknown\n' >"$net/$name/operstate"
  printf '%s\n' "$type" >"$net/$name/type"
  printf '%s\n' 'de:ad:be:ef:00:99' >"$net/$name/address"
  case "$marker" in
    '') ;;
    tun_flags) printf '0x0001\n' >"$net/$name/tun_flags" ;;
    *)
      mkdir -p "$net/$name/$marker"
      printf '0\n' >"$net/$name/$marker/stp_state"
      ;;
  esac
}

mkvirtual lo 772 ''
mkvirtual docker0 1 bridge
mkvirtual br-df56d9872e83 1 bridge
mkvirtual tailscale0 65534 tun_flags
mkvirtual veth0 1 ''

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

# --- block devices: NVMe with a PCIe link, SATA SSD, spinning disk ----------

block="$root/block"
mkdir -p "$block"

mkdisk() {
  local name="$1" sectors="$2" rot="$3" model="$4"
  mkdir -p "$block/$name/queue" "$block/$name/device"
  printf '%s\n' "$sectors" >"$block/$name/size"
  printf '%s\n' "$rot" >"$block/$name/queue/rotational"
  # sysfs pads the SCSI model field to a fixed width, and the parser has to trim it.
  printf '%-40s\n' "$model" >"$block/$name/device/model"
  # Never read, and present so a test can prove it stays unread.
  printf 'SERIAL-DO-NOT-PRINT\n' >"$block/$name/device/serial"
}

# NVMe: the PCIe link lives two levels down, on the controller's own PCI function.
mkdisk nvme0n1 2000409264 0 'WD PC SN560 SDDPNQE-1T00-1102'
mkdir -p "$block/nvme0n1/device/device"
printf '16.0 GT/s PCIe\n' >"$block/nvme0n1/device/device/current_link_speed"
printf '16.0 GT/s PCIe\n' >"$block/nvme0n1/device/device/max_link_speed"
printf '4\n' >"$block/nvme0n1/device/device/current_link_width"
printf '4\n' >"$block/nvme0n1/device/device/max_link_width"

# A Gen4 drive negotiated down to Gen3 x2 — the case worth surfacing, since nothing
# else on the system says the drive is in the wrong slot.
mkdisk nvme1n1 4000797360 0 'Samsung SSD 990 PRO 2TB'
mkdir -p "$block/nvme1n1/device/device"
printf '8.0 GT/s PCIe\n' >"$block/nvme1n1/device/device/current_link_speed"
printf '16.0 GT/s PCIe\n' >"$block/nvme1n1/device/device/max_link_speed"
printf '2\n' >"$block/nvme1n1/device/device/current_link_width"
printf '4\n' >"$block/nvme1n1/device/device/max_link_width"

mkdisk sda 500118192 0 'Samsung SSD 860 EVO 250GB'
mkdisk sdb 7814037168 1 'ST4000DM004-2CV104'

# None of these is a disk and all must be skipped.
for junk in loop0 loop7 ram0 zram0 dm-0 sr0; do
  mkdir -p "$block/$junk/queue"
  printf '0\n' >"$block/$junk/size"
  printf '0\n' >"$block/$junk/queue/rotational"
done

# --- EDAC: two controllers, two channels each, four slots apiece -----------

edac="$root/edac"
mkdir -p "$edac"
for mc in 0 1; do
  for d in 0 1 2 3; do
    mkdir -p "$edac/mc$mc/dimm$d"
    printf 'channel %s slot %s\n' $((d / 2)) $((d % 2)) \
      >"$edac/mc$mc/dimm$d/dimm_location"
    printf 'MC#%s_Chan#%s_DIMM#%s\n' "$mc" $((d / 2)) $((d % 2)) \
      >"$edac/mc$mc/dimm$d/dimm_label"
    printf '2048\n' >"$edac/mc$mc/dimm$d/size"
  done
done

printf 'sysfs fixtures written to %s\n' "$root"
