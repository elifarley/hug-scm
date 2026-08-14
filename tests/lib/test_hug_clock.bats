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
  # Must match YYYYMMDD-HHMM format. The regex is sufficient — a second
  # `date` call for exact equality would straddle a minute boundary (Codex P2).
  [[ "$output" =~ ^[0-9]{8}-[0-9]{4}$ ]]
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

@test "hug_clock_epoch: invalid override warns and falls back to real epoch" {
  HUG_FAKE_CLOCK=garbage run --separate-stderr hug_clock_epoch
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
  [[ "$stderr" == *"ignoring invalid HUG_FAKE_CLOCK"* ]]
}

@test "hug_clock_epoch: numeric-but-unformattable override falls back with warning" {
  HUG_FAKE_CLOCK=99999999999999999999 run --separate-stderr hug_clock_epoch
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
  [[ "$stderr" == *"could not be formatted"* ]]
}

# -----------------------------------------------------------------------------
# hug_clock_format_epoch — the capture-once-format-many primitive.
#
# Callers (resolve_backup_name, git-bc) capture ONE epoch via hug_clock_epoch,
# then format several components (%Y-%m, %d-%H%M, %S) from it. The invariant
# these tests pin: all components refer to the SAME instant, so across a
# year/month/day/hour/minute boundary the timestamp stays chronologically
# consistent (no "2024-12" paired with "01-0000" from Jan 1).
# -----------------------------------------------------------------------------

@test "hug_clock_format_epoch: formats a known epoch per format string" {
  # 946684800 = 2000-01-01 00:00:00 UTC.
  run hug_clock_format_epoch 946684800 "%Y-%m-%d"
  assert_success
  assert_output "2000-01-01"

  run hug_clock_format_epoch 946684800 "%d-%H%M"
  assert_success
  assert_output "01-0000"

  run hug_clock_format_epoch 946684800 "%S"
  assert_success
  assert_output "00"
}

@test "hug_clock_format_epoch: components from the same epoch are mutually consistent" {
  # The boundary-race invariant: format %Y-%m, %d-%H%M, %S from ONE epoch and
  # they must describe the same instant. Pin a boundary-adjacent instant —
  # 2024-12-31 23:59:59 UTC — and assert each component matches that instant.
  local epoch=1735689599
  local ym dhm secs
  ym=$(hug_clock_format_epoch "$epoch" "%Y-%m")
  dhm=$(hug_clock_format_epoch "$epoch" "%d-%H%M")
  secs=$(hug_clock_format_epoch "$epoch" "%S")
  assert_equal "$ym" "2024-12"
  assert_equal "$dhm" "31-2359"
  assert_equal "$secs" "59"
  # One second later rolls the YEAR, MONTH, DAY, HOUR, MINUTE simultaneously.
  local epoch2=$((epoch + 1))
  ym=$(hug_clock_format_epoch "$epoch2" "%Y-%m")
  dhm=$(hug_clock_format_epoch "$epoch2" "%d-%H%M")
  secs=$(hug_clock_format_epoch "$epoch2" "%S")
  assert_equal "$ym" "2025-01"
  assert_equal "$dhm" "01-0000"
  assert_equal "$secs" "00"
}

@test "hug_clock_format_epoch: garbage epoch returns nonzero and empty stdout" {
  # Fail-safe contract: a non-numeric epoch must not crash the caller. Both
  # GNU and BSD date reject it; the function returns nonzero with empty stdout.
  run hug_clock_format_epoch "not-a-number" "%Y-%m"
  assert_failure
  [[ -z "$output" ]]
}
