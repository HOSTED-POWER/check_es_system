#!/usr/bin/env bash

set -u

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mock_path="$repo_dir/test/bin:$PATH"
selected_group=${1:-all}
tests_run=0
tests_failed=0
curl_log=$(mktemp)
trap 'rm -f "$curl_log"' EXIT

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

assert_request_contract() {
  local name=$1
  local checktype=$2
  local local_check=$3
  local expected_primary=$4
  local expected_secondary=${5:-}

  should_run contracts || return 0
  tests_run=$((tests_run + 1))
  : > "$curl_log"

  local -a args=(-H 127.0.0.1 -P 9200 -t "$checktype")
  if [[ $local_check == yes ]]; then
    args+=(-L)
  fi

  local output actual_exit
  output=$(PATH="$mock_path" MOCK_ES_SCENARIO=green MOCK_CURL_LOG="$curl_log" \
    "$repo_dir/check_es_system.sh" "${args[@]}" 2>&1)
  actual_exit=$?

  local expected_requests=1
  [[ -n $expected_secondary ]] && expected_requests=2

  if [[ $actual_exit -ne 0 ]] || ! grep -Fqx "$expected_primary" "$curl_log" || \
     [[ -n $expected_secondary && $(grep -Fxc "$expected_secondary" "$curl_log") -ne 1 ]] || \
     [[ $(wc -l < "$curl_log") -ne $expected_requests ]]; then
    printf 'not ok - %s\n' "$name"
    printf '  exit=%s output=%q\n' "$actual_exit" "$output"
    printf '  requests:\n'
    sed 's/^/    /' "$curl_log"
    tests_failed=$((tests_failed + 1))
    return
  fi

  printf 'ok - %s\n' "$name"
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
assert_check status "status preserves filtered health authorization errors" health_unauthorized 2 "unauthorized for cluster health" -H 127.0.0.1 -t status

assert_check master "master reports elected node" green 0 "Master node is test-master" -H 127.0.0.1 -t master
assert_check master "master handles request failure" master_failure 2 "Failed to connect" -H 127.0.0.1 -t master
assert_check master "master rejects empty response" empty_master 2 "no master node" -H 127.0.0.1 -t master

assert_filtered_check

base=http://127.0.0.1:9200
health_fields=cluster_name,status,number_of_nodes,number_of_data_nodes,active_primary_shards,active_shards,relocating_shards,initializing_shards,unassigned_shards,error
status_health_fields=relocating_shards,initializing_shards,unassigned_shards,error

assert_request_contract "online requests only health fields" online no \
  "$base/_cluster/health?filter_path=$health_fields"
assert_request_contract "status requests only status fields" status no \
  "$base/_cluster/stats?filter_path=cluster_name,status,indices.shards.total,indices.docs.count,nodes.count.total,nodes.count.data,error" \
  "$base/_cluster/health?filter_path=$status_health_fields"
assert_request_contract "disk requests only disk fields" disk no \
  "$base/_cluster/stats?filter_path=cluster_name,indices.store.size_in_bytes,nodes.fs.total_in_bytes,error"
assert_request_contract "memory requests only JVM memory fields" mem no \
  "$base/_cluster/stats?filter_path=cluster_name,nodes.jvm.mem.heap_used_in_bytes,nodes.jvm.mem.heap_max_in_bytes,error"
assert_request_contract "CPU requests only process CPU fields" cpu no \
  "$base/_cluster/stats?filter_path=cluster_name,nodes.process.cpu.percent,error"
assert_request_contract "JVM thread requests only thread fields" jthreads no \
  "$base/_cluster/stats?filter_path=cluster_name,nodes.jvm.threads,error"
assert_request_contract "local disk requests only local disk fields" disk yes \
  "$base/_nodes/_local/stats?filter_path=cluster_name,nodes.*.indices.store.size_in_bytes,nodes.*.fs.total.total_in_bytes,error"
assert_request_contract "local memory requests only local JVM memory fields" mem yes \
  "$base/_nodes/_local/stats?filter_path=cluster_name,nodes.*.jvm.mem.heap_used_in_bytes,nodes.*.jvm.mem.heap_max_in_bytes,error"
assert_request_contract "local CPU requests only local process CPU fields" cpu yes \
  "$base/_nodes/_local/stats?filter_path=cluster_name,nodes.*.process.cpu.percent,error"
assert_request_contract "local JVM thread requests only local thread fields" jthreads yes \
  "$base/_nodes/_local/stats?filter_path=cluster_name,nodes.*.jvm.threads.count,error"
assert_request_contract "readonly filters index settings" readonly no \
  "$base/_cluster/stats?filter_path=cluster_name,error" \
  "$base/_all/_settings?filter_path=*.settings.index.blocks.read_only,*.settings.index.blocks.read_only_allow_delete,*.settings.index.provided_name,error"
assert_request_contract "thread pool requests stable CAT columns" tps no \
  "$base/_cluster/stats?filter_path=cluster_name,error" \
  "$base/_cat/thread_pool?h=node_name,name,active,queue,rejected"
assert_request_contract "master requests only node column" master no \
  "$base/_cluster/stats?filter_path=cluster_name,error" \
  "$base/_cat/master?h=node"

if [[ $tests_run -eq 0 ]]; then
  printf 'No tests selected for group %s\n' "$selected_group" >&2
  exit 2
fi

printf '\nTests: %s, failures: %s\n' "$tests_run" "$tests_failed"
[[ $tests_failed -eq 0 ]]
