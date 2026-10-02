param(
    [ValidateSet('m26', 'm16-testcache')]
    [string] $Case = 'm26',
    [string] $ArtifactPath
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputPath = (Resolve-Path -LiteralPath (Join-Path $packageRoot "inputs/$Case.csv")).Path
$expectedTest = if ($Case -eq 'm26') { 'delight.nashornsandbox.TestGetFunction#test' } else { 'com.github.davidmoten.rx2.FlowablesTest#testCache' }
$imageName = 'flakesync-artifact:latest'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is required. Install or start Docker Desktop, then try again.'
}

& docker info --format '{{.ServerVersion}}' 1>$null
if ($LASTEXITCODE -ne 0) {
    throw 'The Docker daemon is unavailable. Start Docker Desktop, then try again.'
}

& docker image inspect $imageName --format '{{.Id}}' 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    if (-not $ArtifactPath) {
        throw "Image $imageName is missing. Download the official artifact and rerun with -ArtifactPath <path-to-tar.gz>."
    }
    $resolvedArtifact = (Resolve-Path -LiteralPath $ArtifactPath).Path
    $actualMd5 = (Get-FileHash -LiteralPath $resolvedArtifact -Algorithm MD5).Hash
    if ($actualMd5 -ne 'DA181D43DADCDA81735A6AABD4BCBF05') {
        throw "Artifact MD5 mismatch: $actualMd5. Check the download against the official Zenodo record."
    }
    & docker load --input $resolvedArtifact
    if ($LASTEXITCODE -ne 0) { throw 'Docker could not load the official artifact.' }
    & docker image inspect $imageName --format '{{.Id}}' 1>$null
    if ($LASTEXITCODE -ne 0) { throw "The loaded artifact did not contain $imageName." }
}

$runName = '{0}-{1}' -f $Case, (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$runDir = Join-Path $packageRoot "runs/$runName"
New-Item -ItemType Directory -Path $runDir -ErrorAction Stop | Out-Null

$containerScript = 'cd /home/java8-flakesync/scripts || exit 1; bash end_to_end_flakesync.sh /tmp/flakesync-input.csv > /export/pipeline.log 2>&1; status=$?; for item in Results-Minimizer Results-Boundary Results-Barrier Locations logs; do if [ -e "$item" ]; then cp -R "$item" /export/; fi; done; exit "$status"'

& docker run --rm --cpus=4 --memory=4g `
    --mount "type=bind,source=$inputPath,target=/tmp/flakesync-input.csv,readonly" `
    --mount "type=bind,source=$runDir,target=/export" `
    $imageName bash -lc $containerScript
$runExitCode = $LASTEXITCODE

Write-Host "Results and full pipeline log: $runDir"
if ($runExitCode -ne 0) {
    throw "FlakeSync exited with code $runExitCode. Review pipeline.log and the partial outputs in $runDir."
}
$barrierCsv = Join-Path $runDir 'Results-Barrier/Result.csv'
if (-not (Test-Path -LiteralPath $barrierCsv) -or -not (Select-String -LiteralPath $barrierCsv -SimpleMatch $expectedTest -Quiet)) {
    throw "The pipeline did not record the expected test in Results-Barrier/Result.csv. Review $runDir/pipeline.log."
}
Write-Host "Confirmed barrier-search output for $expectedTest"
