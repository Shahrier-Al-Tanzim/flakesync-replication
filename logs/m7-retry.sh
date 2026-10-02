#!/bin/bash
cd ~/flakesync-staleness/fs-check-M7
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
find . -maxdepth 2 -type d -name "dubbo-config*"
echo "---trying nested path---"
timeout 300 mvn -q -pl dubbo-config/dubbo-config-api -am clean test-compile > /tmp/m7-retry.log 2>&1
echo "EXIT: $?"
tail -15 /tmp/m7-retry.log
