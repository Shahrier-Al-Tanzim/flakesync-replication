#!/usr/bin/env bash
set -euo pipefail

case_name="${1:-m26}"
artifact_path="${2:-}"
case "$case_name" in
    m26) expected_test='delight.nashornsandbox.TestGetFunction#test' ;;
    m16-testcache) expected_test='com.github.davidmoten.rx2.FlowablesTest#testCache' ;;
    *) echo 'Usage: bash run.sh [m26|m16-testcache] [path-to-artifact.tar.gz]' >&2; exit 2 ;;
esac

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input_path="$package_root/inputs/$case_name.csv"
image_name='flakesync-artifact:latest'

command -v docker >/dev/null || { echo 'Docker is required.' >&2; exit 1; }
docker info --format '{{.ServerVersion}}' >/dev/null || {
    echo 'The Docker daemon is unavailable.' >&2; exit 1;
}

if ! docker image inspect "$image_name" --format '{{.Id}}' >/dev/null 2>&1; then
    if [[ -z "$artifact_path" ]]; then
        echo 'Download the official Zenodo artifact and pass its path as argument 2.' >&2
        exit 1
    fi
    expected_md5='da181d43dadcda81735a6aabd4bcbf05'
    if command -v md5sum >/dev/null; then
        actual_md5="$(md5sum "$artifact_path" | cut -d' ' -f1)"
    elif command -v md5 >/dev/null; then
        actual_md5="$(md5 -q "$artifact_path")"
    else
        echo 'An MD5 utility is required to verify the artifact.' >&2
        exit 1
    fi
    if [[ "$actual_md5" != "$expected_md5" ]]; then
        echo "Artifact MD5 mismatch: $actual_md5" >&2
        exit 1
    fi
    docker load --input "$artifact_path"
fi

mkdir -p "$package_root/runs"
run_dir="$(mktemp -d "$package_root/runs/$case_name-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
echo "Writing results to $run_dir"

docker run --rm --cpus=4 --memory=4g \
    --mount "type=bind,source=$input_path,target=/tmp/flakesync-input.csv,readonly" \
    --mount "type=bind,source=$run_dir,target=/export" \
    "$image_name" bash -lc '
        cd /home/java8-flakesync/scripts || exit 1
        bash end_to_end_flakesync.sh /tmp/flakesync-input.csv > /export/pipeline.log 2>&1
        status=$?
        for item in Results-Minimizer Results-Boundary Results-Barrier Locations logs; do
            if [ -e "$item" ]; then cp -R "$item" /export/; fi
        done
        exit "$status"
    '

barrier_csv="$run_dir/Results-Barrier/Result.csv"
if [[ ! -f "$barrier_csv" ]] || ! grep -Fq "$expected_test" "$barrier_csv"; then
    echo "No barrier-search result for $expected_test. Review $run_dir/pipeline.log." >&2
    exit 1
fi
echo "Confirmed barrier-search output for $expected_test"
