#!/usr/bin/env bash

set -u

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mock_path="$repo_dir/test/bin:$PATH"
selected_group=${1:-all}
tests_run=0
tests_failed=0

should_run() {
  [[ $selected_group == all || $selected_group == "$1" ]]
}

assert_check() {
  local group=$1
  local name=$2
  local scenario=$3
  local expected_exit=$4
  local expected_text=$5
  shift 5

  should_run "$group" || return 0
  tests_run=$((tests_run + 1))

  local output actual_exit
  output=$(PATH="$mock_path" MOCK_ES_SCENARIO="$scenario" "$repo_dir/check_es_system.sh" "$@" 2>&1)
  actual_exit=$?

  if [[ $actual_exit -ne $expected_exit || $output != *"$expected_text"* ]]; then
    printf 'not ok - %s\n' "$name"
    printf '  expected exit=%s text=%q\n' "$expected_exit" "$expected_text"
    printf '  actual   exit=%s output=%q\n' "$actual_exit" "$output"
    tests_failed=$((tests_failed + 1))
    return
  fi

  printf 'ok - %s\n' "$name"
}

assert_filtered_check() {
  should_run filter || return 0
  tests_run=$((tests_run + 2))

  local output actual_exit
  output=$(PATH="$mock_path" MOCK_ES_SCENARIO=green MOCK_REQUIRE_FILTER_PATH=1 \
    "$repo_dir/check_es_system.sh" -H 127.0.0.1 -P 9200 -t disk 2>&1)
  actual_exit=$?

  if [[ $actual_exit -ne 0 || $output != *"ES SYSTEM OK - Disk usage"* ]]; then
    printf 'not ok - cluster stats request uses filter_path\n'
    printf '  actual exit=%s output=%q\n' "$actual_exit" "$output"
    tests_failed=$((tests_failed + 1))
    return
  fi

  printf 'ok - cluster stats request uses filter_path\n'

  output=$(PATH="$mock_path" MOCK_ES_SCENARIO=green MOCK_REQUIRE_FILTER_PATH=1 \
    "$repo_dir/check_es_system.sh" -H 127.0.0.1 -P 9200 -L -t disk 2>&1)
  actual_exit=$?

  if [[ $actual_exit -ne 0 || $output != *"ES SYSTEM OK - Disk usage"* ]]; then
    printf 'not ok - local node stats request uses filter_path\n'
    printf '  actual exit=%s output=%q\n' "$actual_exit" "$output"
    tests_failed=$((tests_failed + 1))
    return
  fi

  printf 'ok - local node stats request uses filter_path\n'
}

assert_check online "online accepts green" green 0 "ES SYSTEM OK" -H 127.0.0.1 -t online
assert_check online "online accepts yellow" yellow 0 "yellow" -H 127.0.0.1 -t online
assert_check online "online rejects red" red 2 "ES SYSTEM CRITICAL" -H 127.0.0.1 -t online
assert_check online "online rejects connection failure" connection_failure 2 "Failed to connect" -H 127.0.0.1 -t online
assert_check online "online rejects unknown health" unknown 3 "ES SYSTEM UNKNOWN" -H 127.0.0.1 -t online

assert_check status "status accepts green" green 0 "is green" -H 127.0.0.1 -t status
assert_check status "status warns on yellow" yellow 1 "is yellow" -H 127.0.0.1 -t status
assert_check status "status rejects red" red 2 "is red" -H 127.0.0.1 -t status
assert_check status "status rejects unknown health" unknown 3 "ES SYSTEM UNKNOWN" -H 127.0.0.1 -t status
assert_check status "status handles health request timeout" health_failure 2 "did not respond" -H 127.0.0.1 -t status

assert_check master "master reports elected node" green 0 "Master node is test-master" -H 127.0.0.1 -t master
assert_check master "master handles request failure" master_failure 2 "Failed to connect" -H 127.0.0.1 -t master
assert_check master "master rejects empty response" empty_master 2 "no master node" -H 127.0.0.1 -t master

assert_filtered_check

if [[ $tests_run -eq 0 ]]; then
  printf 'No tests selected for group %s\n' "$selected_group" >&2
  exit 2
fi

printf '\nTests: %s, failures: %s\n' "$tests_run" "$tests_failed"
[[ $tests_failed -eq 0 ]]
