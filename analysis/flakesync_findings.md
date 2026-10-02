# FlakeSync - Findings log

> Observations from replicating the FlakeSync artifact. Organised by category.
> Every entry gives: the exact command, the wall-clock, what was expected (from
> the paper), what happened, and why the difference matters. Entries are never
> deleted.

## Run-block template

    ### YYYY-MM-DD - <one-line title> `[TAG]` `[TAG]`
    **Target:** <project> module <module>, SHA <sha>, FlakeSync module ID <Mnn>
    **Paper says:** <the exact number or claim from the paper, with table/section>
    **Command:**
    ```
    <the full command, every flag>
    ```
    **Wall-clock:** <time>
    **Observed:** <what actually happened>
    **Gap:** <what is different, and why that is interesting>
    **Log:** findings/logs/flakesync/<file>.log

---

## [UNEXPECTED] - behaved differently from the paper or the docs

### 2026-09-21 - Real reproduction of M26 (delight-nashorn-sandbox): matches ground truth, but reveals internal non-determinism `[UNEXPECTED]` `[CONFIG-DEPENDENT]`
**Target:** `javadelight/delight-nashorn-sandbox`, SHA `da35edc0a75424bad8cbf60959fae253202154c4`,
test `delight.nashornsandbox.TestGetFunction#test` (paper Table 1 M26)
**Paper says:** Table 2 M26 - critical point found, **repaired**, overhead **0.91×**
**Command:** the artifact's own `end_to_end_flakesync.sh` run end-to-end inside
the shipped Docker image (`flakesync-artifact:latest`), 4 CPU / 4 GB, via
`docker run --cpus=4 --memory=4g`, full pipeline `real 21m21.445s` for both
targets combined (T1 failed at build per the staleness finding above; this
result is T2 only)
**Observed - compared directly against the authors' own
`expected_results/Results-Barrier/Result.csv`:**

| Field | Authors' recorded result | My run (6 repetitions from one pipeline execution) |
| --- | --- | --- |
| Barrier point | `NashornSandboxImpl#233` | `NashornSandboxImpl#233` - **exact match, all 6 reps** |
| Threshold | `1` | `1` - **exact match, all 6 reps** |
| Critical point | `JsEvaluator#53~54[100];67~68[100];` (split, two ranges) | **4 of 6 reps**: exact match, same split. **2 of 6 reps**: a coarser single range `JsEvaluator#53~68[100]` - same overall span, different internal decomposition |
| Search runtime (not the paper's overhead metric - see caveat) | 28.383s | 44.2s – 62.3s across the 6 reps (mean ≈ 50.7s) - **1.6× to 2.2× slower** |

**Gap - two distinct findings in one comparison:**
1. **The core result reproduces.** Same barrier point, same threshold, same
   overall critical region, on different hardware, 21 months after the
   artifact was built. This is a genuine, positive replication of one of the
   paper's 67 repaired tests.
2. **But the pipeline is not internally deterministic.** These 6 rows all
   came from **one single execution** of `end_to_end_flakesync.sh` against
   one test (the script's own internal repetition, not a re-run I triggered).
   2 of 6 reps converged on a materially different critical-point
   decomposition than the other 4 - same span, different internal
   granularity. The paper reports exactly one number per test in Table 2 and
   never discusses repetition variance. This is direct, first-hand evidence
   that FlakeSync's search process can find different - not just
   differently-timed - answers for the identical test on the identical
   machine in the identical run. Module 6's planned determinism probe
   (Step 28) is answered by this alone: **no, it is not fully deterministic.**

### 2026-09-21 - M16 (rxjava2-extras, stretch target): barrier point matches exactly, critical point is a *different class entirely* `[UNEXPECTED]` `[CONFIG-DEPENDENT]`
**Target:** `davidmoten/rxjava2-extras`, SHA `7663d3b19295f12c35f80594efa1e507e98650b1`,
test `com.github.davidmoten.rx2.FlowablesTest#testCache` (Table 1 M16)
**Command:** same artifact pipeline, 4 CPU / 4 GB, second stretch run
(second test in the same input, `TransformersTest#testBufferMaxCountAndTimeoutAsyncCountWins`,
was still mid-search when this run was stopped after ~2 hours - see the
`[RESOURCE-GAP]` entry below)
**Observed vs. authors' `expected_results/Results-Barrier/Result.csv`:**

| Field | Authors' recorded result | My run |
| --- | --- | --- |
| Barrier point | `FlowablesTest#67` | `FlowablesTest#67` - **exact match** |
| Threshold | 1 | 1 - **exact match** |
| Critical point | `ScheduledRunnable#57` (RxJava internal scheduler class), delay 1600ms | `Flowables$4#306` (the test's own anonymous inner class), delay 800ms |
| Time | 37.0s | 68.0s |

**Gap - a stronger version of the M26 finding.** For M26 the two runs found
the *same class*, different sub-range split. Here they found **two entirely
different classes** - one deep in RxJava's own scheduler internals, one in
the test module's own code - as the reported "critical point" (the location
the paper's Section 3.1 says helps a developer understand *where* the bug
is). Both runs still converged on the identical fix location and threshold,
so the **repair** is reproducible even though the **diagnosis** is not. This
is a materially more serious version of the non-determinism already logged:
if a developer used FlakeSync's critical-point output to understand *why*
their test is flaky, two runs on two machines could point them at two
unrelated pieces of code, both consistent with the same working fix.
**Log:** findings/logs/flakesync/pipeline-m16-full.log; findings/reports/flakesync/my-run-m16-Results-Barrier-partial/

**Caveat on the "Time" column:** `expected_results/README.md` describes this
field as "the duration taken to reach the barrier point" - a search/discovery
runtime, not the paper's Table 2 "Overhead (X)" metric (repaired-test runtime
÷ original-test runtime, from actually running the patched test). This
comparison is about how long *finding* the fix took, not the *cost of the fix
itself*. Measuring the paper's actual overhead metric was not done in this
session and is left as follow-up (plan Module 5, Step 26).
**Log:** findings/logs/flakesync/pipeline-run1-full.log (516K, full pipeline
transcript); findings/reports/flakesync/my-run-Results-Barrier/,
my-run-Results-Boundary/, my-run-Results-Minimizer/ (real output, vs.
findings/reports/flakesync/expected_results/ - the authors' original output,
for direct diffing)

### 2026-09-21 - Artifact ships far more than a typical replication package `[UNEXPECTED]`
**Target:** the artifact itself, not a subject
**Paper says:** nothing - data availability just points to the Zenodo record
**Observed:** the 1.4 GB tarball is a pure `docker save` export (`flakesync-artifact:latest`,
2.22 GB loaded, built 2024-01-04). Inside, `/home/java8-flakesync/` contains:
- `FlakeSync/` - the tool source, three Maven modules: `flakeDelay-core`
  (CritSearch/delay injection), `barrierSearch-core`, `localization-core`
  (root-method search)
- `scripts/` - every driver script for the pipeline, plus `agent-pom-modify/`
  which injects the Java agent into subject `pom.xml`s via a small Java
  program (`PomFile.java`), not a shell `sed` hack
- `scripts/data_list/all_input.csv` - **70 lines**, the artifact's own curated
  "tests to actually run" list - narrower than the paper's full 176/174/80
  funnel, and a different set than my hand-typed Table 1 (see `[DISAGREEMENT]`
  below)
- `scripts/data_list/input.csv` - the single demo test (`alibaba/wasp`, i.e.
  Table 1's M6), matching the `scripts/README.md` example exactly
- `scripts/projects/` - 8 pre-staged project clones (davidmoten, elasticjob,
  flaxsearch, fluent, javadelight, nlighten, qos-ch, undertow-io) - **but
  these are scratch/leftover from the authors' own prior runs, not what the
  pipeline uses.** `runAll.sh` clones fresh into a sibling `projects-For-Delta/`
  directory every time, keyed off `all_input.csv`
- `expected_results/` - the authors' own actual output: `Results-Boundary/`
  (76 per-test CSVs, critical-point locations), `Results-Minimizer/` (358
  files, including delta-debugging intermediates), `Results-Barrier/Result.csv`
  (**72 lines incl. header - 71 data rows**, giving critical-point,
  barrier-point, threshold and runtime per test in the exact schema its own
  README documents)

**Gap:** this is materially better than the plan assumed (Module 1 Step 5-7
anticipated possibly nothing more than a README). It means Modules 4-6 can
verify runs against the artifact's **own** recorded output per test, not just
against the paper's aggregate tables. Copied into
`findings/reports/flakesync/` (`expected_results/`, `artifact-all_input.csv`,
`artifact-demo_input.csv`) since these are real result artifacts, not scratch.
**Log:** findings/logs/flakesync/image-explore.log, image-readmes.log,
image-datalist.log, image-all-input.log

### 2026-09-21 - Delay schedule stops at 25600ms, paper's MAX_DELAY is 51200ms `[UNEXPECTED]` `[CONFIG-DEPENDENT]`
**Target:** `scripts/runAll.sh`
**Paper says:** Section 4.3 - `INITIAL_DELAY` 100ms, `MAX_DELAY` 51200ms
**Observed:** `runAll.sh`'s `delayArray=(100 200 400 800 1600 3200 6400 12800 25600)` - nine steps, doubling from 100 to 25600, and stopping there. **51200 never
appears in this script - and a search of the entire copied tool source
(`FlakeSync/tool-source/`, the `flakeDelay-core`, `barrierSearch-core`, and
`localization-core` Java modules) for `51200`, `25600`, `INITIAL_DELAY`, or
`MAX_DELAY` returns zero hits.** Confirmed: the shell array is the complete,
only implementation of the delay schedule, and it stops one doubling short
of the paper's stated `MAX_DELAY`.
**Gap:** the paper's stated ceiling (51,200ms) is not what the shipped
artifact actually runs (25,600ms max). For any test whose failure needs a
delay between 25,600 and 51,200ms to reproduce, the shipped artifact would
report "no boundary found" where the paper's described configuration would
have found one - a silent under-reporting risk baked into the artifact
itself, independent of anything about this replication's environment.
**Log:** findings/logs/flakesync/image-datalist.log (script text),
tool-source grep (zero matches, confirmed via `grep -rn` over the full
copied source tree)

## [DISAGREEMENT] - contradictions between tools, datasets, or papers

### 2026-09-21 - Artifact's own curated list (70) doesn't match paper's stated counts (176 / 174 / 80) `[DISAGREEMENT]`
**Target:** `scripts/data_list/all_input.csv` vs. paper Table 1/Table 2
**Paper says:** 176 tests reach the final dataset; 174 get a critical point;
80 are genuine async flaky tests; 67 get repaired
**Observed:** `all_input.csv` has 70 lines (69 unique test identifiers - one
duplicate `flaxsearch/luwak` row). `Results-Barrier/Result.csv` - the
artifact's own record of completed barrier-point searches - has 71 data rows.
Neither number is 176, 174, 80, or 67. Also spotted:
`Results-Minimizer/Only-178-Tests-Delta-Result.csv` - **178**, a number that
appears nowhere in the paper's stated funnel (300 → 221 → 176 → 174 → 80 → 67).
**Gap:** the shipped artifact's own bookkeeping uses at least three counts
(70, 71, 178) that don't match any published number. Worth reconciling in
Module 2/7 - possibly the shipped artifact is a later or different snapshot
than what produced the published tables, which would itself be a citable
`[STALENESS]`/reproducibility finding.
**Log:** findings/logs/flakesync/image-all-input.log

## [LIMITATION] - demonstrated boundaries of the technique

## [FALSE-POSITIVE] - claimed results that do not hold up

## [FALSE-NEGATIVE] - real cases the tool missed

## [CONFIG-DEPENDENT] - results that move with configuration

### 2026-09-21 - Resource sensitivity (Module 6, Step 27): doubling CPU/RAM changes neither the answer nor meaningfully the speed `[CONFIG-DEPENDENT]` `[NULL]`
**Target:** `delight.nashornsandbox.TestGetFunction#test` (M26), same clean
image, same SHA
**Configs compared:**

| | Config A (paper's stated config) | Config B |
| --- | --- | --- |
| CPU | `--cpus=4` | `--cpuset-cpus=0-7` (8 cores) |
| Memory | `--memory=4g` | `--memory=8g` |
| Critical point | 4-of-6 reps: `53~54,67~68` split; 2-of-6: coarser `53~68` | 1 run: `53~54,67~68` split (matches the majority pattern) |
| Barrier point | `NashornSandboxImpl#233` | `NashornSandboxImpl#233` - same |
| Threshold | 1 | 1 - same |
| Barrier-search "Time" | 44.2s–62.3s (mean ≈50.7s) | **41.0s** - within the same range |
| Total pipeline wall-clock (this test only) | not isolated (ran with T1) | 3m 27s |

**Observed:** giving the container twice the CPU cores and twice the memory
**did not produce a meaningfully faster result** (41.0s sits inside config
A's own 44.2–62.3s spread) and **did not change the final answer** - same
barrier point, same threshold, and the majority-pattern critical point.
**Gap - read alongside the determinism finding above:** this is genuine
signal that FlakeSync's search cost here is **not CPU/memory-bound**. The
algorithm proceeds through a sequence of individual `mvn test` invocations
(JVM + Maven cold-start dominate each step), which is inherently serial - extra cores have nothing to parallelize against in this pipeline's current
implementation. A user hoping a bigger machine would make CritSearch/
BarrierSearch faster, on a test this size, would be spending resources for
no benefit. This is a `[NULL]` result in the sense the plan predicted it as
one legitimate possible outcome - and it strengthens (does not weaken) the
earlier non-determinism finding, since config B landing on the majority
pattern (not the minority one) is consistent with genuine run-to-run
variance rather than a config-A-specific artifact.
**Caveat:** single run at config B, versus 6 internal repetitions at config
A - not a matched sample size, so this is suggestive, not conclusive; a
fuller sweep (multiple reps at config B) is listed as follow-up.
**Log:** findings/logs/flakesync/pipeline-configB-full.log; findings/reports/flakesync/my-run-configB-Results-Barrier/

## [RESOURCE-GAP] - hardware or time beyond what is stated

### 2026-09-21 - M16's second test genuinely needs ~7+ minutes; stopped after ~2 hours wall-clock for the whole run `[RESOURCE-GAP]`
**Target:** `TransformersTest#testBufferMaxCountAndTimeoutAsyncCountWins`
(the second of M16's two tests)
**Observed:** this run was stopped (not crashed) after ~2 hours of total
wall-clock for both M16 tests, while still mid-search for this second test.
**Confirmed from the authors' own ground truth, after the fact:** their
recorded runtime for this exact test is **438.4 seconds (7.3 minutes)** - by far the most expensive single-test entry in the entire `Results-Barrier`
reference file (compare: 28–68s for the other three tests this session
touched). This is not a sign of malfunction; this specific test is
genuinely, verifiably expensive even for the original authors. The stop was
a session time-management decision, not a tool failure - recorded honestly
rather than presented as either a success or a bug.
**Gap:** confirms the plan's own warning (Module 3, "Budget honestly") that
per-test cost varies enormously and some tests are legitimately costly
regardless of hardware - consistent with the resource-sensitivity finding
above, which showed this pipeline's cost is dominated by sequential search
steps, not by available CPU/memory.

### 2026-09-21 - RQ4 overhead metric: baseline measured cleanly, true "repaired-test" ratio not obtainable from the shipped scripts `[RESOURCE-GAP]` `[LIMITATION]`
**Target:** `delight.nashornsandbox.TestGetFunction#test` (M26)
**Paper says:** Table 2 M26 overhead **0.91×** - repaired-test runtime ÷
original-test runtime, both run normally (no agent, no delay), measured
after the synchronization patch is actually applied to source
**What I measured - a clean, real baseline:**
```
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
mvn -q test -Dtest=delight.nashornsandbox.TestGetFunction#test
```
5 runs: 12.39s (first, JVM/dependency warmup), then **2.31s, 2.35s, 2.32s,
2.24s** - steady state **≈2.2–2.3s**, reasonably close to Table 1's stated
3.07s for this test on the authors' machine.
**Why the actual ratio is not in this session's results:** the paper's
overhead metric needs the *repaired* test - source with FlakeSync's
synchronization patch actually applied - run normally and timed. The shipped
`scripts/` pipeline exposes CritSearch (`root_method_and_critical_point_search.sh`)
and BarrierSearch (`barrier_point_search.sh`), both of which run the test
**under instrumentation** (an attached delay/wait agent) to *find* the fix - that is a fundamentally more expensive operation than running an
already-patched test once, and its timing (44–62s search time, already
recorded above) is not a stand-in for the RQ4 number. No separate
"apply the patch as a source-code diff, then run normally" step was found
in the shipped scripts within this session's time budget - Section 3.3 of
the paper describes this as something a developer would do manually with
the reported critical/barrier point information, which the shipped artifact
does not appear to automate as output.
**Gap:** a genuine baseline now exists on this machine for a fair future
comparison; producing the actual overhead ratio needs either finding an
automated patch-application step this session missed, or manually applying
the synchronization pattern from Figure 1 of the paper using the critical
point (`JsEvaluator#53~54, 67~68`) and barrier point
(`NashornSandboxImpl#233`) this session already confirmed match ground
truth. Left as explicit follow-up rather than reported as a number.
**Log:** findings/logs/flakesync/overhead-baseline.sh, WSL
`~/flakesync-overhead/run-*.log`

## [STALENESS] - benchmark entries that no longer reproduce

### 2026-09-21 - M7 (dubbo-config-api) also fails: "Could not find the selected project in the reactor" `[STALENESS]` (unconfirmed cause)
**Target:** `apache/dubbo`, module `dubbo-config-api`, pinned SHA
`737f7a7ea67832d7f17517326fb2491d0a086dd7` (Table 1 M7)
**Command:** `mvn -q -pl dubbo-config-api -am clean test-compile`, staleness
sample (Module 2, Step 12)
**Observed:** same error class as the M22 failure above - `Could not find
the selected project in the reactor: dubbo-config-api`. **Unlike M22, this
one used the correctly pinned commit**, not `master` - so the `master`-vs-SHA
explanation does not apply here.
**Caveat, stated honestly:** dubbo is known to nest its modules
(`all_input.csv`'s own dubbo rows use `dubbo-remoting/dubbo-remoting-netty`
and `dubbo-rpc/dubbo-rpc-dubbo`, not bare `dubbo-remoting-netty` /
`dubbo-rpc-dubbo`). Table 1's text gives the module as the bare
`dubbo-config-api`, and this staleness check used that bare form. It is not
yet confirmed whether the correct path is `dubbo-config/dubbo-config-api`
(a naming-convention gap in the paper's own Table 1, and in this replication's
sampling script) or whether the module has genuinely been removed/renamed at
this commit. Recorded as-is rather than silently discarded; the fix (retry
with the nested path) is cheap and left for a follow-up run.
**Log:** WSL `~/flakesync-staleness/M7-build.log`, `~/flakesync-staleness/summary.txt`
**Resolved - confirmed:** retried with `mvn -q -pl dubbo-config/dubbo-config-api
-am clean test-compile` → **EXIT=0, clean build.** **Conclusion: this is a
notation gap, not staleness.**
Table 1 abbreviates dubbo's module names without their parent directory
(`dubbo-config-api` instead of `dubbo-config/dubbo-config-api`), matching the
pattern already visible in the artifact's own `all_input.csv`
(`dubbo-remoting/dubbo-remoting-netty`, `dubbo-rpc/dubbo-rpc-dubbo`). M10
(`dubbo-rpc-http`) almost certainly has the same explanation
(`dubbo-rpc/dubbo-rpc-http`) - not independently retried, but noted here
rather than double-counted as a second real staleness hit.

### 2026-09-21 - M21 (Achilles): genuine staleness - unpinned plugin resolved to a version needing a newer JDK `[STALENESS]`
**Target:** `doanduyhai/Achilles`, module `integration-test`, SHA
`f52f7ec93b3da758119dbbbc1be8dad8e8783764` (Table 1 M21)
**Command:** `mvn -q -pl integration-test -am clean test-compile`, JDK 8
(matching this whole staleness sample's environment)
**Observed:** `BUILD EXIT=1`. Root cause, from the actual Maven error (not
just the generic wrapper):
```
java.lang.UnsupportedClassVersionError: aQute/bnd/osgi/Analyzer has been
compiled by a more recent version of the Java Runtime (class file version
61.0), this version of the Java Runtime only recognizes class file versions
up to 52.0
```
Class file version 52.0 = Java 8; version 61.0 = Java 17. Maven resolved
`org.apache.felix:maven-bundle-plugin:6.2.0` - a version that requires
Java 17+ to run - because the project's `pom.xml` does not pin the plugin
version, so Maven always resolves the latest release from Maven Central
regardless of when the project was last touched.
**Gap:** this is genuine, textbook dependency drift - the exact mechanism
the paper's own Section 5.5 gestures at ("could no longer build them at this
latest commit") but never demonstrates concretely. One year-plus after the
FlakeSync paper's evaluation, one of its 37 subject modules fails to build
under the paper's own stated JDK for a reason that has nothing to do with
the project's source code changing - only the build tooling ecosystem
moving forward under it. **Retrying under JDK 17 instead of JDK 8 would very
likely fix this** (untested - left as a follow-up, since the paper's stated
environment is Java 8/Ubuntu 20.04 and switching JDKs to work around this
would itself be a deviation worth flagging, not a silent fix).
**Log:** WSL `~/flakesync-staleness/M21-build.log`

### Staleness sample summary (Module 2, Step 12) - final tally
**10 of 37 modules sampled** (random, seeded, recorded before running):
**7 clean** (M31, M25, M14, M33, M22-at-pinned-SHA, M12, M36) · **1 notation
gap, not real staleness** (M7, resolved) · **1 likely same notation gap,
unconfirmed** (M10) · **1 genuine staleness** (M21, unpinned plugin drift).
**Headline: at most 1 of 10 (10%), and possibly 0 of 10, sampled FlakeSync
evaluation modules have a genuine build-breaking staleness problem 21+
months after publication** - a much lower rate than the paper's own
300→221 (26% dropped) funnel during original construction, suggesting most
of FlakeSync's evaluation set remains buildable well after publication, once
module-path notation is accounted for correctly.

### 2026-09-21 - M22 (elasticjob) fails to build: `master` checkout resolved to a restructured repo `[STALENESS]` `[CONFIG-DEPENDENT]`
**Target:** `elasticjob/elastic-job-lite`, module `elasticjob-infra/elasticjob-infra-common`,
test `org.apache.shardingsphere.elasticjob.infra.concurrent.ElasticJobExecutorServiceTest#assertCreateExecutorService`
**Paper says:** Table 1 M22 - 1 flaky test, buildable, 4.91s runtime, repaired
(overhead 0.95×)
**Command:** the artifact's own `end_to_end_flakesync.sh`, run via `runAll.sh`'s
`mvn install -pl elasticjob-infra/elasticjob-infra-common -am -DskipTests`,
inside the shipped Docker image
**Observed:** `ERROR: Could not find the selected project in the reactor:
elasticjob-infra/elasticjob-infra-common`. Root cause: `scripts/data_list/all_input.csv`
records this row's SHA field as the literal string **`master`**, not a pinned
commit - already flagged in Module 1 as a reproducibility gap. Checking out
`master` today resolves to a version of the repository restructured since the
artifact was built (Jan 2024): the project appears to have moved under the
`org.apache.shardingsphere.elasticjob` package/org, and the module path
`elasticjob-infra/elasticjob-infra-common` no longer exists in that state of
the reactor.
**Gap:** this is a direct, concrete confirmation of the `master`-vs-SHA gap
noted in Module 1 - not a hypothetical risk. One of the artifact's own two
demo-adjacent test rows cannot be reproduced through its own shipped pipeline,
21 months after the artifact was built, specifically because that one row
was not pinned the way every other row is.
**Log:** findings/logs/flakesync/ (Docker container `flakesync-run1`,
`flaky-study/fs-output/run1.log` lines 1-90, 609)
**Confirmed by a controlled comparison:** Module 2's staleness sample
independently drew this exact project (`elasticjob/elastic-job-lite`,
module `elasticjob-infra/elasticjob-infra-common`) but at Table 1's actual
**pinned SHA `9afe466`**, not `master`. Result: `mvn -q -pl
elasticjob-infra/elasticjob-infra-common -am clean test-compile` - **BUILD
EXIT=0**, clean. Same project, same module path, same machine - the only
variable that changed was pinning the commit instead of using `master`. This
directly isolates the cause: the project itself is fine at its recorded
commit; the artifact's own `all_input.csv` row is what is broken, purely
from using a moving ref for one specific test.
**Cross-check against IDoFT:** IDoFT tracks this project under
`apache/shardingsphere-elasticjob` (org changed) with test package
`io.elasticjob.lite.*` - different from the `org.apache.shardingsphere.elasticjob`
namespace in FlakeSync's `all_input.csv` row. Two independent signs of the
same rename, confirming the build failure is a real staleness event, not a
local misconfiguration. `delight-nashorn-sandbox` (T2) does **not** appear in
IDoFT's `pr-data.csv` at all - zero hits, recorded as a `[NULL]` cross-check.

### 2026-09-21 - delight-nashorn-sandbox: FlakeSync (async) vs NonDex (ID) on the same project `[DISAGREEMENT]` (partial, pending run completion)
**Target:** `javadelight/delight-nashorn-sandbox`
**Cross-check:** NonDex ran on this exact project in the earlier work
(see `nondex_findings.md` in the original study) and returned an **empty summary** - no unguaranteed-iteration-order (ID) flakiness found, a genuine null result.
FlakeSync's Table 1 (M26) claims this project has **1 NOD/async-flaky test**
(`delight.nashornsandbox.TestGetFunction#test`) which it repairs with overhead
0.91×. The two techniques target different categories (ID vs async), so
disagreement is not automatically a contradiction - but it does mean this one
small project has, per two independent tools, **zero** ID-flakiness and
**one** claimed async-flakiness. Whether FlakeSync's run (in progress)
actually reproduces that claim on this machine is the real test. To finalize
once the container run completes.

## [PLATFORM] - OS-specific breaks

### 2026-09-21 - FlakeSync's pom-injection step silently fails on native Windows: POSIX paths handed to a Windows-native `java.io.File` `[PLATFORM]`
**Target:** `scripts/agent-pom-modify/modify-project.sh` + `PomFile.java`,
run natively on Windows (git-bash shell, Windows JDK - not WSL, not Docker) - this is the plan's deliberate Module 6 break test (Step 29)
**Command:**
```bash
export JAVA_HOME="C:/Users/Tanzim/.jdks/corretto-1.8.0_412"
export PATH="$JAVA_HOME/bin:$PATH"
bash modify-project.sh "C:/PHD/.../delight-nashorn-sandbox" 0 minimizer
```
**Observed:**
```
File does not exit: /c/PHD/redacted/Tools/flaky-study/windows-native-test/delight-nashorn-sandbox/pom.xml
C:\c\PHD\redacted\Tools\flaky-study\windows-native-test\delight-nashorn-sandbox
File does not exit: /c/PHD/redacted/Tools/flaky-study/windows-native-test/delight-nashorn-sandbox/pom.xml
```
**Root cause, confirmed by reading `PomFile.java`:**
`modify-project.sh` runs `find ${project_path} -name pom.xml | grep -v
"src/" | java PomFile ${ARG_LINE} ${surefire_exists}` - `find`, running under
git-bash, emits **POSIX-style paths** (`/c/PHD/...`). `PomFile.java` (line
53) does `new File(pom)` directly on each line read from stdin. Java's
`java.io.File`, running under a **native Windows JVM**, cannot resolve
`/c/...`-style paths - it needs `C:\...` or `C:/...`. The check at line 103
(`if (!pomFile.exists())`) fails silently: it prints a message (containing
the artifact's own typo, "exit" instead of "exist") and **returns without
modifying the pom or attaching the FlakeSync agent** - no exception, no
non-zero exit code propagated to the calling shell script.
**Gap:** this is a real, distinct, concretely diagnosed Windows failure - the
third one found in this research line (after NonDex's Windows path-parsing
bug in `nondex:debug`, and iDFlakies' file-lock-on-delete bug), each with a
**different underlying mechanism**. Here specifically: a shell pipeline
mixing a POSIX-path-emitting tool (`find` under git-bash) with a
native-Windows JVM that expects Windows-style paths. The failure mode is
worse than a crash - the pipeline **continues** past this silent failure with
no agent attached, meaning any test run afterward would report "no boundary
found" (indistinguishable from a genuine null result) rather than an
obvious error. This is exactly the "some problems" iDFlakies' own docs
gesture at for Windows without ever naming - and here it recurs in an
entirely different, unrelated tool from the same research group.
**Log:** findings/logs/flakesync/windows-break-attempt.log

## [NULL] - deliberate negative results

## [IMPROVEMENT] - concrete changes that would fix something observed
