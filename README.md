# check_es_system (Elasticsearch and OpenSearch Monitoring Plugin)
This is an open source monitoring plugin to check the status of an Elasticsearch or OpenSearch cluster or a single node. Besides the classical status check (green, yellow, red), this plugin can monitor availability, disk usage, memory usage, CPU usage, JVM threads, thread pools, the elected master, and read-only indexes.

The `online` check is intended for high-priority availability monitoring. It treats both green and yellow cluster health as OK, while red health, connection failures, timeouts, authentication failures, and invalid Elasticsearch responses are CRITICAL. This gives single-node clusters—which are commonly yellow because replicas cannot be assigned—a stable OK baseline for retry-based alerting. Use the separate `status` check when yellow must remain a WARNING.

The plugin was initially written for Elasticsearch but also works on OpenSearch.

Please refer to https://www.claudiokuenzler.com/monitoring-plugins/check_es_system.php for full documentation and usage examples.

Requirements
------
- The following commands must be available: `curl`, `expr`
- One of the following json parsers must be available: `jshon` or `jq` (defaults to jq)

Usage
------

    ./check_es_system.sh -H NodeOrClusterAddress [-P port] [-S] [-L] [-u user] [-p pass] [-E certificate] [-K key] -t check [-o unit] [-i index1,index2] [-w warn] [-c crit] [-m max_time] [-e node] [-X jq|jshon]

Availability check:

    ./check_es_system.sh -H 127.0.0.1 -P 9200 -t online

Detailed cluster-health check:

    ./check_es_system.sh -H 127.0.0.1 -P 9200 -t status

| Check | Green | Yellow | Red/unreachable |
| --- | --- | --- | --- |
| `online` | OK | OK | CRITICAL |
| `status` | OK | WARNING | CRITICAL |

Tests
------

The deterministic regression suite uses a mocked `curl` command and does not require Elasticsearch:

    bash test/test_regressions.sh
