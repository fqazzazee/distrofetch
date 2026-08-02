#!/usr/bin/env bats
#
# The SMBIOS type-17 parser, against synthetic structures.
#
# The real tables are mode 0400, so this code path cannot run against the developer's
# own machine without root — and one machine's memory would prove very little anyway.
# tests/fixtures/dmi-entries holds hand-built records covering the cases that actually
# differ: the two size units, the 32-bit extended-size escape, an empty slot, firmware
# that knows nothing, and a stick with no manufacturer recorded.

setup() {
  DF_DMI_ENTRIES="$BATS_TEST_DIRNAME/fixtures/dmi-entries"
  DF_DMI_ID="$BATS_TEST_DIRNAME/fixtures/dmi-id"
  export DF_DMI_ENTRIES DF_DMI_ID
  # shellcheck source=../lib/dmi.sh
  . "$BATS_TEST_DIRNAME/../lib/dmi.sh"
}

@test "the fixtures are readable, so the rest of this file is meaningful" {
  run dmi_raw_readable
  [ "$status" -eq 0 ]
}

@test "every populated slot is reported and every empty one is skipped" {
  run dmi_dimms
  [ "$status" -eq 0 ]
  # Six records, four of them populated: one empty (size 0) and one unknown (0xFFFF).
  [ "${#lines[@]}" -eq 4 ]
}

@test "slot count includes the unpopulated slots" {
  run dmi_slot_count
  [ "$output" -eq 6 ]
}

@test "a megabyte-unit size is read as megabytes" {
  run dmi_dimms
  [[ "${lines[0]}" == 'DIMM 0|16384|DDR5|SODIMM|5600|5200|SK Hynix (HMCG78AGBSA095N)' ]]
}

# 0x7FFF in the 16-bit field is an escape meaning "read the 32-bit field instead".
# Treating it as a literal size reports every large module as 32 GB minus a megabyte.
@test "the 0x7FFF escape reads the 32-bit extended size" {
  run dmi_dimms
  [[ "${lines[1]}" == DIMM_A1'|'32768'|'DDR4'|'DIMM'|'* ]]
}

# Bit 15 set means the low bits are kilobytes. Misreading the flag turns 16 MiB into
# 16 GiB, which looks plausible enough to go unnoticed.
@test "the kilobyte unit flag is honoured" {
  run dmi_dimms
  [[ "${lines[2]}" == DIMM_B1'|'16'|'DDR3'|'* ]]
}

@test "a module whose speed is throttled reports both rated and configured" {
  run dmi_dimms
  # rated 5600, configured 5200
  [[ "${lines[0]}" == *'|5600|5200|'* ]]
}

@test "placeholder manufacturer and part strings are dropped, not printed" {
  run dmi_dimms
  # Fixture 17-5 has "Unknown" and "Not Specified" in those fields.
  [[ "${lines[3]}" == *'|' ]]
  [[ "${lines[3]}" != *Unknown* ]]
  [[ "${lines[3]}" != *'Not Specified'* ]]
}

# The output is designed to be screenshotted and posted publicly. A DIMM serial is a
# durable hardware identifier, so the parser must never read that offset at all.
@test "serial numbers never appear in the output" {
  run dmi_dimms
  [[ "$output" != *SERIAL-DO-NOT-PRINT* ]]
  [[ "$output" != *SER2* ]]
  [[ "$output" != *SER3* ]]
  [[ "$output" != *SER5* ]]
}

@test "an absent entries directory is reported, not crashed on" {
  DF_DMI_ENTRIES="$BATS_TEST_DIRNAME/fixtures/does-not-exist"
  run dmi_raw_readable
  [ "$status" -ne 0 ]
  run dmi_raw_reason
  [ "$status" -eq 0 ]
  [[ "$output" == *"no SMBIOS tables"* ]]
}

@test "placeholder firmware strings are filtered out of the id files" {
  run dmi_id board_vendor
  [ "$status" -eq 0 ]
  [ "$output" = "ExampleCorp" ]

  run dmi_id sys_vendor
  [ "$status" -eq 0 ]
  # The fixture holds "To Be Filled By O.E.M.", which is not a vendor name.
  [ -z "$output" ]
}

@test "a missing id file is empty rather than an error" {
  run dmi_id no_such_field
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
