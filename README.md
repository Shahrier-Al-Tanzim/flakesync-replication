# FlakeSync artifact replication

This folder contains the inputs, recorded outputs, logs, and analysis from an
independent run of [**FlakeSync: Automatically Repairing Async Flaky Tests**](https://doi.org/10.1145/3597503.3639115)
(Shanto Rahman and August Shi, ICSE 2024).

The executable FlakeSync implementation is in the [authors' official Zenodo
artifact](https://zenodo.org/records/10460139). The 1.4 GB Docker archive is
not included here. The archive contains the tool source, driver scripts,
dependencies, and an environment based on Java 8. The archived MD5 recorded
for this study is `da181d43dadcda81735a6aabd4bcbf05`.

## What is included

| Path | Purpose |
| --- | --- |
| `inputs/m26.csv` | Single M26 test used for the main reproduction. |
| `inputs/m16-testcache.csv` | Single M16 test with a differing critical-point location. |
| `inputs/original-m22-m26.csv` | Historical two-test input; M22 uses a moving `master` ref and no longer builds through the shipped pipeline. |
| `run.ps1`, `run.sh` | PowerShell and Bash launchers for the official Docker artifact. |
| `results/` | Saved outputs from the original M26, M16, and resource-comparison runs. |
| `reference/` | Authors' expected outputs and input lists copied from the official artifact for comparison. |
| `logs/` | Full pipeline transcripts and selected setup logs from the original study. |
| `analysis/` | Replication report and detailed findings. |

The source projects and tool are **not** vendored. The official script clones
each subject project at the commit specified in the input CSV, so a rerun
requires internet access from Docker.

Some historical notes retain paths from the original workspace. In this
standalone folder, `findings/logs/flakesync/` maps to `logs/`, and
`findings/reports/flakesync/` maps to `results/` or `reference/` depending on
whether the file was produced by this study or by the authors.
Use the launchers below for new runs.

## Run on Windows

1. Install and start Docker Desktop with Linux containers.
2. Download `flakesync-artifact_latest.tar.gz` from the [Zenodo record](https://zenodo.org/records/10460139).
3. Verify it in PowerShell (the launcher also checks this before loading):

   ```powershell
   (Get-FileHash .\flakesync-artifact_latest.tar.gz -Algorithm MD5).Hash
   # Expected: DA181D43DADCDA81735A6AABD4BCBF05
   ```

4. From this folder, run the main M26 case:

   ```powershell
   .\run.ps1 -Case m26 -ArtifactPath .\flakesync-artifact_latest.tar.gz
   ```

   Once the Docker image is loaded, `-ArtifactPath` can be omitted. To run the
   single completed M16 case, use `-Case m16-testcache`.

The launcher uses 4 CPUs and 4 GB of memory. Each run gets its own ignored
`runs/<case>-<timestamp>/` folder with `pipeline.log` and all generated
result directories. The first run can take substantially longer because the
authors' script clones and builds a subject project. Docker and the project's
Maven dependencies need network access.

On Linux or macOS with Docker, use `bash run.sh m26 /path/to/flakesync-artifact_latest.tar.gz`.
Once the image is loaded, the second argument can be omitted. The launchers
check for the expected test in `Results-Barrier/Result.csv`; they do not claim
that an actual source patch was applied and measured.

## Original results and limits

- M26 (`delight-nashorn-sandbox`): six recorded output rows have the same
  barrier point (`NashornSandboxImpl#233`) and threshold (`1`) as the authors'
  output. Four found the same split critical region; two found a broader
  `JsEvaluator#53–68` region.
- M16 (`rxjava2-extras`, `FlowablesTest#testCache`): the barrier point and
  threshold matched the authors' output. The reported critical point was
  `Flowables$4#306` instead of the authors' `ScheduledRunnable#57`.
- M22 (`elastic-job-lite`) failed using the original artifact input because
  that row specified `master` rather than the commit from the paper. A
  separate build check at the paper's pinned commit succeeded.

These are saved observations, not a claim to have reproduced the whole paper.
The study did **not** independently measure repaired-test runtime overhead or
validate an applied source patch. The M16 second test was stopped before its
search finished. See [the report](analysis/flakesync_report.md) and
[the findings log](analysis/flakesync_findings.md) for the full detail and
qualifications.

## Attribution

FlakeSync and the reference outputs belong to their original authors.
`reference/` is copied from the official artifact so each comparison can be
checked; it is not a result of this replication. `results/`, `logs/`, and
`analysis/` document the independent study. Cite the paper and link to the
[artifact record](https://zenodo.org/records/10460139) when sharing this
repository. No license is asserted here for the authors' code or data.
