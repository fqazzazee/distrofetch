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
  export DF_SYS_PCI DF_SYS_NET DF_SYS_USB DF_SYS_TBT
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
