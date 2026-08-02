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

@test "--duration 0 is accepted and prints the report" {
  run "$DF" --duration 0 --no-color
  [ "$status" -eq 0 ]
  [[ "$output" == *"OS:"* ]]
}

@test "the help text documents 0 as the default duration" {
  run "$DF" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"default: 0"* ]]
}

# A non-zero duration must still be inert off a terminal — this is what keeps the
# animation out of pipes, cron, and CI logs regardless of flags.
@test "a non-zero duration still emits no escapes when stdout is not a terminal" {
  run "$DF" --duration 5
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "the report runs clean and labels every field" {
  run "$DF" --no-color
  [ "$status" -eq 0 ]
  for label in OS: Kernel: Arch: Uptime: Packages: Shell: CPU: Memory:; do
    [[ "$output" == *"$label"* ]]
  done
}

# bats captures output through a pipe, so every case below runs with stdout off a TTY.
# That is exactly the condition --color=always exists to override.

@test "--color=always emits escapes even off a terminal" {
  run "$DF" --color=always
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033'* ]]
}

@test "--color=never emits no escapes" {
  run "$DF" --color=never
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "--color=auto is plain off a terminal" {
  run "$DF" --color=auto
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033'* ]]
}

@test "--color accepts a space-separated value" {
  run "$DF" --color always
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033'* ]]
}

@test "--color rejects an unknown value and names the valid ones" {
  run "$DF" --color=sometimes
  [ "$status" -eq 2 ]
  [[ "$output" == *"always"* ]]
  [[ "$output" == *"never"* ]]
  [[ "$output" == *"auto"* ]]
}

@test "--color requires a value" {
  run "$DF" --color
  [ "$status" -eq 2 ]
}

# The rain positions the cursor and clears the screen; forcing color must not smuggle
# that into a pipe.
@test "--color=always does not enable the animation off a terminal" {
  run "$DF" --color=always --duration 5
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\033[2J'* ]]
  [[ "$output" != *$'\033[?25l'* ]]
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
