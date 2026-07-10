#!/usr/bin/env bats
# Tests for hug-clock library: testable current-time helper with HUG_FAKE_CLOCK override.
# All output is UTC; the override must render identically regardless of host TZ.

load '../test_helper'
load '../../git-config/lib/hug-clock'

@test "hug_clock_now: requires a format argument" {
  run hug_clock_now
  assert_failure
  assert_output --partial "usage"
}

@test "hug_clock_now: returns real UTC time when override unset" {
  unset HUG_FAKE_CLOCK
  run hug_clock_now "%Y%m%d-%H%M"
  assert_success
  # Must match YYYYMMDD-HHMM and equal date -u (UTC), not local time.
  [[ "$output" =~ ^[0-9]{8}-[0-9]{4}$ ]]
  assert_equal "$output" "$(date -u +"%Y%m%d-%H%M")"
}

@test "hug_clock_now: honors HUG_FAKE_CLOCK epoch regardless of host TZ" {
  # Codex #1: epoch formatting is TZ-dependent. Force a non-UTC TZ and confirm
  # the library still renders 20000101-0000 (UTC contract).
  TZ=America/Bahia HUG_FAKE_CLOCK=946684800 run hug_clock_now "%Y%m%d-%H%M"
  assert_success
  assert_output "20000101-0000"
}

@test "hug_clock_now: seconds format honors override" {
  HUG_FAKE_CLOCK=946684800 run hug_clock_now "%S"
  assert_success
  assert_output "00"
}

@test "hug_clock_now: invalid override warns on stderr, real UTC time on stdout" {
  # Codex #5: plain `run` merges streams — use --separate-stderr so $output and
  # $stderr are asserted independently.
  HUG_FAKE_CLOCK=not-a-number run --separate-stderr hug_clock_now "%Y%m%d-%H%M"
  assert_success
  [[ "$output" =~ ^[0-9]{8}-[0-9]{4}$ ]]
  [[ "$stderr" == *"ignoring invalid HUG_FAKE_CLOCK"* ]]
}

@test "hug_clock_now: numeric-but-unformattable override falls back with warning" {
  # Codex #3: a numeric value date cannot format must not propagate nonzero.
  # Use an absurdly large epoch that overflows date's range.
  HUG_FAKE_CLOCK=99999999999999999999 run --separate-stderr hug_clock_now "%Y%m%d-%H%M"
  assert_success
  [[ "$output" =~ ^[0-9]{8}-[0-9]{4}$ ]]
  [[ "$stderr" == *"could not be formatted"* ]]
}

@test "hug_clock_epoch: returns real epoch when override unset" {
  unset HUG_FAKE_CLOCK
  run hug_clock_epoch
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
  local real_epoch now_epoch
  real_epoch=$(date -u +%s)
  now_epoch=$output
  (( now_epoch - real_epoch <= 5 ))
  (( real_epoch - now_epoch <= 5 ))
}

@test "hug_clock_epoch: returns override verbatim" {
  HUG_FAKE_CLOCK=946684800 run hug_clock_epoch
  assert_success
  assert_output "946684800"
}

@test "hug_clock_epoch: invalid override falls back to real epoch" {
  HUG_FAKE_CLOCK=garbage run hug_clock_epoch
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}
