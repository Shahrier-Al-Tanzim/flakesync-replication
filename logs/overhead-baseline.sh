#!/bin/bash
set -x
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
java -version
WORK=~/flakesync-overhead
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"
git clone https://github.com/javadelight/delight-nashorn-sandbox.git . > clone.log 2>&1
git checkout da35edc0a75424bad8cbf60959fae253202154c4 >> clone.log 2>&1
echo "=== baseline (plain, no agent) x5 ==="
for i in 1 2 3 4 5; do
  { time mvn -q test -Dtest="delight.nashornsandbox.TestGetFunction#test" ; } > "run-$i.log" 2>&1
  echo "run $i exit=$?"
  grep -E "^real" "run-$i.log"
done
