#!/bin/bash
set -x
WORK=~/flakesync-staleness
mkdir -p "$WORK"
cd "$WORK"

export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"

declare -a rows=(
  "M31|qos-ch/logback|logback-core|0f57531977287fd3d8c9046e9f68e281715f3b10"
  "M25|fluent/fluent-logger-java|.|2e5fdf2dbed59cc5af88442ceae6cbe72f321060"
  "M14|apache/incubator-uniffle|common|6fb2a9a63132ab9abbde2f1f9240f9caf2f5d0f0"
  "M33|undertow-io/undertow|core|ac7204a"
  "M22|elasticjob/elastic-job-lite|elasticjob-infra/elasticjob-infra-common|9afe466"
  "M12|apache/httpcore|httpcore|49247d208bde47f652812493e1d3576e136b8eb8"
  "M36|vmware/admiral|compute|e4b02936cc7d4ff2714e7231db0c4373ba5d48a2"
  "M7|apache/dubbo|dubbo-config-api|737f7a7ea67832d7f17517326fb2491d0a086dd7"
  "M21|doanduyhai/Achilles|integration-test|f52f7ec93b3da758119dbbbc1be8dad8e8783764"
  "M10|apache/dubbo|dubbo-rpc-http|737f7a7ea67832d7f17517326fb2491d0a086dd7"
)

SUMMARY="$WORK/summary.txt"
> "$SUMMARY"

for row in "${rows[@]}"; do
  IFS='|' read -r id slug module sha <<< "$row"
  dir="fs-check-${id}"
  echo "=== $id $slug $module $sha ===" | tee -a "$SUMMARY"

  if [ -d "$dir" ]; then rm -rf "$dir"; fi
  git clone "https://github.com/$slug" "$dir" > "$WORK/${id}-clone.log" 2>&1
  clone_exit=$?
  if [ $clone_exit -ne 0 ]; then
    echo "$id: CLONE FAILED (exit $clone_exit)" | tee -a "$SUMMARY"
    continue
  fi

  cd "$dir"
  git checkout "$sha" >> "$WORK/${id}-clone.log" 2>&1
  checkout_exit=$?
  if [ $checkout_exit -ne 0 ]; then
    echo "$id: CHECKOUT FAILED for SHA $sha (exit $checkout_exit)" | tee -a "$SUMMARY"
    cd "$WORK"
    continue
  fi

  if [ "$module" == "." ]; then
    timeout 900 mvn -q clean test-compile > "$WORK/${id}-build.log" 2>&1
  else
    timeout 900 mvn -q -pl "$module" -am clean test-compile > "$WORK/${id}-build.log" 2>&1
  fi
  build_exit=$?
  echo "$id: BUILD EXIT=$build_exit" | tee -a "$SUMMARY"
  cd "$WORK"
done

echo "=== ALL DONE ===" | tee -a "$SUMMARY"
cat "$SUMMARY"
