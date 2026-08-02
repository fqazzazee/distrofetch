#!/usr/bin/env bats
#
# Device enumeration, against synthetic sysfs trees.
#
# Neither the developer machine nor a CI runner can cover what matters here: the runners
# are VMs with no display adapter, no Thunderbolt, and one virtio NIC, and the laptop has
# integrated graphics only. Switchable graphics, a down ethernet link, an unbound driver,
# a USB4 bus, and an unauthorised Thunderbolt device all live in
# tests/fixtures/sysfs, built by make-sysfs-fixtures.sh.

setup() {
  ROOT="$BATS_TEST_DIRNAME/fixtures/sysfs"
  DF_SYS_PCI="$ROOT/pci"
  DF_SYS_NET="$ROOT/net"
  DF_SYS_USB="$ROOT/usb"
  DF_SYS_TBT="$ROOT/thunderbolt"
  DF_SYS_BLOCK="$ROOT/block"
  export DF_SYS_PCI DF_SYS_NET DF_SYS_USB DF_SYS_TBT DF_SYS_BLOCK
  # shellcheck source=../lib/devices.sh
  . "$BATS_TEST_DIRNAME/../lib/devices.sh"
}

# --- graphics --------------------------------------------------------------

@test "every display-class device is found and nothing else is" {
  run detect_gpus
  [ "$status" -eq 0 ]
  # Three display devices; the audio controller and the PCIe bridge must not appear.
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" != *51c8* ]]
  [[ "$output" != *7a38* ]]
}

# A laptop with switchable graphics reports the panel-driving adapter as VGA and the
# discrete one as a 3D controller. Collapsing them would hide which is which.
@test "VGA, 3D, and display controllers are distinguished" {
  run detect_gpus
  [[ "${lines[0]}" == '8086|a7a0|i915|vga' ]]
  [[ "${lines[1]}" == '10de|2684|nvidia|3d' ]]
  [[ "${lines[2]}" == '1002|744c||display' ]]
}

# `readlink -f` prints a path whose final component does not exist, so without an
# explicit symlink test an unbound device reports its driver as the string "driver".
@test "a device with no driver bound reports an empty driver, not a bogus one" {
  run detect_gpus
  [[ "${lines[2]}" == *'|744c||display' ]]
  [[ "$output" != *'|driver|'* ]]
}

# --- network ---------------------------------------------------------------

@test "only interfaces backed by hardware are enumerated" {
  run detect_nics
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  for virtual in lo docker0 br-df56d9872e83 tailscale0 veth0; do
    [[ "$output" != *"$virtual"* ]]
  done
}

@test "wireless interfaces are distinguished from ethernet" {
  run detect_nics
  [[ "$output" == *'eth0|ethernet|'* ]]
  [[ "$output" == *'wlan0|wifi|'* ]]
}

# sysfs reports -1 for the negotiated rate of a down link. Printing that as a speed
# would be worse than printing nothing.
@test "a down link reports no speed rather than -1" {
  run detect_nics
  [[ "${lines[0]}" == 'eth0|ethernet|8086|15fb|e1000e|up|1000' ]]
  [[ "${lines[1]}" == 'eth1|ethernet|14e4|1657|tg3|down|' ]]
}

@test "wireless reports no speed, since there is no single negotiated rate" {
  run detect_nics
  [[ "${lines[2]}" == *'|wlan0'* || "${lines[2]}" == 'wlan0|'* ]]
  [[ "${lines[2]}" == *'|up|' ]]
}

# The MAC address is a durable, globally unique identifier for the machine, and this
# output is designed to be posted. The fixtures carry one so this can be proven.
@test "MAC addresses never appear in the output" {
  run detect_nics
  [[ "$output" != *de:ad:be:ef* ]]
}

# --- USB -------------------------------------------------------------------

@test "root hubs are enumerated and attached devices are not" {
  run detect_usb_buses
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  # 1-1 is a device plugged into bus 1, not a bus.
  [[ "$output" != *'1-1|'* ]]
}

# sysfs space-pads this attribute — it reads " 2.00", not "2.00".
@test "the space-padded version attribute is trimmed" {
  run detect_usb_buses
  [[ "${lines[0]}" == 'usb1|480|2.00|1' ]]
  [[ "$output" != *'| 2.00|'* ]]
}

# USB 3.2 Gen 1, Gen 2, and Gen 2x2 all report version 3.10 and differ only in speed,
# so the marketing name has to come from the speed.
@test "speed classes are named from the link rate, not the version" {
  run usb_speed_name 480
  [ "$output" = 'USB 2.0' ]
  run usb_speed_name 5000
  [ "$output" = 'USB 3.2 Gen 1' ]
  run usb_speed_name 10000
  [ "$output" = 'USB 3.2 Gen 2' ]
  run usb_speed_name 20000
  [ "$output" = 'USB 3.2 Gen 2x2' ]
  run usb_speed_name 40000
  [ "$output" = 'USB4' ]
}

@test "an unrecognised speed still names the bus" {
  run usb_speed_name 999999
  [ "$output" = 'USB' ]
  run usb_speed_name ''
  [ -z "$output" ]
}

@test "link rates render in the unit a person would use" {
  run dev_speed_human 480
  [ "$output" = '480 Mbps' ]
  run dev_speed_human 1000
  [ "$output" = '1 Gbps' ]
  run dev_speed_human 2500
  [ "$output" = '2.5 Gbps' ]
  run dev_speed_human 40000
  [ "$output" = '40 Gbps' ]
  run dev_speed_human ''
  [ -z "$output" ]
  run dev_speed_human 'not-a-number'
  [ -z "$output" ]
}

# --- storage ---------------------------------------------------------------

@test "whole disks are enumerated and pseudo-devices are not" {
  run detect_disks
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  for junk in loop0 loop7 ram0 zram0 dm-0 sr0; do
    [[ "$output" != *"$junk"* ]]
  done
}

@test "rotational distinguishes an SSD from a spinning disk" {
  run detect_disks
  # sda is rotational=0, sdb is rotational=1.
  [[ "${lines[2]}" == 'sda|500118192|0|'* ]]
  [[ "${lines[3]}" == 'sdb|7814037168|1|'* ]]
}

@test "the padded model field is trimmed" {
  run detect_disks
  [[ "${lines[0]}" == *'|WD PC SN560 SDDPNQE-1T00-1102|nvme|'* ]]
  [[ "$output" != *'  |'* ]]
}

@test "an NVMe drive reports its PCIe link" {
  run detect_disks
  [[ "${lines[0]}" == *'|PCIe 4.0 x4' ]]
}

# A Gen4 drive in a Gen3 slot runs at half speed and nothing else on the system says
# so, which is the whole reason both numbers are reported.
@test "a link running below its maximum reports both" {
  run detect_disks
  [[ "${lines[1]}" == *'|PCIe 3.0 x2 (max 4.0 x4)' ]]
}

@test "a SATA disk has no PCIe link to report" {
  run detect_disks
  [[ "${lines[2]}" == *'|sata|' ]]
}

# The output is designed to be screenshotted, and a drive serial is a durable
# identifier. The fixtures carry one so this can be proven.
@test "disk serial numbers never appear" {
  run detect_disks
  [[ "$output" != *SERIAL-DO-NOT-PRINT* ]]
}

@test "PCIe generations map from the negotiated transfer rate" {
  run pcie_gen_from_speed '2.5 GT/s PCIe'
  [ "$output" = '1.0' ]
  run pcie_gen_from_speed '8.0 GT/s PCIe'
  [ "$output" = '3.0' ]
  run pcie_gen_from_speed '16.0 GT/s PCIe'
  [ "$output" = '4.0' ]
  run pcie_gen_from_speed '32.0 GT/s PCIe'
  [ "$output" = '5.0' ]
  run pcie_gen_from_speed 'Unknown'
  [ -z "$output" ]
}

# Manufacturers sell drives in decimal units. 2000409264 sectors is 1.02 TB decimal and
# 953 GiB binary; the number someone can match against the label is the useful one.
@test "capacity is reported in the units printed on the drive" {
  run disk_size_human 2000409264
  [ "$output" = '1.0 TB' ]
  run disk_size_human 500118192
  [ "$output" = '256 GB' ]
  run disk_size_human 0
  [ -z "$output" ]
  run disk_size_human 'not-a-number'
  [ -z "$output" ]
}

# --- link classification ---------------------------------------------------

# pci.ids names discrete wireless parts with their generation, which is the only
# unprivileged source: sysfs has no capability attributes and ethtool needs privilege.
@test "Wi-Fi generation is read from the device name" {
  run wifi_generation 'Wi-Fi 7(802.11be) AX1775*/BE401 2x2'
  [[ "$output" == 'Wi-Fi 7'* ]]
  run wifi_generation 'Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak]'
  [[ "$output" == 'Wi-Fi 6E'* ]]
  run wifi_generation 'Wi-Fi 6 AX200'
  [[ "$output" == 'Wi-Fi 6 '* ]]
  run wifi_generation 'Wi-Fi 5(802.11ac) Wireless-AC 9x6x'
  [[ "$output" == 'Wi-Fi 5'* ]]
}

@test "a name with no generation marker yields nothing" {
  run wifi_generation 'Wireless 8265 / 8275'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# CNVi splits the wireless MAC (in the PCH, which the PCI ID names) from the RF module
# that actually sets the generation. Two machines with this ID can differ, so there is
# no answer to give and the panel says why rather than guessing.
@test "CNVi parts are identified as unanswerable rather than guessed" {
  run wifi_is_cnvi 'Raptor Lake PCH CNVi WiFi'
  [ "$status" -eq 0 ]
  run wifi_is_cnvi 'Wi-Fi 6 AX200'
  [ "$status" -ne 0 ]
  run wifi_generation 'Raptor Lake PCH CNVi WiFi'
  [ -z "$output" ]
}

@test "ethernet rated speed is read from the device name" {
  run ethernet_rated_speed '82574L Gigabit Network Connection'
  [ "$output" = '1 Gbps' ]
  run ethernet_rated_speed 'Ethernet Controller X550'
  [ "$output" = '10 Gbps' ]
  run ethernet_rated_speed 'FastLinQ QL45000 Series 25GbE Controller'
  [ "$output" = '25 Gbps' ]
  run ethernet_rated_speed 'Some Unlabelled NIC'
  [ -z "$output" ]
}

# *5GbE* also matches "2.5GbE", so pattern order decides whether a 2.5 GbE card is
# reported at twice its speed.
@test "2.5GbE is not mistaken for 5GbE" {
  run ethernet_rated_speed 'Ethernet Controller I225-V'
  [ "$output" = '2.5 Gbps' ]
  run ethernet_rated_speed '2.5GbE Controller'
  [ "$output" = '2.5 Gbps' ]
  run ethernet_rated_speed 'AQC111 5GbE'
  [ "$output" = '5 Gbps' ]
}

# --- Thunderbolt -----------------------------------------------------------

@test "each domain is reported with the generation from its host router" {
  run detect_thunderbolt
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  # The generation lives on the <n>-0 router, not on the domain node.
  [[ "${lines[0]}" == 'domain0|4|user|1|INTEL|Gen12' ]]
  [[ "${lines[1]}" == 'domain1|3|none|0|INTEL|Gen12' ]]
}

@test "attached devices are listed and host routers are not" {
  run detect_thunderbolt_devices
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == '0-1|CalDigit|TS4|0' ]]
  # 0-0 and 1-0 are the controllers themselves.
  [[ "$output" != *'0-0|'* ]]
  [[ "$output" != *'1-0|'* ]]
}

@test "generations are named with the rate people compare on" {
  run tbt_generation_name 3
  [[ "$output" == 'Thunderbolt 3 (40 Gbps)' ]]
  run tbt_generation_name 4
  [[ "$output" == 'Thunderbolt 4 / USB4 (40 Gbps)' ]]
  run tbt_generation_name ''
  [ -z "$output" ]
  run tbt_generation_name 9
  [[ "$output" == *'generation 9'* ]]
}

# "none" is the dangerous value and reads as "no security feature", so it is spelled
# out rather than printed bare.
@test "the security level is explained, not just echoed" {
  run tbt_security_name none
  [[ "$output" == *'full PCIe access'* ]]
  run tbt_security_name user
  [[ "$output" == *'approval'* ]]
  run tbt_security_name ''
  [ -z "$output" ]
}

# --- absent hardware -------------------------------------------------------
#
# A machine with none of this is the normal case in a container, and is a different
# answer from "there is some and I could not identify it".

@test "empty trees produce no output rather than an error" {
  local empty="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty"
  DF_SYS_PCI="$empty" run detect_gpus
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  DF_SYS_NET="$empty" run detect_nics
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  DF_SYS_USB="$empty" run detect_usb_buses
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  DF_SYS_TBT="$empty" run detect_thunderbolt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing trees produce no output rather than an error" {
  DF_SYS_PCI=/nonexistent run detect_gpus
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  DF_SYS_TBT=/nonexistent run detect_thunderbolt
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
