#!/usr/bin/env bats
#
# CLI contract plus the detection probes. The probes assert shape, never content —
# this suite has to pass on Arch, Debian, and Fedora runners with different hardware.

setup() {
  DF="$BATS_TEST_DIRNAME/../bin/distrofetch"
  # shellcheck source=../lib/detect.sh
  . "$BATS_TEST_DIRNAME/../lib/detect.sh"
}

@test "--version prints a semver-looking string" {
  run "$DF" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--help mentions every documented flag" {
  run "$DF" --help
  [ "$status" -eq 0 ]
  for flag in --no-rain --no-color --duration --version --help; do
    [[ "$output" == *"$flag"* ]]
  done
}

@test "an unknown option exits 2 and explains itself on stderr" {
  run "$DF" --definitely-not-a-flag
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "--duration rejects a non-numeric value" {
  run "$DF" --duration soon
  [ "$status" -eq 2 ]
}

@test "--duration requires a value" {
  run "$DF" --duration
  [ "$status" -eq 2 ]
}

@test "the report runs clean and labels every field" {
  run "$DF" --no-color
  [ "$status" -eq 0 ]
  for label in OS: Kernel: Arch: Uptime: Packages: Shell: CPU: Memory:; do
    [[ "$output" == *"$label"* ]]
  done
}

@test "--no-color emits no ANSI escapes" {
  run "$DF" --no-color
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "detection probes each return exactly one non-empty line" {
  for probe in detect_os detect_kernel detect_arch detect_host \
    detect_shell detect_uptime detect_cpu detect_memory detect_packages; do
    run "$probe"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "${#lines[@]}" -eq 1 ]
  done
}

@test "memory reports as 'used / total' in GiB" {
  run detect_memory
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]\ GiB\ /\ [0-9]+\.[0-9]\ GiB$ ]] || [ "$output" = "unknown" ]
}
