# Elasticsearch Availability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an availability-oriented `online` check that treats green and yellow clusters as available, while hardening five adjacent failure and performance paths.

**Architecture:** Keep the existing single-file Bash plugin and its Nagios exit-code contract. Add a lightweight health-only request for `online`, retain the detailed `status` check, reduce API payloads with `filter_path`, and cover behavior with a deterministic mocked `curl` executable so tests do not require a running Elasticsearch cluster.

**Tech Stack:** Bash, curl, jq/jshon, GitHub Actions

---

### Task 1: Deterministic test harness

**Files:**
- Create: `test/bin/curl`
- Create: `test/test_regressions.sh`

- [ ] **Step 1: Add a mock curl executable**

Create a Bash mock that selects green, yellow, red, unknown, connection-failure, health-failure, and master-failure responses using `MOCK_ES_SCENARIO`. It must recognize `/_cluster/health`, `/_cluster/stats`, and `/_cat/master`, and reject stats URLs that omit `filter_path` when `MOCK_REQUIRE_FILTER_PATH=1`.

- [ ] **Step 2: Add failing regression cases**

Add shell assertions for:

```text
online green  -> exit 0
online yellow -> exit 0
online red    -> exit 2
online connection failure -> exit 2
status unknown -> exit 3
status health request failure -> exit 2
master request failure -> exit 2
cluster stats request includes filter_path -> exit 0
```

- [ ] **Step 3: Run the new suite and confirm red**

Run: `bash test/test_regressions.sh`

Expected: failures for the absent `online` mode and the existing status/master error paths.

### Task 2: Add the `online` availability check

**Files:**
- Modify: `check_es_system.sh`
- Modify: `README.md`

- [ ] **Step 1: Add `online` to validation and help**

Document that `online` returns OK for green/yellow and CRITICAL for red, unreachable, timed-out, unauthorized, or invalid Elasticsearch responses.

- [ ] **Step 2: Use the health endpoint only**

For `-t online`, request:

```text
/_cluster/health?filter_path=cluster_name,status,number_of_nodes,number_of_data_nodes,active_primary_shards,active_shards,relocating_shards,initializing_shards,unassigned_shards
```

This avoids the heavier `/_cluster/stats` call for a 30-second availability check.

- [ ] **Step 3: Implement state mapping**

Return OK for `green` and `yellow`, CRITICAL for `red`, and UNKNOWN for any unrecognized or missing status.

- [ ] **Step 4: Run the online cases**

Run: `bash test/test_regressions.sh online`

Expected: all online assertions pass.

### Task 3: Reduce Elasticsearch API response size

**Files:**
- Modify: `check_es_system.sh`

- [ ] **Step 1: Add cluster-stats field filtering**

Append a `filter_path` containing only fields consumed by disk, memory, CPU, JVM-thread, status, and master checks.

- [ ] **Step 2: Add local node-stats field filtering**

Append a separate node-local `filter_path` matching the existing `.nodes[]` parsing paths.

- [ ] **Step 3: Verify the request contract**

Run: `MOCK_REQUIRE_FILTER_PATH=1 bash test/test_regressions.sh filter`

Expected: the disk check returns exit 0 and the mock confirms a filtered stats URL.

### Task 4: Fail safely on invalid status and request failures

**Files:**
- Modify: `check_es_system.sh`
- Modify: `test/test_regressions.sh`

- [ ] **Step 1: Capture the cluster-health curl return code**

Store and evaluate the health request return code instead of treating only an empty response as an error.

- [ ] **Step 2: Add explicit unexpected-status output**

If status is not `green`, `yellow`, or `red`, print `ES SYSTEM UNKNOWN` and exit 3 instead of falling through to shell exit 0.

- [ ] **Step 3: Run status failure cases**

Run: `bash test/test_regressions.sh status`

Expected: unknown status returns 3 and a failed health request returns 2.

### Task 5: Correct the master-check failure path

**Files:**
- Modify: `check_es_system.sh`
- Modify: `test/test_regressions.sh`

- [ ] **Step 1: Use `masterrc` in sanity checks**

Replace the incorrect `threadpoolrc` references with `masterrc`.

- [ ] **Step 2: Reject empty master responses**

Return CRITICAL when the master request succeeds but returns no master node.

- [ ] **Step 3: Run master cases**

Run: `bash test/test_regressions.sh master`

Expected: failed and empty master responses return exit 2.

### Task 6: CI and documentation

**Files:**
- Create: `.github/workflows/test.yml`
- Modify: `README.md`
- Modify: `check_es_system.sh`

- [ ] **Step 1: Add GitHub Actions**

Install `jq` and run `bash -n check_es_system.sh` plus `bash test/test_regressions.sh` on pushes and pull requests.

- [ ] **Step 2: Document the state contract**

Add concise examples for `online` and explain why it is different from `status` on single-node clusters.

- [ ] **Step 3: Bump the plugin version**

Increment the feature version and add dated changelog entries for the new mode and fixes.

- [ ] **Step 4: Run full verification**

Run:

```bash
bash -n check_es_system.sh
bash -n test/bin/curl test/test_regressions.sh
bash test/test_regressions.sh
git diff --check
```

Expected: every command exits 0 and the regression suite reports zero failures.

- [ ] **Step 5: Commit the isolated change**

Run:

```bash
git add check_es_system.sh README.md test/bin/curl test/test_regressions.sh .github/workflows/test.yml docs/superpowers/plans/2026-09-16-elasticsearch-availability-hardening.md
git commit -m "Add Elasticsearch availability check and harden failures"
```
