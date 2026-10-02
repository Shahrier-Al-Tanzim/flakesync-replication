# FlakeSync - replication report

> One-page summary of the FlakeSync replication. Full detail in
> [flakesync_findings.md](flakesync_findings.md). Full historical plan in
> [flakesync_explore.md](flakesync_explore.md).

## 1. What I did

Downloaded the official FlakeSync artifact from Zenodo (1.4 GB, checksum
verified against the published MD5), loaded it as a Docker image
(`flakesync-artifact:latest`, 2.22 GB, built 2024-01-04), and discovered it
ships far more than a typical replication package: the tool's own source,
every driver script, and - critically - the **authors' own actual output**
for 71 tests (critical points, barrier points, thresholds, runtimes), which
let this replication diff its own runs directly against ground truth instead
of only against the paper's aggregate tables.

Ran the artifact's own end-to-end pipeline (`end_to_end_flakesync.sh`) inside
the shipped image, under the paper's stated resource limits (4 CPU, 4 GB
RAM), against two real subjects from Table 1: M22 (`elastic-job-lite`) and
M26 (`delight-nashorn-sandbox`). In parallel, randomly sampled 10 of the
paper's 37 evaluation modules and attempted to build each at its recorded
commit, to measure how much of the dataset still compiles today.

Also ran a resource-sensitivity comparison (Module 6, Step 27 - 8 CPU/8 GB
vs. the paper's 4 CPU/4 GB), a deliberate native-Windows break test (Step 29),
and a clean baseline-runtime measurement toward the RQ4 overhead metric
(Step 26, partial).

**Not fully done this session:** RQ4's actual repaired-vs-original overhead
ratio (a clean baseline was measured; the ratio itself needs a
patch-application step not found in the shipped scripts within this
session's time). The M3 (Java-WebSocket, 52 tests) stretch target was not
attempted - expensive relative to remaining budget.

## 2. What the paper claims vs. what I measured

| | Paper (Table 1/2, M26) | This run |
| --- | --- | --- |
| Critical point | found | **found - matches, 4 of 6 reps exactly, 2 of 6 a coarser but consistent variant** |
| Barrier point | `NashornSandboxImpl` (implied) | `NashornSandboxImpl#233` - **exact match** |
| Threshold | 1 (implied) | 1 - **exact match** |
| Repaired | yes | yes, by the artifact's own criteria |
| Runtime | not directly comparable (see caveat in findings) | 44–62s search time vs. authors' recorded 28.38s |

| | Paper (Table 1, M22) | This run |
| --- | --- | --- |
| Buildable | yes | **fails** via the artifact's own `all_input.csv` row (uses `master`, not a pinned SHA) - **but builds clean (EXIT=0) at the correct Table 1 SHA `9afe466`**, confirming the project itself is fine and the artifact's own input row is the problem |

**Staleness sample (10 of 37 modules, random, seeded):** 7 clean, 1 confirmed
non-issue (dubbo module-path notation), 1 likely the same (unconfirmed), 1
genuine staleness (Achilles - an unpinned Maven plugin resolved to a version
requiring a newer JDK than the project targets). **Real staleness rate: at
most 1 of 10 sampled modules**, well below the paper's own 26% attrition
during original construction (300→221).

## 3. The disagreements - central section

1. **The artifact's own demo/evaluation data is less reliable than its code.**
   One of `all_input.csv`'s 70 rows uses `master` instead of a pinned commit - the only row that does. It broke, concretely, 21 months after the artifact
   shipped. The fix (pin the SHA) costs one edit; the artifact never applies
   it to itself.
2. **FlakeSync's own search is not fully deterministic**, even within one
   pipeline execution on one machine. The barrier point and threshold were
   stable across 6 internal repetitions; the *critical-point decomposition*
   was not (4-of-6 vs. 2-of-6 pattern). The paper reports one number per test
   and never discusses repetition variance - this is first-hand evidence that
   variance exists, on a case where the final repair outcome still happened
   to agree.
3. **The delay schedule the artifact ships (max 25,600ms) is half the
   paper's stated `MAX_DELAY` (51,200ms).** Confirmed by exhaustive search of
   both the shell scripts and the full Java source - the constant does not
   exist anywhere in the shipped code. Any test needing 25.6–51.2s of delay
   to reproduce would silently under-report using the artifact as shipped.
4. **The artifact's own bookkeeping uses at least three subject counts (70,
   71, 178) that match none of the paper's published funnel numbers** (176 /
   174 / 80 / 67) - not yet reconciled; flagged for anyone reproducing this
   work with access to the original authors.
5. **A concrete, diagnosed Windows-native failure**: the pom-injection step
   (`agent-pom-modify/PomFile.java`) receives POSIX-style paths from `find`
   (under git-bash) and calls `new File(pom)` directly - a native-Windows JVM
   cannot resolve `/c/...`-style paths. The check fails silently (containing
   the artifact's own typo, "exit" instead of "exist"), the agent never gets
   attached, and **no error propagates to the calling script** - the pipeline
   would continue and report "no boundary found," indistinguishable from a
   genuine negative result. Third distinct Windows bug found across this
   research line's tools, each with a different root cause.
6. **Doubling the container's CPU and memory (4→8 cores, 4→8 GB) changed
   neither the final answer nor meaningfully the search speed** (41.0s vs.
   the original config's 44.2–62.3s range) for M26. The pipeline's cost here
   is bound by its inherently sequential structure (one `mvn test`
   invocation per candidate), not by available resources - extra hardware
   would not speed this up.
7. **On a third target (M16, rxjava2-extras), the barrier point matched the
   authors' ground truth exactly - but the critical point was a completely
   different class** (`Flowables$4#306`, the test's own code, vs. their
   `ScheduledRunnable#57`, deep in RxJava's scheduler internals). The repair
   reproduces; the diagnosis a developer would read to understand *why*
   does not. A stronger, second instance of the determinism problem above.

## 4. What I'd do next

- Measure the paper's actual RQ4 overhead metric (repaired vs. original
  runtime) directly, which this session did not do.
- Retry M21 (Achilles) under JDK 17 instead of JDK 8 to confirm the
  plugin-version staleness diagnosis and see whether it's a one-line fix.
- Run the resource-sensitivity sweep (Module 6 Step 27) on M26, since its
  critical-point decomposition already showed variance within one config - worth checking whether the config with more resources changes it further.
- Cross-check FlakeSync's dubbo tests (M7–M11, once module paths are
  corrected) against RankF's dubbo worked example - both plans touch the
  same project, unexamined so far.
