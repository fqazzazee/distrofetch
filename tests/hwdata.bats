#!/usr/bin/env bats
#
# Lookups against the bundled reference tables.
#
# These assert the lookup *rules* — version fallback, rolling releases, the live
# SUPPORT_END field winning over the table, a miss producing nothing — rather than the
# table's contents. Asserting that Debian 12 goes EOL on a particular date would turn
# every data refresh into a test failure, which is how a table stops being refreshed.

setup() {
  DISTROFETCH_DATA="$BATS_TEST_DIRNAME/../lib/data"
  DISTROFETCH_LOGOS="$BATS_TEST_DIRNAME/../lib/logos"
  export DISTROFETCH_DATA DISTROFETCH_LOGOS
  # shellcheck source=../lib/hwdata.sh
  . "$BATS_TEST_DIRNAME/../lib/hwdata.sh"
}

# --- version matching ------------------------------------------------------

@test "an exact version matches its row" {
  run hwdata_distro_row debian 12
  [ "$status" -eq 0 ]
  [[ "$output" == debian*bookworm* ]]
}

# Rocky reports 9.8 where the table knows about point releases only sometimes; Alpine
# reports 3.24.1 where the table knows 3.22. Dropping a dotted component at a time is
# what lets one row cover a whole series.
@test "a more specific version falls back to a less specific row" {
  run hwdata_distro_row ubuntu 24.04.2
  [ "$status" -eq 0 ]
  [[ "$output" == ubuntu*noble* ]]
}

@test "a rolling distro matches the wildcard row at any version" {
  run hwdata_distro_row arch 20260726.0.562117
  [ "$status" -eq 0 ]
  [[ "$output" == arch*rolling* ]]
}

@test "an unknown distro yields nothing rather than a wrong row" {
  run hwdata_distro_row not-a-distro 1.0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unknown version of a known fixed-release distro yields nothing" {
  run hwdata_distro_row debian 99
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- support status --------------------------------------------------------

@test "a rolling release is reported as having no end of life" {
  run hwdata_distro_support arch 20260726.0.562117
  [ "$status" -eq 0 ]
  [[ "$output" == *"rolling release"* ]]
  run hwdata_distro_support_level arch 20260726.0.562117
  [ "$output" = ok ]
}

@test "a release past its end of life says so" {
  run hwdata_distro_support debian 10
  [ "$status" -eq 0 ]
  [[ "$output" == "END OF LIFE since"* ]]
  run hwdata_distro_support_level debian 10
  [ "$output" = dead ]
}

@test "a supported release reports its remaining days" {
  run hwdata_distro_support ubuntu 24.04
  [ "$status" -eq 0 ]
  [[ "$output" == "supported until"*"days)" ]]
  run hwdata_distro_support_level ubuntu 24.04
  [ "$output" = ok ]
}

@test "an unknown distro reports no support status rather than guessing" {
  run hwdata_distro_support not-a-distro 1.0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Fixed ISO dates rather than "tomorrow": busybox date(1) accepts the former and not
# the latter, and this suite runs on Alpine. That difference is not incidental — it is
# exactly why hwdata_days_until returns nothing instead of trusting date(1) blindly.
@test "day arithmetic is signed around today" {
  if ! date -d 2030-01-01 +%s >/dev/null 2>&1; then
    skip "date(1) here has no usable -d; hwdata_days_until degrades to an empty count"
  fi
  run hwdata_days_until 2099-01-01
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]

  run hwdata_days_until 2000-01-01
  [ "$status" -eq 0 ]
  [ "$output" -lt 0 ]
}

@test "an unparseable date yields nothing rather than a bogus count" {
  run hwdata_days_until "not-a-date"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run hwdata_days_until '-'
  [ -z "$output" ]
}

# --- CPU table -------------------------------------------------------------

@test "a known family/model resolves to a microarchitecture" {
  run hwdata_cpu_arch GenuineIntel 6 186
  [ "$status" -eq 0 ]
  [[ "$output" == "Raptor Lake|2023|Intel 7" ]]
}

@test "an unknown model falls back to the family wildcard where one exists" {
  run hwdata_cpu_arch AuthenticAMD 26 255
  [ "$status" -eq 0 ]
  [[ "$output" == "Zen 5|"* ]]
}

# Intel has no wildcard row: the families span too many microarchitectures for a
# family-wide answer to be true. An unknown Intel model must produce nothing.
@test "an unknown model with no family wildcard yields nothing" {
  run hwdata_cpu_arch GenuineIntel 6 253
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unknown vendor yields nothing" {
  run hwdata_cpu_arch SomeOtherVendor 6 186
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- logo resolution -------------------------------------------------------

@test "a distro with its own logo file uses it" {
  run hwdata_logo_name fedora ""
  [ "$output" = fedora ]
}

@test "a derivative borrows its parent's logo via ID_LIKE" {
  run hwdata_logo_name garuda "arch"
  [ "$output" = arch ]
}

@test "ID_LIKE is searched nearest relative first" {
  run hwdata_logo_name someremix "notadistro ubuntu debian"
  [ "$output" = ubuntu ]
}

@test "an unrecognised distro falls back to the generic logo" {
  run hwdata_logo_name totally-unknown ""
  [ "$output" = tux ]
}

@test "opensuse variants collapse onto one logo" {
  run hwdata_logo_name opensuse-tumbleweed ""
  [ "$output" = opensuse ]
  run hwdata_logo_name opensuse-leap ""
  [ "$output" = opensuse ]
}

@test "every name the alias table can return has a logo file behind it" {
  local name
  for name in opensuse pop linuxmint rhel almalinux rocky centos endeavouros \
    manjaro elementary tux; do
    [ -r "$DISTROFETCH_LOGOS/$name.txt" ]
  done
}
