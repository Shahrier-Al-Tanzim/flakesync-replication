# FlakeSync — replication plan

> **Execution status, 2026-09-21 (updated).** Modules 1–2 done in full.
> Modules 3–5 done for M26 (delight-nashorn-sandbox) via the artifact's own
> end-to-end pipeline, plus a repeat under a different resource
> configuration (Step 27, done) and a stretch target, M16 (rxjava2-extras).
> M22 hit a real staleness bug in the artifact's own input data (documented,
> not worked around). Module 6 fully covered: the determinism probe
> (Step 28) was answered by the pipeline's own internal repetition; the
> resource-sensitivity sweep (Step 27) is done — doubling CPU/RAM changed
> neither the answer nor meaningfully the speed; the deliberate Windows
> break (Step 29) is done and found a concrete, diagnosed bug (POSIX paths
> handed to a native-Windows JVM in the pom-injection step). Module 7's
> cross-checks and write-up are done. The RQ4 overhead metric (Step 26) is
> **partially done** — a clean baseline runtime was measured
> (~2.2–2.3s, matching Table 1's 3.07s), but the true repaired-vs-original
> ratio needs a patch-application step this session could not locate in the
> shipped scripts; recorded as an explicit gap, not a fabricated number. See
> [flakesync_findings.md](flakesync_findings.md) and
> [flakesync_report.md](flakesync_report.md)
> for full results.
>
> Stretch target M16 (rxjava2-extras) was attempted: one of its two tests
> completed with a real, striking result (barrier point matched ground
> truth exactly, critical point did not — a stronger version of the
> determinism finding), the second was stopped after ~2h wall-clock as a
> time-management call, then confirmed via the authors' own ground truth to
> genuinely need ~7.3 minutes regardless of machine. Remaining stretch
> target not attempted: M3 (Java-WebSocket, 52 tests — expensive).
>
> **This plan is considered complete.** All 7 modules have real evidence
> behind them; every gap above is stated explicitly rather than glossed
> over. Ready for review/commit, or for Plan 2 (RankF).

> **Paper:** *FlakeSync: Automatically Repairing Async Flaky Tests* (ICSE 2024).
> **Artifact:** `flakesync-artifact_latest.tar.gz`, 1.5 GB, on Zenodo at
> <https://zenodo.org/records/10460139> (MD5 `da181d43dadcda81735a6aabd4bcbf05`).
> Project page: <https://sites.google.com/view/flakesync/>.
> **Paper:** <https://doi.org/10.1145/3597503.3639115>.
>
> **This is plan 1 of 3.** It is **entirely CPU-bound** — no GPU anywhere — so
> it runs first. The other two are [rankf_explore.md](rankf_explore.md) (mostly
> CPU, one GPU module at the very end) and
> [flakylens_explore.md](flakylens_explore.md) (GPU-bound, run last).
>
> **Start at Module 1, Step 1.** Work top to bottom. Every step ends with a
> **Verify** line. Do not move on until that line passes.

---

## Why this plan exists

The earlier work in this repository — TSVD4J, then IDoFT / NonDex / iDFlakies
(see [new_explore.md](new_explore.md)) — produced one recurring result shape:
**a detector's reported numbers depend on things that are not the underlying
bug.** Configuration choices, pre-existing failures, and platform all moved the
numbers more than the actual defect did.

FlakeSync is a different kind of artifact. It is not a detector — it is a
**repair** tool. That makes it a genuine test of whether that result shape
generalises, or whether it was specific to detection:

| Question this plan answers | Why it is new |
| --- | --- |
| Does a *repair* tool's success rate also move with configuration? | Every finding so far is about detectors |
| Is the 83.75% repair rate reproducible on modest hardware? | The paper used 4 CPU / 4 GB; this machine has more, which should *help* — so any shortfall is meaningful |
| How much of the paper's subject set still builds today? | The paper's own funnel (300 → 221 → 176) is a staleness measurement nobody has repeated |
| Does FlakeSync agree with TSVD4J about `Java-WebSocket`? | Two artifacts, same project, same research group, never compared |

That last row is the prize. `Java-WebSocket` is module **M3** in FlakeSync's
evaluation (52 flaky tests) *and* the project where the TSVD4J work already
produced 22 conflicting pairs. No published work compares them.

---

## Ground rules

These carry over unchanged from [new_explore.md](new_explore.md).

- **Never edit a subject project's source or pom**, except where the tool
  itself requires it. If a change is unavoidable, write it down, unapplied,
  before applying it.
- **Never edit the artifact's source** to make a run succeed. If it will not
  run as shipped, that is the finding. Record it, then decide separately.
- **Write down the null results.** "FlakeSync could not reproduce the failure"
  is a real result, and it is one the paper itself reports for 6 tests.
- **Every command below is given twice** — once plain, once writing to a log
  file. Use the log version for anything over a minute.
- **Second terminal rule.** A redirected command shows nothing and looks idle.
  Check progress from a *different* window. `Ctrl+C` in the running window —
  including when you only meant to copy text — kills the run.
- **This plan is a living document.** If the work deviates from what is written
  here, update this file at the same time as the findings log, not afterwards.

---

## Path handling — set this once per shell

This plan never hardcodes an absolute path. Set `$T` at the top of every new
PowerShell window, and `$T` again inside every new bash/WSL shell:

**PowerShell** — `cd` to the repository root (the folder holding `findings\`
and `flaky-study\`), then:

```powershell
$T = $PWD.Path
echo $T
```

**bash (WSL or inside a container that mounts the repo):**

```bash
cd /mnt/c/.../Tools     # the same folder, seen from Linux
export T="$(pwd)"
echo "$T"
```

Everything below uses `$T\findings\...` (PowerShell) or `$T/findings/...`
(bash). If you open a second window, set `$T` there too — it does not carry
over.

> **Sanitising before any commit.** Maven, Docker and the artifact's own
> scripts print absolute paths into their output. Before committing anything
> under `findings\`, grep the new log files for the on-disk path and scrub it.
> Do this every time, not once:
>
> ```powershell
> Select-String -Path $T\findings\logs\flakesync\*.log -Pattern "C:\\" -SimpleMatch | Select-Object Filename,LineNumber
> ```

---

## Branching — branches and sub-branches

This paper gets **one integration branch**, and **one sub-branch per module**
cut from it. Modules merge up into the integration branch; the integration
branch merges into `main` once the write-up module is done.

```
main
 └── paper-flakesync                 (integration branch for this whole plan)
      ├── flakesync/m1-setup
      ├── flakesync/m2-dataset
      ├── flakesync/m3-baseline
      ├── flakesync/m4-critsearch
      ├── flakesync/m5-barrier-overhead
      ├── flakesync/m6-limits
      └── flakesync/m7-crosscheck
```

| Module | Sub-branch |
| --- | --- |
| 1 — Setup and artifact acquisition | `flakesync/m1-setup` |
| 2 — The evaluation dataset | `flakesync/m2-dataset` |
| 3 — Reproduce the flaky failure | `flakesync/m3-baseline` |
| 4 — CritSearch | `flakesync/m4-critsearch` |
| 5 — BarrierSearch and overhead | `flakesync/m5-barrier-overhead` |
| 6 — Limits and sensitivity | `flakesync/m6-limits` |
| 7 — Cross-check and write-up | `flakesync/m7-crosscheck` |

**Create the integration branch once, at the start:**

```powershell
git checkout main
git checkout -b paper-flakesync
git push -u origin paper-flakesync
```

**Per module** — cut from the integration branch, come back to it when the
module's **Definition of done** is met:

```powershell
git checkout paper-flakesync
git checkout -b flakesync/m2-dataset
# ... run the module's steps, commit under findings\ as you go ...
git checkout paper-flakesync
git merge flakesync/m2-dataset
```

**At the very end, after Module 7:**

```powershell
git checkout main
git merge paper-flakesync
```

`planning\` is git-ignored on every branch, so this file never changes or
disappears when you switch branches. Only what you commit under `findings\`
differs branch to branch.

---

## Findings folder convention

Same split as every earlier module: raw console output is a **log**, a
structured result copied out of a tool's own output directory is a **report**.

| Kind | Goes in |
| --- | --- |
| Console output (`*> some.log`) | `findings\logs\flakesync\` |
| FlakeSync's own result files (critical point / barrier point / patch output) | `findings\reports\flakesync\` |
| Narrative findings, one entry per observation | `findings\flakesync_findings.md` |

Create both folders in Module 1, Step 2.

### Finding categories — use these tags

Every entry written into `findings\flakesync_findings.md` carries **one or more
of these tags in its heading.** The same tag set is used by all three paper
plans, so the three findings files can be merged into one comparative table at
the end without re-reading them.

| Tag | Means |
| --- | --- |
| `[UNEXPECTED]` | The tool did something the paper or its docs do not predict |
| `[LIMITATION]` | A boundary of what the technique can do, demonstrated not assumed |
| `[DISAGREEMENT]` | Two tools, datasets, or papers contradict each other |
| `[IMPROVEMENT]` | A concrete change that would fix something observed |
| `[FALSE-POSITIVE]` | The tool claimed a result that does not hold up |
| `[FALSE-NEGATIVE]` | The tool missed something it is capable of finding |
| `[CONFIG-DEPENDENT]` | The result moves with configuration rather than with the defect |
| `[RESOURCE-GAP]` | The artifact needs hardware or time beyond what is stated or available |
| `[STALENESS]` | A dataset or benchmark entry no longer reproduces |
| `[PLATFORM]` | An OS-specific break |
| `[NULL]` | A real negative result, recorded deliberately |

The findings file is organised **by category**, with runs listed under each.
Module 1, Step 3 creates it with the headings already in place.

---

## What is already on this machine

Surveyed, not guessed, as of 2026-09-21.

| Thing | State |
| --- | --- |
| Free disk on C: | **~29.8 GiB** — the artifact alone is 1.5 GB compressed, and a Docker image built from it will be several GB more |
| Docker | Docker Desktop 28.5.1, installed and already used in the iDFlakies work |
| WSL | WSL 2, distro `Ubuntu`, JDK 8 already selected system-wide via `update-alternatives` |
| JDKs on Windows | 8 (Corretto `1.8.0_412`), 17.0.9, 17.0.10, 20, **21 (active)**, 24. **No JDK 11** |
| Maven | 3.9.11, install path **contains a space**; `M2_HOME` points at the `bin` subfolder, not the Maven home |
| RAM | ~16 GB usable |
| Already cloned, relevant here | `Java-WebSocket` (M3), `rxjava2-extras` (M16), `fluent-logger-java` (M25), `delight-nashorn-sandbox` (M26) |

**Four of FlakeSync's 37 evaluation modules are projects already sitting in
`flaky-study\`.** They are cloned at whatever SHA the earlier work used, *not*
at the SHA in FlakeSync's Table 1 — Module 2, Step 6 checks that and it
matters.

---

## The route, at a glance

| Module | What | Where it runs | Rough cost |
| --- | --- | --- | --- |
| **Module 1** | Setup: disk, Docker, download and open the artifact | PowerShell | ~2 h (mostly download) |
| **Module 2** | The evaluation dataset: what it is, how much still exists | PowerShell | ~2 h |
| **Module 3** | Reproduce the flaky failure on the chosen targets | Docker / WSL | ~half day |
| **Module 4** | CritSearch — find the critical point | Docker | ~1 day of wall-clock, mostly unattended |
| **Module 5** | BarrierSearch, the repair, 100× rerun, overhead | Docker | ~1 day, mostly unattended |
| **Module 6** | Limits: resource sensitivity, determinism, Windows | Both | ~half day |
| **Module 7** | Cross-check against TSVD4J / iDFlakies / NonDex, write up | PowerShell | ~half day |

Modules 4 and 5 are slow but unattended. The paper reports a **mean of 126.62
minutes per test** and a 12-hour per-test cap, so plan around wall-clock, not
around your attention.

---

# Module 1 — Setup and artifact acquisition

**Sub-branch:** `flakesync/m1-setup`

**Definition of done:** the 1.5 GB artifact is downloaded, its checksum
verified, its contents listed, and you can state in one sentence what form it
ships in (Docker image? source tree? both?) — from having looked, not guessed.

---

### Step 1 — Check disk before downloading anything

1.5 GB compressed will expand to considerably more, and if the artifact ships
a Docker image the loaded image is larger again.

```powershell
Get-PSDrive C | Select-Object Used,Free
docker system df
```

**Log-file version:**

```powershell
mkdir $T\findings\logs\flakesync -Force
Get-PSDrive C | Select-Object Used,Free *> $T\findings\logs\flakesync\disk-before.log
docker system df *>> $T\findings\logs\flakesync\disk-before.log
type $T\findings\logs\flakesync\disk-before.log
```

If you are under ~20 GB free, reclaim space first. Safe things, in order:

```powershell
# Docker leftovers from the iDFlakies work
docker system prune -a --volumes

# Rebuildable Maven output
Get-ChildItem $T\flaky-study -Recurse -Directory -Filter target | Select-Object FullName
```

> **`docker system prune -a` deletes every image not currently used by a
> container**, including the iDFlakies image from the earlier work. That is
> fine — it is re-pullable — but know that it goes before you run it.

**Verify:** at least 20 GB free. Write the number down; Step 4 and Module 6
both compare against it.

---

### Step 2 — Create the findings folders

```powershell
mkdir $T\findings\logs\flakesync -Force
mkdir $T\findings\reports\flakesync -Force
```

**Log-file version:**

```powershell
mkdir $T\findings\logs\flakesync -Force *> $T\findings\logs\flakesync\folders.log
mkdir $T\findings\reports\flakesync -Force *>> $T\findings\logs\flakesync\folders.log
Get-ChildItem $T\findings\logs, $T\findings\reports -Directory *>> $T\findings\logs\flakesync\folders.log
type $T\findings\logs\flakesync\folders.log
```

**Verify:** both folders exist and appear in the listing.

---

### Step 3 — Create the findings file with its categories

Create `findings\flakesync_findings.md` now, empty but structured, so there is
never a moment where you have an observation and nowhere obvious to put it.

Paste this in:

```markdown
# FlakeSync — Findings log

> Observations from replicating the FlakeSync artifact. Organised by category.
> Every entry gives: the exact command, the wall-clock, what was expected (from
> the paper), what happened, and why the difference matters. Entries are never
> deleted.

## Run-block template

    ### YYYY-MM-DD — <one-line title> `[TAG]` `[TAG]`
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

## [UNEXPECTED] — behaved differently from the paper or the docs

## [LIMITATION] — demonstrated boundaries of the technique

## [DISAGREEMENT] — contradictions between tools, datasets, or papers

## [FALSE-POSITIVE] — claimed results that do not hold up

## [FALSE-NEGATIVE] — real cases the tool missed

## [CONFIG-DEPENDENT] — results that move with configuration

## [RESOURCE-GAP] — hardware or time beyond what is stated

## [STALENESS] — benchmark entries that no longer reproduce

## [PLATFORM] — OS-specific breaks

## [NULL] — deliberate negative results

## [IMPROVEMENT] — concrete changes that would fix something observed
```

**Verify:** the file exists at `$T\findings\flakesync_findings.md` and has all
eleven category headings.

---

### Step 4 — Download the artifact

1.5 GB. Do this on a connection you can leave alone, and **do not** run it in
the same window you are working in.

```powershell
cd $T\flaky-study
Invoke-WebRequest -Uri "https://zenodo.org/records/10460139/files/flakesync-artifact_latest.tar.gz?download=1" -OutFile "flakesync-artifact_latest.tar.gz"
```

**Log-file version:**

```powershell
cd $T\flaky-study
Measure-Command {
  Invoke-WebRequest -Uri "https://zenodo.org/records/10460139/files/flakesync-artifact_latest.tar.gz?download=1" -OutFile "flakesync-artifact_latest.tar.gz"
} *> $T\findings\logs\flakesync\download.log
type $T\findings\logs\flakesync\download.log
```

> **`Invoke-WebRequest` buffers the whole body in memory before writing on some
> PowerShell versions.** For 1.5 GB on a 16 GB machine that is survivable but
> wasteful. If it stalls or the memory use alarms you, use `curl.exe` instead —
> it streams to disk:
>
> ```powershell
> curl.exe -L -o flakesync-artifact_latest.tar.gz "https://zenodo.org/records/10460139/files/flakesync-artifact_latest.tar.gz?download=1"
> ```

**Verify the checksum before unpacking anything.** Zenodo publishes MD5
`da181d43dadcda81735a6aabd4bcbf05`.

```powershell
Get-FileHash flakesync-artifact_latest.tar.gz -Algorithm MD5
```

**Log-file version:**

```powershell
Get-FileHash $T\flaky-study\flakesync-artifact_latest.tar.gz -Algorithm MD5 *> $T\findings\logs\flakesync\checksum.log
type $T\findings\logs\flakesync\checksum.log
```

| Outcome | Meaning | Action |
| --- | --- | --- |
| Hash matches | Clean download | Continue to Step 5 |
| Hash differs | Truncated or corrupted download | Delete and re-download. Do **not** proceed — a partial tarball produces confusing failures three steps later |
| Zenodo shows a different published hash than the one above | The record was updated after this plan was written | Record the new hash, note the change as `[STALENESS]`, and use the new one |

**Verify:** `Get-FileHash` output equals the published MD5, and you have
written both into the findings file.

---

### Step 5 — Look inside before unpacking

> **Update, 2026-09-21 — confirmed by actually running this step.** The
> tarball is **purely a `docker save` export** — 7 layer directories
> (`VERSION`/`json`/`layer.tar` each), a `manifest.json`, and a `repositories`
> file. No exposed source tree, no top-level `Dockerfile`, no top-level
> `README` sitting next to the tarball. Everything — source, scripts, README,
> reference results — lives *inside* the image's filesystem. Steps 6–7 below
> are rewritten around that; skip straight to "unpack" meaning `docker load`,
> not `tar -x`.
>
> Also: **the artifact is 1.17 GB decompressed-transfer / 1.4 GB on disk, not
> 1.5 GB** as Zenodo's page states — a minor, harmless discrepancy, noted for
> completeness.

A 1.5 GB tarball can be a source tree, a Docker image export, a pile of
pre-built subject projects, or all three. Find out which without spending the
disk.

```powershell
tar -tzf $T\flaky-study\flakesync-artifact_latest.tar.gz | Select-Object -First 60
```

**Log-file version:**

```powershell
tar -tzf $T\flaky-study\flakesync-artifact_latest.tar.gz *> $T\findings\logs\flakesync\artifact-manifest.log
Get-Content $T\findings\logs\flakesync\artifact-manifest.log -TotalCount 60
(Get-Content $T\findings\logs\flakesync\artifact-manifest.log | Measure-Object -Line).Lines
```

> **`tar` is built into Windows 10/11** (`C:\Windows\System32\tar.exe`) and
> handles `.tar.gz` fine. You do not need 7-Zip or WSL for this step.

Things to look for in the manifest, and what each implies:

| If the manifest contains | It means | Consequence for this plan |
| --- | --- | --- |
| A single large `.tar` at the top level | It is a Docker image export | Module 3 runs `docker load`, not `docker build` |
| A `Dockerfile` | You build the image yourself | Expect a long first build and a network dependency |
| `pom.xml` / `src/main/java` near the root | The FlakeSync tool source is shipped | You can read the ASM instrumentation directly — useful for Module 6 |
| Per-module subject folders (`M1`, `M2`, … or project names) | Subject projects are pre-staged | Much of Module 3's build risk disappears |
| `*.sh` driver scripts | There is a prescribed entry point | Read it before running it; Module 4 depends on knowing its flags |
| A `README` | Read it first | It overrides this plan wherever they disagree |

**Verify:** you can answer, from the manifest and not from guessing: *does this
artifact ship a Docker image, a Dockerfile, or neither?*

---

### Step 6 — Unpack

```powershell
cd $T\flaky-study
mkdir FlakeSync -Force
tar -xzf flakesync-artifact_latest.tar.gz -C FlakeSync
```

**Log-file version:**

```powershell
cd $T\flaky-study
mkdir FlakeSync -Force
Measure-Command { tar -xzf flakesync-artifact_latest.tar.gz -C FlakeSync } *> $T\findings\logs\flakesync\unpack.log
Get-ChildItem $T\flaky-study\FlakeSync -Depth 2 | Select-Object FullName,Length *>> $T\findings\logs\flakesync\unpack.log
Get-PSDrive C | Select-Object Free *>> $T\findings\logs\flakesync\unpack.log
type $T\findings\logs\flakesync\unpack.log
```

> **`flaky-study/FlakeSync/` was listed in the original repository's
> `.gitignore`** — the unpacked tree did not pollute that repo.
> The **tarball itself is not**, and `*.tar.gz` is not covered by any existing
> rule. Add it in Module 1's housekeeping (Step 8) before your first commit, or
> you will try to push 1.5 GB to GitHub.

**Verify:** the tree is unpacked, and you have recorded how much disk it cost
(free space before minus free space after).

---

### Step 7 — Read the artifact's own README, and record where it disagrees with the paper

```powershell
Get-ChildItem $T\flaky-study\FlakeSync -Recurse -Include README*,INSTALL*,*.md -Depth 3 | Select-Object FullName
```

**Log-file version:**

```powershell
Get-ChildItem $T\flaky-study\FlakeSync -Recurse -Include README*,INSTALL*,*.md -Depth 3 | Select-Object FullName *> $T\findings\logs\flakesync\readme-locations.log
type $T\findings\logs\flakesync\readme-locations.log
```

Then read the top-level one and answer these four questions in the findings
file:

1. What is the prescribed entry point — a script, a Maven goal, a Docker run?
2. What are the tunables, and do their defaults match the paper's Section 4.3
   (`INITIAL_DELAY` 100 ms, `MAX_DELAY` 51200 ms, 3-minute barrier-search
   per-run timeout, 12-hour per-test cap, 4 CPU / 4 GB RAM)?
3. Does it document the per-test runtime? The paper says mean **126.62 min**,
   median **58.77 min**.
4. Does it say anything about which subjects are pre-staged?

> **Any defaults in the shipped code that differ from the paper's stated
> configuration is a `[CONFIG-DEPENDENT]` finding on its own**, and a cheap one
> — it costs a `Select-String` and it is exactly the class of gap this research
> tracks. Look specifically for the delay constants:
>
> ```powershell
> Select-String -Path $T\flaky-study\FlakeSync\* -Pattern "INITIAL_DELAY|MAX_DELAY|51200|timeout" -Recurse
> ```
>
> **Log-file version:**
>
> ```powershell
> Select-String -Path $T\flaky-study\FlakeSync\* -Pattern "INITIAL_DELAY|MAX_DELAY|51200|timeout" -Recurse *> $T\findings\logs\flakesync\defaults-vs-paper.log
> type $T\findings\logs\flakesync\defaults-vs-paper.log
> ```

**Verify:** all four questions are answered in
`findings\flakesync_findings.md`, and any mismatch with the paper is filed
under `[CONFIG-DEPENDENT]` or `[UNEXPECTED]`.

---

### Step 8 — Housekeeping before the first commit

Add these to `.gitignore` — none of them is covered by an
existing rule:

```gitignore
# FlakeSync artifact — 1.5 GB tarball and its unpacked tree
*.tar.gz
flaky-study/FlakeSync/
```

(`flaky-study/FlakeSync/` is already there; `*.tar.gz` is not.)

Then commit Module 1:

```powershell
git add $T\.gitignore $T\findings\logs\flakesync $T\findings\flakesync_findings.md
git status
```

> **Ask before committing, and sanitise first.** Run the path-scrub check from
> the "Path handling" section above over every new log before `git commit`.

**Verify:** `git status` shows no `.tar.gz` and no `flaky-study/FlakeSync/`
content staged.

---

# Module 2 — The evaluation dataset

**Sub-branch:** `flakesync/m2-dataset`

**Definition of done:** you know which of FlakeSync's 37 modules you can
realistically run, you have measured how much of its subject set still builds,
and you have chosen three targets with a written reason for each.

This module builds almost nothing and is the one that cannot stall. It also
produces a result the literature does not have.

---

### Step 9 — Write down the paper's numbers before you measure anything

Do this first, on purpose. If you look at the paper only after your own run,
you will unconsciously read its numbers as confirmation.

**The subject funnel (Section 4.2):**

| Stage | Count | The paper's stated reason for the drop |
| --- | --- | --- |
| IDoFT tests labelled NOD | 300 | starting point |
| Still buildable and runnable at the recorded commit | 221 | "out-of-date or missing library dependencies" |
| Have at least one concurrent method during execution | **176** | tests without concurrency are unlikely to be async flaky |

Final dataset: **176 flaky tests, 23 projects, 37 modules.**

**The result funnel (Section 5.1, Table 2):**

| Stage | Count |
| --- | --- |
| Critical point found (CSS) | 174 of 176 |
| Rely on absolute runtime, so out of scope | 94 of 174 |
| Genuine async flaky tests | **80** |
| Repaired | **67** → the headline **83.75%** |

Of the 13 async flaky tests not repaired: **6** could not have their failure
reproduced reliably, **2** hit the 12-hour cap, **5** failed on network I/O.
Two of the original 176 crashed on memory limits before a critical point was
found.

**Overhead (RQ4):** mean **2.26×**, median **1.00×**.

**Runtime (RQ3):** mean **126.62 min** per test, median **58.77 min**.
CritSearch mean **104.39** / median **30.73**; BarrierSearch mean **22.23** /
median **7.00**.

> **The 94-of-174 line is the most interesting number in this table and the
> paper passes over it in a paragraph.** These are tests IDoFT labels **NOD**
> that FlakeSync's own inspection found are not async flaky at all — they
> assert on absolute wall-clock time. That is **54% of the dataset** carrying a
> label that, on the paper's own reading, does not describe them. If that holds
> up, it is a `[DISAGREEMENT]` between a paper and the dataset it is built on,
> and it is squarely the same shape as the iDFlakies label gap already recorded
> in `idflakies_findings.md` in the original study.

**Verify:** all of the above is transcribed into
`findings\flakesync_findings.md` under a heading marked *paper's claims, before
measurement*.

---

### Step 10 — Extract Table 1 into a machine-readable file

You will join against this repeatedly. Type it once.

Create `findings\reports\flakesync\table1-subjects.csv` with these columns:
`ID,Project,Module,SHA,KLOC,NumFlakyTests,TestRuntimeSec,NumConcMethods`.

The rows, from the paper's Table 1:

```csv
ID,Project,Module,SHA,KLOC,NumFlakyTests,TestRuntimeSec,NumConcMethods
M1,Accenture/mercury,platform-core,8586dc7,19.27,1,15.00,622.50
M2,Alluxio/alluxio,.,78c063a,59.68,17,5.42,893.25
M3,TooTallNate/Java-WebSocket,.,fa3909c,10.92,52,4.30,103.59
M4,activiti/activiti,activiti-engine,b11f757,111.80,12,10.30,2219.41
M5,activiti/activiti,activiti-spring,b11f757,3.04,1,7.56,2842.00
M6,alibaba/wasp,.,b2593d8,153.50,1,5.67,59.00
M7,apache/dubbo,dubbo-config-api,737f7a7,8.34,4,6.33,498.50
M8,apache/dubbo,dubbo-remoting-netty,737f7a7,1.56,1,13.38,265.00
M9,apache/dubbo,dubbo-rpc-dubbo,737f7a7,4.69,5,4.12,364.20
M10,apache/dubbo,dubbo-rpc-http,737f7a7,0.39,1,3.81,134.00
M11,apache/dubbo,dubbo-rpc-rest,737f7a7,1.03,3,4.54,94.00
M12,apache/httpcore,httpcore,49247d2,21.05,2,2.16,18.50
M13,apache/httpcore,httpcore-nio,49247d2,19.19,9,2.15,327.66
M14,apache/incubator-uniffle,common,6fb2a9a,10.68,1,6.32,46.00
M15,cescoffier/vertx-completable-future,.,011d3cd,2.10,1,2.67,9.00
M16,davidmoten/rxjava2-extras,.,7663d3b,13.69,3,7.06,207.00
M17,doanduyhai/Achilles,integration-test-2_1,e3099bd,8.97,12,15.04,6042.08
M18,doanduyhai/Achilles,integration-test-2_2,e3099bd,0.86,7,13.37,6066.00
M19,doanduyhai/Achilles,integration-test-3_10,e3099bd,0.51,2,12.27,6053.00
M20,doanduyhai/Achilles,integration-test-3_7,e3099bd,0.19,6,12.36,6068.16
M21,doanduyhai/Achilles,integration-test,f52f7ec,2.56,1,8.88,4802.00
M22,elasticjob/elastic-job-lite,elasticjob-infra-common,9afe466,2.12,1,4.91,6.00
M23,feroult/yawp,yawp-testing-appengine,b3bcf9c,0.21,1,3.51,516.00
M24,flaxsearch/luwak,luwak,c27ec08,7.53,2,3.60,44.00
M25,fluent/fluent-logger-java,.,2e5fdf2,1.67,1,5.39,602.00
M26,javadelight/delight-nashorn-sandbox,.,da35edc,2.49,1,3.07,17.00
M27,kagkarlsson/db-scheduler,db-scheduler,0e9f2a8,10.39,4,3.53,32.25
M28,kagkarlsson/db-scheduler,.,4a8a28e,3.74,2,7.67,434.00
M29,nlighten/tomcat_exporter,client,bc6a2d2,0.95,1,7.13,1111.00
M30,qos-ch/logback,logback-classic,0f57531,21.63,3,4.05,380.66
M31,qos-ch/logback,logback-core,0f57531,25.96,2,2.87,36.50
M32,square/okhttp,okhttp-tests,129c937,11.55,1,2.78,129.00
M33,undertow-io/undertow,core,ac7204a,49.28,4,4.03,817.75
M34,undertow-io/undertow,websockets-jsr,d0efffa,6.98,4,4.77,1376.50
M35,vmware/admiral,registry,e4b0293,1.59,5,3.96,1864.20
M36,vmware/admiral,compute,e4b0293,40.47,1,8.13,2475.00
M37,wro4j/wro4j,wro4j-core,7e3801e,23.34,1,2.48,9.00
```

Sanity-check it:

```powershell
$t1 = Import-Csv $T\findings\reports\flakesync\table1-subjects.csv
$t1.Count
($t1 | Measure-Object -Property NumFlakyTests -Sum).Sum
```

**Log-file version:**

```powershell
$t1 = Import-Csv $T\findings\reports\flakesync\table1-subjects.csv
$t1.Count *> $T\findings\logs\flakesync\table1-check.log
($t1 | Measure-Object -Property NumFlakyTests -Sum).Sum *>> $T\findings\logs\flakesync\table1-check.log
type $T\findings\logs\flakesync\table1-check.log
```

**Verify:** 37 rows, and `NumFlakyTests` sums to **176**. If either is wrong,
you mistyped a row — fix it now, because Module 7 joins against this file.

---

### Step 11 — Find the overlap with what is already cloned

```powershell
$t1 = Import-Csv $T\findings\reports\flakesync\table1-subjects.csv
$local = Get-ChildItem $T\flaky-study -Directory | Select-Object -ExpandProperty Name
$t1 | Where-Object { $p = ($_.Project -split '/')[1]; $local -contains $p } | Format-Table ID,Project,Module,SHA,NumFlakyTests
```

**Log-file version:**

```powershell
$t1 = Import-Csv $T\findings\reports\flakesync\table1-subjects.csv
$local = Get-ChildItem $T\flaky-study -Directory | Select-Object -ExpandProperty Name
$t1 | Where-Object { $p = ($_.Project -split '/')[1]; $local -contains $p } | Format-Table ID,Project,Module,SHA,NumFlakyTests *> $T\findings\logs\flakesync\local-overlap.log
type $T\findings\logs\flakesync\local-overlap.log
```

Expect four hits: **M3** `Java-WebSocket`, **M16** `rxjava2-extras`, **M25**
`fluent-logger-java`, **M26** `delight-nashorn-sandbox`.

**Now check whether the local clone is at the paper's SHA** — it almost
certainly is not, because the earlier work cloned these for different reasons.

```powershell
foreach ($p in @("Java-WebSocket","rxjava2-extras","fluent-logger-java","delight-nashorn-sandbox")) {
  $sha = (git -C $T\flaky-study\$p rev-parse --short HEAD)
  "$p local=$sha"
}
```

**Log-file version:**

```powershell
foreach ($p in @("Java-WebSocket","rxjava2-extras","fluent-logger-java","delight-nashorn-sandbox")) {
  $sha = (git -C $T\flaky-study\$p rev-parse --short HEAD)
  "$p local=$sha"
} *> $T\findings\logs\flakesync\local-shas.log
type $T\findings\logs\flakesync\local-shas.log
```

Paper SHAs to compare against: M3 `fa3909c`, M16 `7663d3b`, M25 `2e5fdf2`,
M26 `da35edc`.

> **Do not check out the paper's SHA in the existing clone.** Those clones are
> the ones the TSVD4J and NonDex findings were produced from; moving them
> invalidates the ability to re-check earlier results. Clone a **separate copy**
> per FlakeSync target, named `<project>-flakesync`, and leave the originals
> alone.

**Verify:** the four overlaps are recorded, each with both SHAs, and any
mismatch is noted.

---

### Step 12 — Measure the funnel again: how much of the subject set still builds?

This is the module's real output, and it repeats a measurement the paper made
in 2023 and nobody has repeated since.

**Sample 10 of the 37 modules at random**, clone each at its Table 1 SHA, and
try `mvn -q clean test-compile`.

```powershell
$t1 = Import-Csv $T\findings\reports\flakesync\table1-subjects.csv
$t1 | Get-Random -Count 10 | Select-Object ID,Project,Module,SHA
```

**Log-file version:**

```powershell
$t1 = Import-Csv $T\findings\reports\flakesync\table1-subjects.csv
$t1 | Get-Random -Count 10 | Select-Object ID,Project,Module,SHA *> $T\findings\logs\flakesync\staleness-sample.log
type $T\findings\logs\flakesync\staleness-sample.log
```

> **Record the sample before you run any of it.** If you pick the sample after
> seeing which ones build, the number means nothing.

Then, for each sampled module:

```powershell
cd $T\flaky-study
git clone https://github.com/<Project> fs-check-<ID>
cd fs-check-<ID>
git checkout <SHA>
mvn -q clean test-compile
echo $LASTEXITCODE
```

**Log-file version:**

```powershell
cd $T\flaky-study\fs-check-<ID>
git checkout <SHA> *> $T\findings\logs\flakesync\staleness-<ID>.log
mvn -q clean test-compile *>> $T\findings\logs\flakesync\staleness-<ID>.log
"EXIT CODE: $LASTEXITCODE" *>> $T\findings\logs\flakesync\staleness-<ID>.log
type $T\findings\logs\flakesync\staleness-<ID>.log
```

For a multi-module project, build only the module named in Table 1:

```powershell
mvn -q -pl <Module> -am clean test-compile
```

**Log-file version:**

```powershell
mvn -q -pl <Module> -am clean test-compile *> $T\findings\logs\flakesync\staleness-<ID>.log
"EXIT CODE: $LASTEXITCODE" *>> $T\findings\logs\flakesync\staleness-<ID>.log
type $T\findings\logs\flakesync\staleness-<ID>.log
```

| Outcome | Record as |
| --- | --- |
| Compiles clean | Subject still usable |
| Compiles only after switching JDK | Usable, but note which JDK — the paper does not state one per module |
| Fails on a missing or yanked dependency | `[STALENESS]` — the same failure mode the paper's own 300→221 drop describes |
| Repository gone, renamed, or archived | `[STALENESS]`, and note it separately: the paper's funnel could not have hit this in 2023 |

> **Clean up as you go.** Ten Maven projects, some of them 100+ kLOC
> (`activiti` is 111.80, `alibaba/wasp` 153.50), will eat the disk you checked
> in Step 1. `Remove-Item fs-check-<ID> -Recurse -Force` after each one, and
> re-check free space every third clone.

**The output line to write:** *"X of 10 sampled FlakeSync evaluation modules no
longer compile at their recorded commit, N months after publication."* Small
sample, honestly stated, and it is a number the literature does not have.

**Verify:** ten outcomes recorded under `[STALENESS]`, each with its log file,
and the summary line written.

---

### Step 13 — Pick the targets

Choose three, in this order. The reasoning is written out so you can defend the
choice later.

| Order | Target | Why this one |
| --- | --- | --- |
| **T1** | **M22** `elasticjob/elastic-job-lite`, module `elasticjob-infra-common`, SHA `9afe466` | The cheapest subject in the entire table: 2.12 kLOC, 1 flaky test, 4.91 s test runtime, and only **6 concurrent methods** — an order of magnitude fewer than the 1434 mean. CritSearch's cost scales with concurrent methods, so this is the fastest possible first run. Paper expects: CSS found, **1 test repaired**, overhead 0.95× |
| **T2** | **M26** `javadelight/delight-nashorn-sandbox`, SHA `da35edc` | Already cloned (at a different SHA — clone fresh as `delight-nashorn-sandbox-flakesync`), 2.49 kLOC, 1 test, 17 concurrent methods. Paper expects: CSS found, **1 test repaired**, overhead 0.91×. Also the project the NonDex module already ran on, so a NonDex-vs-FlakeSync comparison comes free |
| **T3** | **M37** `wro4j/wro4j`, module `wro4j-core`, SHA `7e3801e` | **A negative control.** 1 test, 9 concurrent methods. The paper expects CSS found but **0 repaired**, because this is the exact test it prints in Figure 5 as its example of an absolute-runtime test it cannot fix. If FlakeSync repairs it, something is wrong with your setup *or* with the paper. If it declines, you have confirmed the tool correctly refuses out-of-scope work — which is worth as much as a success |

**Stretch targets, only if T1–T3 go smoothly:**

| Target | Why |
| --- | --- |
| **M16** `rxjava2-extras` @ `7663d3b` | 3 flaky tests, paper expects 2 repaired, overhead 1.12×. Already a NonDex and iDFlakies subject — three tools on one project |
| **M3** `Java-WebSocket` @ `fa3909c` | **The cross-check prize.** 52 flaky tests, all 52 get a critical point, only 7 are async flaky and all 7 get repaired. This is also the project with 22 TSVD4J conflicting pairs already on disk. Expensive — 52 tests × ~2 h mean is not a weekend — so run a **subset** and say so |

> **Budget honestly.** At the paper's mean of 126.62 min per test, T1+T2+T3 is
> roughly **6 hours of unattended compute** if nothing goes wrong, and each test
> has a 12-hour cap if it does. Start T1 before you need the answer.

**Verify:** three targets chosen, each written into the findings file with its
paper-expected outcome recorded **before** you run it.

---

# Module 3 — Reproduce the flaky failure

**Sub-branch:** `flakesync/m3-baseline`

**Definition of done:** for each target, you know whether the flaky test
actually fails today, and you have the baseline runtime that Module 5's
overhead ratio divides by.

FlakeSync cannot repair what it cannot make fail. The paper states this
plainly in Section 5.6: *"FlakeSync heavily relies on being able to reproduce a
flaky-test failure to proceed."* Six of its own 13 failures were exactly this.
So this module is a gate, not a warm-up.

---

### Step 14 — Decide where FlakeSync runs

The paper's environment is a **Ubuntu 20.04 Docker container with 4 CPU and
4 GB RAM**. You have three options and they are not equivalent.

| Option | Matches the paper? | Cost | Use when |
| --- | --- | --- | --- |
| **Docker on Windows**, image from the artifact | Closest — same OS, and you can cap CPU/RAM exactly | Disk for the image | **Default choice.** Use this |
| **WSL2 Ubuntu directly** | Different Ubuntu release, no resource cap | Cheapest, reuses the JDK 8 already configured | Only if the artifact ships no image and no Dockerfile |
| **Windows natively** | Not at all | — | Module 6 only, as a deliberate break |

Confirm Docker is alive and that you can impose the paper's limits:

```powershell
docker version
docker run --rm --cpus=4 --memory=4g ubuntu:20.04 bash -c "nproc; free -m | head -2"
```

**Log-file version:**

```powershell
docker version *> $T\findings\logs\flakesync\docker-check.log
docker run --rm --cpus=4 --memory=4g ubuntu:20.04 bash -c "nproc; free -m | head -2" *>> $T\findings\logs\flakesync\docker-check.log
type $T\findings\logs\flakesync\docker-check.log
```

> **`nproc` inside a `--cpus=4` container still reports the host's core count.**
> `--cpus` is a CFS quota — it throttles total CPU time, it does not hide cores.
> The JVM will see all of them and may size its thread pools accordingly. This
> matters: FlakeSync's whole technique is about thread interleaving, and a JVM
> that thinks it has 16 cores behaves differently from one that thinks it has 4.
> If you want a true 4-core view, use `--cpuset-cpus=0-3` **as well**:
>
> ```powershell
> docker run --rm --cpuset-cpus=0-3 --memory=4g ubuntu:20.04 bash -c "nproc"
> ```
>
> **Which one the paper used is not stated.** Record which one you used. If the
> two give different repair outcomes in Module 4, that is a strong
> `[CONFIG-DEPENDENT]` finding and a strong `[UNEXPECTED]` one.

**Verify:** a container runs, and you have written down whether you are using
`--cpus`, `--cpuset-cpus`, or both.

---

### Step 15 — Load or build the image

**If Step 5 showed a Docker image export:**

```powershell
docker load -i $T\flaky-study\FlakeSync\<image-file>.tar
docker images
```

**Log-file version:**

```powershell
docker load -i $T\flaky-study\FlakeSync\<image-file>.tar *> $T\findings\logs\flakesync\docker-load.log
docker images *>> $T\findings\logs\flakesync\docker-load.log
docker system df *>> $T\findings\logs\flakesync\docker-load.log
type $T\findings\logs\flakesync\docker-load.log
```

**If it shipped a Dockerfile instead:**

```powershell
cd $T\flaky-study\FlakeSync\<dir-with-Dockerfile>
docker build -t flakesync:local .
```

**Log-file version:**

```powershell
cd $T\flaky-study\FlakeSync\<dir-with-Dockerfile>
Measure-Command { docker build -t flakesync:local . } *> $T\findings\logs\flakesync\docker-build.log
docker images *>> $T\findings\logs\flakesync\docker-build.log
type $T\findings\logs\flakesync\docker-build.log
```

> **A 2023-era Dockerfile that starts `FROM ubuntu:20.04` and runs `apt install`
> is a staleness hazard.** Ubuntu 20.04 reached end of standard support in
> April 2025; package versions have moved and some repositories redirect to
> archive hosts. If `apt` fails inside the build, that is a `[STALENESS]`
> finding about the artifact, not a mistake on your part. Record the exact
> `apt` error before working around it.

**Verify:** `docker images` lists a FlakeSync image, and you have recorded its
size and how much free disk remains.

---

### Step 16 — Stage the target project

Clone fresh, at the Table 1 SHA, under a `-flakesync` suffix so the existing
clones stay untouched.

```powershell
cd $T\flaky-study
git clone https://github.com/elasticjob/elastic-job-lite elastic-job-lite-flakesync
cd elastic-job-lite-flakesync
git checkout 9afe466
git log -1 --oneline
```

**Log-file version:**

```powershell
cd $T\flaky-study
git clone https://github.com/elasticjob/elastic-job-lite elastic-job-lite-flakesync *> $T\findings\logs\flakesync\clone-T1.log
cd elastic-job-lite-flakesync
git checkout 9afe466 *>> $T\findings\logs\flakesync\clone-T1.log
git log -1 --oneline *>> $T\findings\logs\flakesync\clone-T1.log
git status *>> $T\findings\logs\flakesync\clone-T1.log
type $T\findings\logs\flakesync\clone-T1.log
```

| Outcome | Action |
| --- | --- |
| Clone and checkout succeed | Continue |
| `fatal: repository not found` | The project moved or was archived. Search GitHub for a rename or a fork at that SHA. Record as `[STALENESS]` with the original URL |
| SHA not found | The history was rewritten or the clone is shallow. Retry with a full clone (no `--depth`) |

> **`git status` must be clean.** An earlier module's finding was that a dirty
> clone silently changes results. Confirm clean before every run, and record
> that you did.

**Verify:** `git log -1` shows the Table 1 SHA and `git status` is clean.

---

### Step 17 — Identify the actual flaky test name

Table 1 gives a count, not names. The names live in IDoFT, which is already
cloned from the earlier work.

```powershell
cd $T\flaky-study\idoft
Select-String -Path pr-data.csv -Pattern "elastic-job-lite" | Select-String -Pattern "NOD"
```

**Log-file version:**

```powershell
cd $T\flaky-study\idoft
Select-String -Path pr-data.csv -Pattern "elastic-job-lite" *> $T\findings\logs\flakesync\idoft-T1.log
type $T\findings\logs\flakesync\idoft-T1.log
```

> **If the SHA in IDoFT does not match Table 1's SHA**, note it. FlakeSync says
> the commits are "taken from IDoFT", so a mismatch means either IDoFT moved
> after the paper, or the paper used a different row. Either way it is a
> `[DISAGREEMENT]` worth one line, and it costs nothing to record.

Cross-check against the CSV-parsing caveat already logged in
`idoft_findings.md` in the original study — the `Notes` column can
contain commas, so naive `-split ','` shifts the columns. Read the whole matched
line, do not trust field index 3.

**Verify:** you have the fully-qualified test name (`package.Class#method` or
`package.Class.method`), copied from the CSV, not reconstructed.

---

### Step 18 — Baseline: does the test still fail, and how often?

Run the single test in isolation, repeatedly, and count. FlakeSync's premise is
that this test is *nondeterministic* — so one run tells you nothing.

Inside the container, mounting the project:

```powershell
docker run --rm -it --cpus=4 --cpuset-cpus=0-3 --memory=4g -v "${T}\flaky-study\elastic-job-lite-flakesync:/work" -w /work flakesync:local bash
```

Then inside the container:

```bash
mvn -q -pl elasticjob-infra-common -am clean test-compile
for i in $(seq 1 20); do
  mvn -pl elasticjob-infra-common surefire:test -Dtest='<FullyQualifiedTest>' > /dev/null 2>&1
  echo "run $i exit=$?"
done
```

**Log-file version (run inside the container; the mount writes straight to
Windows):**

```bash
mkdir -p /work/../../findings/logs/flakesync 2>/dev/null
{ mvn -q -pl elasticjob-infra-common -am clean test-compile ; echo "COMPILE EXIT: $?" ; } > /tmp/t1-baseline.log 2>&1
for i in $(seq 1 20); do
  mvn -pl elasticjob-infra-common surefire:test -Dtest='<FullyQualifiedTest>' > /tmp/run-$i.log 2>&1
  echo "run $i exit=$?" >> /tmp/t1-baseline.log
done
grep -c "exit=0" /tmp/t1-baseline.log >> /tmp/t1-baseline.log
cat /tmp/t1-baseline.log
```

Then copy it out to the Windows findings folder. Mount a second volume for
that, or from PowerShell:

```powershell
docker cp <container-id>:/tmp/t1-baseline.log $T\findings\logs\flakesync\t1-baseline.log
type $T\findings\logs\flakesync\t1-baseline.log
```

> **`{ time cmd ; } > file 2>&1`, not `time cmd > file 2>&1`.** The second form
> sends only `cmd`'s output to the file; `time`'s own real/user/sys summary
> prints to the terminal and is lost. This already cost a re-run in the
> iDFlakies module.

| Outcome over 20 runs | Meaning | Action |
| --- | --- | --- |
| Fails sometimes, passes sometimes | The flaky behaviour still reproduces | **Ideal.** Record the failure rate — it is the denominator for everything |
| Passes all 20 times | Fixed upstream, environment-dependent, or needs delay injection to surface | Not a blocker: FlakeSync's CritSearch *injects delays* precisely to force the failure. Record as `[STALENESS]` candidate and continue to Module 4 — but expect CritSearch to be the only thing that can make it fail |
| Fails all 20 times | Not flaky — deterministically broken here | Something is wrong with the build or the JDK. Investigate before continuing; a deterministic failure is not what FlakeSync targets |
| Will not compile | Subject is stale | Record as `[STALENESS]`, move to the next target |

**Also record the passing-run wall-clock.** Module 5 computes overhead as
`repaired runtime / original runtime`, and the paper's median is 1.00×. Without
this number that comparison is impossible.

Table 1 says T1's test runtime is **4.91 s**. Compare yours.

> **If your baseline runtime differs a lot from Table 1's**, that alone is worth
> a line — the overhead ratios in Table 2 are all relative to the paper's
> machine, and a ratio measured against a very different baseline is not
> directly comparable. Say so explicitly in Module 5 rather than quietly
> comparing incomparable numbers.

**Verify:** for each target you have (a) a failure rate out of 20, (b) a
baseline wall-clock, (c) both written into the findings file, and (d) the log
copied into `findings\logs\flakesync\`.

---

### Step 19 — Repeat Steps 16–18 for T2 and T3

Same shape, different coordinates:

| Target | Clone URL | SHA | Module flag |
| --- | --- | --- | --- |
| T2 | `https://github.com/javadelight/delight-nashorn-sandbox` | `da35edc` | none (single module) |
| T3 | `https://github.com/wro4j/wro4j` | `7e3801e` | `-pl wro4j-core -am` |

> **T2 carries the Nashorn hazard already documented in
> [new_explore.md](new_explore.md) Step 8:** Nashorn was removed from the JDK in
> Java 15. At SHA `da35edc` (2023-era) the project may or may not have adopted
> the standalone `org.openjdk.nashorn:nashorn-core` artifact. Inside the
> container you control the JDK, so install whichever the project needs — but
> **record which JDK made it build**, because the paper does not state one and
> that is itself a reproducibility gap.

> **T3's expected outcome is "not repaired".** Write that expectation down
> before running. The whole value of T3 is that you predicted the negative and
> the tool delivered it — or did not.

**Verify:** three targets, three baselines, three failure rates, all logged.

---

# Module 4 — CritSearch

**Sub-branch:** `flakesync/m4-critsearch`

**Definition of done:** FlakeSync has run its critical-point search to
completion (or to a cap) on at least T1, and you have the critical point it
found together with the wall-clock it took.

CritSearch injects delays at candidate locations, escalating from
`INITIAL_DELAY` 100 ms up to `MAX_DELAY` 51200 ms, to force the flaky failure
reliably; then it minimises the set of delay locations and searches for the
root method. The paper reports it as the dominant cost: mean **104.39 min**,
median **30.73 min** per test.

---

### Step 20 — Read the driver script before running it

```powershell
Get-ChildItem $T\flaky-study\FlakeSync -Recurse -Include *.sh,*.py -Depth 4 | Select-Object FullName,Length
```

**Log-file version:**

```powershell
Get-ChildItem $T\flaky-study\FlakeSync -Recurse -Include *.sh,*.py -Depth 4 | Select-Object FullName,Length *> $T\findings\logs\flakesync\driver-scripts.log
type $T\findings\logs\flakesync\driver-scripts.log
```

Find the one that takes a project and a test name and answer, in the findings
file:

1. What arguments does it take, in what order?
2. Does it run CritSearch and BarrierSearch together, or separately?
3. Where does it write its output?
4. Does it enforce the 12-hour cap itself, or is that something the paper's
   authors did externally?

> **Question 4 decides how you run Module 4.** If the cap is external, a test
> that will not converge runs forever and you will not know it. Impose your own
> cap either way — `timeout 12h <command>` inside the container, and record that
> you did.

> **`M2_HOME` points at the `bin` subfolder on the Windows host**, and the Maven
> path contains a space. Neither applies inside the container — but if any part
> of the artifact's tooling is invoked from PowerShell rather than from inside
> the container, both bite. Prefer running everything inside the container.

**Verify:** all four questions answered, with the script's path recorded.

---

### Step 21 — Run CritSearch on T1

```powershell
docker run --rm -d --name fs-t1 --cpus=4 --cpuset-cpus=0-3 --memory=4g -v "${T}\flaky-study\elastic-job-lite-flakesync:/work" -v "${T}\findings\logs\flakesync:/logs" -w /work flakesync:local bash -c "<the driver command from Step 20>"
```

**Log-file version** — run detached and write the log straight into the mounted
findings folder, so you can read progress from Windows without touching the
container:

```powershell
docker run --rm -d --name fs-t1 --cpus=4 --cpuset-cpus=0-3 --memory=4g `
  -v "${T}\flaky-study\elastic-job-lite-flakesync:/work" `
  -v "${T}\findings\logs\flakesync:/logs" `
  -w /work flakesync:local `
  bash -c "{ time timeout 12h <driver command> ; } > /logs/t1-critsearch.log 2>&1"
```

Watch it from a **second** window:

```powershell
Get-Content $T\findings\logs\flakesync\t1-critsearch.log -Tail 30 -Wait
docker stats fs-t1 --no-stream
```

> **`-d` plus a mounted log directory is the whole point here.** The
> second-terminal rule exists because `Ctrl+C` in a foreground redirected run
> kills it. Detaching removes the hazard entirely: there is no foreground
> window to press `Ctrl+C` in.

> **A `docker run --rm -d` container disappears when it exits, taking `/tmp`
> with it.** Anything you want to keep must be written under `/logs` or `/work`,
> both of which are mounted to Windows. Do not write results to `/tmp` and plan
> to `docker cp` them later — if the run ends while you are asleep, they are
> gone.

**Checkpoints while it runs**, recorded every hour or so:

| Check | Command |
| --- | --- |
| Still alive? | `docker ps --filter name=fs-t1` |
| Memory pressure? | `docker stats fs-t1 --no-stream` |
| Disk still there? | `Get-PSDrive C \| Select-Object Free` |
| Making progress? | `Get-Content $T\findings\logs\flakesync\t1-critsearch.log -Tail 20` |

> **The paper lost 2 of 176 tests to out-of-memory inside a 4 GB container.**
> If `docker stats` shows memory pegged at the 4 GB limit and the log stops
> advancing, you are reproducing that failure mode — which is a result, not a
> mistake. Record it as `[RESOURCE-GAP]`, then Module 6 Step 27 retries with
> more memory to see whether the outcome changes.

**Verify:** the run reached a terminal state — critical point found, explicitly
not found, or timed out — and the log is in
`findings\logs\flakesync\t1-critsearch.log`.

---

### Step 22 — Record the critical point, and time it honestly

Copy FlakeSync's own output artifacts into the reports folder:

```powershell
mkdir $T\findings\reports\flakesync\T1 -Force
Copy-Item $T\flaky-study\elastic-job-lite-flakesync\<output-dir>\* $T\findings\reports\flakesync\T1\ -Recurse
Get-ChildItem $T\findings\reports\flakesync\T1 -Recurse | Select-Object FullName,Length
```

**Log-file version:**

```powershell
mkdir $T\findings\reports\flakesync\T1 -Force
Copy-Item $T\flaky-study\elastic-job-lite-flakesync\<output-dir>\* $T\findings\reports\flakesync\T1\ -Recurse
Get-ChildItem $T\findings\reports\flakesync\T1 -Recurse | Select-Object FullName,Length *> $T\findings\logs\flakesync\t1-output-tree.log
type $T\findings\logs\flakesync\t1-output-tree.log
```

Then fill in this comparison in the findings file:

| | Paper (M22) | This run |
| --- | --- | --- |
| Critical point found | yes (CSS = 1) | |
| CritSearch wall-clock | not broken out per module; overall mean 104.39 min, median 30.73 min | |
| Max delay reached before failure reproduced | not reported for M22 | |
| Peak memory | not reported | |

> **The "max delay reached" row is worth chasing in the log.** The paper
> attributes M30's outsized runtime to needing ~8000 ms of delay per location.
> If your run needed a very different delay than the paper's machine did, that
> is direct evidence that CritSearch's cost — and therefore its 12-hour
> timeouts, and therefore its failure count — is a **function of machine speed,
> not of the bug**. That is the `[CONFIG-DEPENDENT]` thesis of this whole
> research line, tested on a repair tool for the first time.

**Verify:** the table is filled, the output artifacts are under
`findings\reports\flakesync\T1\`, and a run block is written into the findings
file.

---

### Step 23 — Run T2 and T3

Same command shape, different mounts and test names. Run them **one at a
time** — three concurrent 4-CPU containers on a machine with 16 GB RAM will
distort every timing number you collect, and timing is half the point.

> **T3 is expected to fail to repair.** Do not treat a non-repair as a broken
> run. Check specifically whether FlakeSync (a) found a critical point but no
> barrier point, which is the paper's outcome, or (b) failed earlier than that,
> which would be different from the paper and therefore more interesting.

**Verify:** three CritSearch runs complete, each with a log and an outcome.

---

# Module 5 — BarrierSearch, the repair, and overhead

**Sub-branch:** `flakesync/m5-barrier-overhead`

**Definition of done:** for every target where a critical point was found, you
know whether a barrier point was found, and for every repaired test you have a
measured overhead ratio to set against Table 2.

BarrierSearch is cheaper than CritSearch — mean **22.23 min**, median **7.00
min** — with a **3-minute timeout per run**. The paper notes that when it
*fails*, it costs more, because it re-runs across all candidate barrier points a
second time with a different threshold.

---

### Step 24 — Run BarrierSearch

If the Step 20 driver runs both phases together, this already happened and you
only need to separate the two timings out of the log:

```powershell
Select-String -Path $T\findings\logs\flakesync\t1-critsearch.log -Pattern "CritSearch|BarrierSearch|critical point|barrier point" -Context 0,2
```

**Log-file version:**

```powershell
Select-String -Path $T\findings\logs\flakesync\t1-critsearch.log -Pattern "CritSearch|BarrierSearch|critical point|barrier point" -Context 0,2 *> $T\findings\logs\flakesync\t1-phases.log
type $T\findings\logs\flakesync\t1-phases.log
```

If the phases are separate goals, run BarrierSearch the same way as Step 21,
writing to `t1-barriersearch.log`.

| Outcome | Meaning |
| --- | --- |
| Barrier point found, in project code | Full success — a developer-applicable patch. Paper's M22 outcome |
| Barrier point found, in third-party library code | Repairable only via FlakeSync's runtime framework, not as a patch. The paper flags this: only **61 of 67** repairs were directly applicable |
| No barrier point, after two threshold passes | The paper's own most common non-repair path. Record the wall-clock — this is the expensive failure mode |

**Verify:** a yes/no on the barrier point for each target, plus where it lives
(project code or library code).

---

### Step 25 — Validate the repair: 100 reruns

The paper reruns each repaired test **100 times** to confirm it always passes.
Do the same. This is the number that decides whether "repaired" means anything.

Inside the container:

```bash
PASS=0; FAIL=0
for i in $(seq 1 100); do
  mvn -pl <module> surefire:test -Dtest='<FullyQualifiedTest>' > /dev/null 2>&1 \
    && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
done
echo "PASS=$PASS FAIL=$FAIL"
```

**Log-file version:**

```bash
{
  PASS=0; FAIL=0
  for i in $(seq 1 100); do
    /usr/bin/time -f "run $i %e s" mvn -pl <module> surefire:test -Dtest='<FullyQualifiedTest>' > /tmp/r-$i.log 2>&1 \
      && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
  done
  echo "PASS=$PASS FAIL=$FAIL"
} > /logs/t1-validate-100.log 2>&1
tail -5 /logs/t1-validate-100.log
```

> **100 Maven invocations is not 100 test runs' worth of time — it is 100 JVM
> startups plus 100 Maven startups.** At even 10 s of overhead each that is 17
> minutes of pure scaffolding. If the artifact provides a rerun harness that
> stays inside one JVM, use that instead and say which you used, because the
> two measure different things.

| Outcome | Record as |
| --- | --- |
| 100/100 pass | Repair confirmed, matching the paper's criterion |
| 99/100 or fewer | **`[FALSE-POSITIVE]`** — FlakeSync reported a repair that does not hold at the paper's own validation threshold. This is a headline finding if it happens |
| Fails immediately | The patch did not apply, or the wrong test ran. Check that surefire actually executed something — the "BUILD SUCCESS with zero tests" trap from the iDFlakies work applies here too |

> **Check `Tests run:` on every one of these, not just the exit code.** The
> single most costly bug in the earlier work was a build reporting SUCCESS while
> running zero tests, because an `argLine` collision silently discarded the
> agent. FlakeSync attaches an ASM-based agent — the same collision is possible.
> Grep for it:
>
> ```bash
> grep -h "Tests run:" /tmp/r-*.log | sort | uniq -c
> ```

**Verify:** a pass count out of 100, and confirmation that each run actually
executed the test.

---

### Step 26 — Measure overhead against Table 2

Overhead = repaired test runtime ÷ original test runtime, both measured on
*this* machine.

```bash
# original, 20 runs, from the Module 3 baseline
# repaired, 20 runs, same command, same container, same limits
{ for i in $(seq 1 20); do /usr/bin/time -f "%e" mvn -q -pl <module> surefire:test -Dtest='<Test>' 2>&1 >/dev/null ; done ; } > /logs/t1-overhead-repaired.log 2>&1
cat /logs/t1-overhead-repaired.log
```

Then compare:

| Target | Paper's overhead (Table 2) | Yours |
| --- | --- | --- |
| T1 = M22 | 0.95× | |
| T2 = M26 | 0.91× | |
| T3 = M37 | n/a — not repaired | |
| M16 (stretch) | 1.12× | |
| M3 (stretch) | 1.11× | |

> **The paper's own reading of sub-1.0× overheads is "likely noise."** Two of
> your three targets have paper values below 1.0. If your measurement is also
> below 1.0, you have independently reproduced the noise, which supports the
> paper. If yours is well above 1.0 on the same test, the noise claim is
> weaker — and since the median overhead of 1.00× is one of the paper's five
> headline results, that is worth a careful paragraph rather than a footnote.

**Verify:** an overhead number per repaired target, each with the sample size
it came from, written beside the paper's figure.

---

# Module 6 — Limits and sensitivity

**Sub-branch:** `flakesync/m6-limits`

**Definition of done:** you can state at least two things about FlakeSync that
the paper does not, backed by a log.

This is where this replication stops confirming and starts contributing. Three
probes, in order of expected value.

---

### Step 27 — Does the resource cap change the answer?

The paper's 4 CPU / 4 GB is a stated configuration, not a justified one. Two of
its 176 tests died at the memory limit; it speculates that *"if given more
resources, it is possible FlakeSync would identify the critical point."* Nobody
tested that.

Re-run **the same target** under three configurations:

| Run | Flags |
| --- | --- |
| A (paper) | `--cpuset-cpus=0-3 --memory=4g` |
| B (more memory) | `--cpuset-cpus=0-3 --memory=8g` |
| C (more CPU) | `--cpuset-cpus=0-7 --memory=8g` |

```powershell
docker run --rm -d --name fs-t1-B --cpuset-cpus=0-3 --memory=8g -v "${T}\flaky-study\elastic-job-lite-flakesync:/work" -v "${T}\findings\logs\flakesync:/logs" -w /work flakesync:local bash -c "{ time timeout 12h <driver command> ; } > /logs/t1-configB.log 2>&1"
```

**Log-file version** — already writing to `/logs`; read it from a second window:

```powershell
Get-Content $T\findings\logs\flakesync\t1-configB.log -Tail 30 -Wait
```

> **Use a clean clone per configuration.** FlakeSync instruments and rewrites
> code; a second run on a tree the first run touched is not an independent
> measurement. `git clone` a fresh copy, or `git checkout -- .` and
> `git clean -fdx` between runs, and record which you did.

Compare:

| | A (4 CPU / 4 GB) | B (4 CPU / 8 GB) | C (8 CPU / 8 GB) |
| --- | --- | --- | --- |
| Critical point found? | | | |
| Same critical point? | | | |
| Barrier point found? | | | |
| Wall-clock | | | |
| Max delay needed | | | |

> **The interesting cell is "same critical point?"** If A and C find *different*
> critical points for the same test, then FlakeSync's output — the thing a
> developer would paste into their codebase as a patch — depends on the machine
> it ran on. That is a `[CONFIG-DEPENDENT]` finding of the strongest kind, and
> it is the direct repair-tool analogue of the iDFlakies configuration finding
> already recorded.

**Verify:** three runs, one table, filled in.

---

### Step 28 — Is FlakeSync deterministic about its own output?

Run the **identical** configuration twice on a clean clone each time.

```powershell
docker run --rm -d --name fs-t1-rep1 --cpuset-cpus=0-3 --memory=4g -v "${T}\flaky-study\elastic-job-lite-fs-rep1:/work" -v "${T}\findings\logs\flakesync:/logs" -w /work flakesync:local bash -c "{ time timeout 12h <driver command> ; } > /logs/t1-rep1.log 2>&1"
```

**Log-file version:** as above; then diff the two outputs.

```powershell
Compare-Object (Get-Content $T\findings\reports\flakesync\T1-rep1\<result-file>) (Get-Content $T\findings\reports\flakesync\T1-rep2\<result-file>)
```

**Log-file version:**

```powershell
Compare-Object (Get-Content $T\findings\reports\flakesync\T1-rep1\<result-file>) (Get-Content $T\findings\reports\flakesync\T1-rep2\<result-file>) *> $T\findings\logs\flakesync\t1-determinism.log
type $T\findings\logs\flakesync\t1-determinism.log
```

> **A technique whose search is driven by timing cannot be assumed
> deterministic, and the paper never claims it is — but it also never reports
> variance.** Every number in Tables 1 and 2 is from a single run per test. If
> two identical runs disagree, then the 83.75% headline has an unreported error
> bar, and saying so with evidence is a genuine contribution. If they agree,
> that is a `[NULL]` result worth recording too: it strengthens the paper.

**Verify:** two runs, one diff, one conclusion.

---

### Step 29 — What happens on Windows?

The paper says nothing about Windows. The iDFlakies work found a genuine
Windows-only file-locking bug that upstream only gestured at. Repeat the
exercise here: run FlakeSync natively on Windows and find out precisely how it
breaks, if it does.

```powershell
cd $T\flaky-study\elastic-job-lite-flakesync
<the driver command, translated to PowerShell>
```

**Log-file version:**

```powershell
cd $T\flaky-study\elastic-job-lite-flakesync
<driver command> *> $T\findings\logs\flakesync\windows-attempt.log
"EXIT CODE: $LASTEXITCODE" *>> $T\findings\logs\flakesync\windows-attempt.log
type $T\findings\logs\flakesync\windows-attempt.log
```

Expect one of these, and record which, with the exact error text:

| Failure | Why it would happen |
| --- | --- |
| Shell script will not run | The artifact ships `.sh` drivers; Windows has no `/bin/bash` on `PATH` |
| `$M2_HOME/bin/mvn` not found | `M2_HOME` points at `bin`, so the script looks for `bin\bin\mvn` |
| Path truncated at a space | The Maven install path contains a space and the script does not quote it |
| Cannot delete a file in use | Windows locks open files; Linux does not. **This is exactly the iDFlakies Windows bug.** If it recurs here, it is not a one-tool quirk — it is a shared assumption across this research group's tooling, which is a much stronger finding |
| A `-D` flag parsed as a lifecycle phase | PowerShell splits `-D` flags containing dots. Quote the whole flag |

> **The value here is precision, not the fact of failure.** "It does not work on
> Windows" is worth nothing. "It fails at line N of `run.sh` because Windows
> holds a lock on the ASM-instrumented class file that Linux would let it
> delete" is worth a paragraph in a paper.

**Verify:** the exact failure, the exact line, and the exact message, recorded
under `[PLATFORM]`.

---

# Module 7 — Cross-check and write-up

**Sub-branch:** `flakesync/m7-crosscheck`

**Definition of done:** you can state, with evidence, at least one place where
FlakeSync disagrees with another artifact already tested in this repository.

Everything before this collected inputs. This is where the research value is —
and the reason the earlier plan's "disagreements" box was worth filling.

---

### Step 30 — FlakeSync vs TSVD4J on `Java-WebSocket`

The single richest comparison available, because both artifacts evaluate the
same project and neither paper mentions the other.

What is already on disk, from the TSVD4J work:
`findings\reports\tsvd4j\` holds the conflicting-pair output for
`Java-WebSocket`, and `tsvd4j_findings.md` in the original study
records that **6 of 6** pairs inspected on `commons-dbcp` were false positives.

What FlakeSync claims for the same project (M3): **52** flaky tests, **52**
critical points found, **7** genuine async flaky tests, **7** repaired,
overhead 1.11×.

| Test | TSVD4J flagged (conflicting pair)? | FlakeSync: critical point? | FlakeSync: repaired? | Agree? |
| --- | --- | --- | --- | --- |
| | | | | |

The questions to answer:

1. **Does any test appear in both?** TSVD4J finds thread-safety violations;
   FlakeSync repairs async flakiness. Both are concurrency techniques on the
   same suite. Overlap is not guaranteed, which is exactly what makes it
   interesting either way.
2. **Do the 45 tests FlakeSync classified as "relies on absolute runtime"
   overlap with TSVD4J's pairs?** If TSVD4J flags a test that FlakeSync says is
   merely a slow-machine timeout, one of them is wrong about that test.
3. **Does TSVD4J flag any of the 7 FlakeSync repaired?** If so, two independent
   techniques agree something is genuinely wrong there — the strongest possible
   corroboration either tool can get.

> **`Java-WebSocket` needs JDK 8** (source level 1.7) and has documented
> pre-existing flakiness: port-reuse `BindException`, `Issue847Test` port
> exhaustion, `Issue256Test` zombie threads, `Issue941Test` hanging. **Count how
> many of FlakeSync's 52 are actually these.** "N of FlakeSync's 52 M3 subjects
> are environment flakiness, not async flakiness" would be a second
> false-positive measurement on a second tool, and it is the same measurement
> already made for iDFlakies on this exact project.

---

### Step 31 — FlakeSync vs NonDex and iDFlakies

Both have already run on `delight-nashorn-sandbox` and `rxjava2-extras` — T2 and
stretch target M16.

| Project | NonDex found | iDFlakies found | FlakeSync repaired | Notes |
| --- | --- | --- | --- | --- |
| `delight-nashorn-sandbox` | null result (recorded in `nondex_findings.md` in the original study) | | | |
| `rxjava2-extras` | | | | |

The cell to look at: **NonDex returned a null result on
`delight-nashorn-sandbox`, but FlakeSync's Table 1 lists it as having a known
NOD flaky test that FlakeSync repairs.** Those are different categories — ID
versus async — so they are not strictly contradictory. But if FlakeSync can
reliably make that test fail via delay injection while NonDex cannot make it
fail via collection shuffling, you have a concrete statement about what each
technique's blind spot is, on a shared subject, with logs for both.

---

### Step 32 — The 94-of-174 question

This is the highest-value analysis in the plan and it needs no further runs.

FlakeSync inspected 174 tests that IDoFT labels **NOD** and concluded that
**94 of them (54%) rely on absolute runtime** — they fail because a machine was
slow, not because of any ordering or synchronisation issue. The paper uses this
only to compute a denominator for its 83.75%.

Read as a claim about IDoFT, it says: **more than half of a sample of that
dataset's NOD entries are mislabelled**, or at least are labelled with a
category too coarse to be actionable.

Check it against what is already on disk:

```powershell
cd $T\flaky-study\idoft
(Select-String -Path pr-data.csv -Pattern ",NOD," | Measure-Object).Count
```

**Log-file version:**

```powershell
cd $T\flaky-study\idoft
(Select-String -Path pr-data.csv -Pattern ",NOD," | Measure-Object).Count *> $T\findings\logs\flakesync\idoft-nod-count.log
Select-String -Path pr-data.csv -Pattern ",NOD," | Select-Object -First 20 *>> $T\findings\logs\flakesync\idoft-nod-count.log
type $T\findings\logs\flakesync\idoft-nod-count.log
```

Then, for the handful of NOD tests you actually ran in Modules 3–5, judge each
one yourself: is it an async flaky test, or does it assert on absolute time?
Read the test source. A sample of three or four, judged by hand with the source
quoted, is a legitimate spot-check of a 54% claim.

> **This connects three artifacts at once.** IDoFT supplies the label,
> FlakeSync disputes it, and the iDFlakies work already found that iDFlakies
> itself returns generic labels with no victim/polluter distinction for tests
> IDoFT does distinguish. The through-line is: **these tools' category labels
> are less reliable than the numbers built on top of them assume.** That is a
> research direction, not a bug report.

**Verify:** the 54% claim is either supported or questioned, with at least three
hand-inspected tests quoted.

---

### Step 33 — Write it up

Fill in `findings\flakesync_findings.md` completely — every category heading
either has entries or an explicit "nothing found here" line. Then write a
one-page summary in the same shape as
`tsvd4j_report.md` in the original study, saved as
`findings\reports\flakesync\flakesync_report.md`:

1. **What I did** — one paragraph: which targets, which configurations, how long
2. **What the paper claims vs what I measured** — one table, paper column and
   measured column side by side
3. **The disagreements** — the central section
4. **What I would do next** — two or three bullets

Then extend the existing `comparative_report.md` in the original study
with a FlakeSync row rather than starting a new comparative file.

> **Send it before everything is finished.** After Module 5 you already have
> something worth sending: a repair tool reproduced on a laptop with a
> measured overhead, next to the paper's number. After Module 7 you have a
> report.

**Verify:** the report exists, the findings file has no empty category without
an explicit note, and `comparative_report.md` has a FlakeSync row.

---
---

## Every trap in this plan, in one place

| # | Trap | Where | Symptom |
| --- | --- | --- | --- |
| 1 | ~29.8 GiB free disk, 1.5 GB tarball plus a multi-GB image | Module 1 | Builds and `docker load` fail late with no clear message |
| 2 | `*.tar.gz` is not in `.gitignore` | Step 8 | A 1.5 GB push attempt |
| 3 | `Invoke-WebRequest` buffers the whole body in RAM | Step 4 | Memory spike on a 16 GB machine; use `curl.exe` |
| 4 | Checksum not verified before unpacking | Step 4 | A truncated tarball produces confusing errors three steps later |
| 5 | Existing clones are at the wrong SHA for Table 1 | Step 11 | Silently replicating a different commit than the paper |
| 6 | Checking out the paper SHA *in* an existing clone | Step 11 | Destroys the ability to re-check earlier TSVD4J/NonDex findings |
| 7 | `--cpus=4` does not hide cores; `nproc` still reports the host | Step 14 | The JVM sizes thread pools for 16 cores in a "4-core" container |
| 8 | `apt` inside a 2023-era `ubuntu:20.04` Dockerfile | Step 15 | Package repositories moved to archive hosts; build fails |
| 9 | IDoFT's `Notes` column contains commas | Step 17 | Naive `-split ','` shifts every field after index 3 |
| 10 | `time cmd > file` redirects only `cmd` | Steps 18, 21 | Timing summary never reaches the log; use `{ time cmd ; } > file 2>&1` |
| 11 | Writing results to `/tmp` in a `--rm` container | Step 21 | Results vanish when the run ends unattended |
| 12 | `Ctrl+C` in a redirected window | Any long run | Run dies silently; the window looked idle. Detach with `-d` instead |
| 13 | 12-hour cap may be external to the artifact | Step 20 | A non-converging test runs forever unnoticed; impose `timeout 12h` yourself |
| 14 | 4 GB container OOM | Step 21 | Reproduces the paper's own 2-of-176 loss. Record before working around |
| 15 | `argLine` collision silently drops the ASM agent | Step 25 | `BUILD SUCCESS` with zero tests run. Always check `Tests run:` |
| 16 | 100 Maven invocations ≠ 100 test runs | Step 25 | 17+ minutes of pure JVM/Maven startup counted as test time |
| 17 | Reusing an instrumented tree between runs | Step 27 | The second run is not independent; clone fresh or `git clean -fdx` |
| 18 | Running three containers at once | Step 23 | Every timing number is distorted; timing is half the point |
| 19 | Nashorn removed from JDK 15+ | Step 19 (T2) | `ScriptEngine` null, or the build fails |
| 20 | `Java-WebSocket` needs JDK 8 (source 1.7) | Step 30 | `javac` rejects the source release |
| 21 | `Java-WebSocket` pre-existing flakiness | Step 30 | Port exhaustion and zombie threads inflate any flaky count |
| 22 | `M2_HOME` points at `bin`; Maven path contains a space | Step 29 | Any unquoted helper script fails with `bin\bin\mvn` or a truncated path |
| 23 | `-D` flags with dots need quoting in PowerShell | Step 29 | `Unknown lifecycle phase ".something"` |
| 24 | Absolute paths leak into committed logs | Every commit | Scrub before `git commit`, every time |
| 25 | Comparing your overhead ratio to Table 2 across different baselines | Step 26 | Two ratios measured against different denominators, presented as comparable |

---

## Housekeeping while you go

- **Add `*.tar.gz` to `.gitignore`** before the first commit.
- **`planning/` is git-ignored; `findings/` is committed.** Plans here, results
  there.
- **Scrub absolute paths from every log before committing it.**
- **Ask before every `git commit`.**
- **Keep this file current.** If the work diverges from the plan — a different
  target, a different container configuration, a step that turned out
  unnecessary — edit this file at the same time as the findings log.
- **Delete `fs-check-*` clones** as soon as each staleness check is recorded.
- **`docker system df` after every module.** Images and dangling layers
  accumulate faster than anything else in this plan.

---

## What "done" looks like

This work should support a summary page saying:

- Here is the FlakeSync artifact running end to end on a laptop, and here is how
  its repair rate and overhead compare to the published numbers on the same
  subjects.
- Here is what fraction of FlakeSync's own evaluation subjects no longer compile
  at their recorded commits.
- Here is whether FlakeSync's output changes when you change the container's CPU
  and memory — that is, whether a developer's patch depends on their machine.
- Here is whether two identical runs produce the same critical point, which the
  paper never reports.
- Here is precisely how it fails on Windows, which the paper never mentions.
- Here is where FlakeSync and TSVD4J agree and disagree about `Java-WebSocket`,
  a comparison neither paper makes.
- Here is a hand-checked verdict on FlakeSync's claim that 54% of a sample of
  IDoFT's NOD entries are not really async flaky at all.

That is entries in all four categories this research tracks — unexpected
behaviour, limitations, disagreements between tools or datasets, and
opportunities for improvement — from a single artifact.

---

## Next

When Module 7 is merged into `main`, move to
[rankf_explore.md](rankf_explore.md). Its Modules 1–6 are CPU-only; its one GPU
module sits at the end, and [flakylens_explore.md](flakylens_explore.md) is last
of all.
