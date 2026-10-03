#!/usr/bin/env bats
#
# tests/bats/node_modules/.bin/bats --tap tests/bats/helper.bats
#
# shellcheck disable=SC2030,SC2031

load _helper

@test "host_platform maps the machine architecture to a Docker platform" {
  mock_uname="$(mock_command "uname")"

  # Columns: the 'uname -m' output and the expected platform.
  # shellcheck disable=SC2034
  TEST_CASES=(
    "x86_64" "linux/amd64"
    "arm64" "linux/arm64"
    "aarch64" "linux/arm64"
    "riscv64" "linux/riscv64"
  )
  dataprovider_run "host_platform_on_machine" 2
}

host_platform_on_machine() {
  mock_set_output "${mock_uname}" "${1}"
  host_platform
}

@test "wait_mysql prints the container logs and fails when MySQL does not start" {
  mock_docker="$(mock_command "docker")"
  # The port check fails, and the logs call that follows prints a log line.
  mock_set_status "${mock_docker}" 1 1
  mock_set_output "${mock_docker}" "Fake container log line." 2

  run wait_mysql "fake-container"
  assert_failure
  assert_output_contains "Fake container log line."
  assert_equal "logs fake-container" "$(mock_get_call_args "${mock_docker}" 2)"
}
