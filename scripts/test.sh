#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 scripts/sync-resources.py --check
python3 -m unittest discover -s tests -p 'test_*.py' -v
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export PATH="$JAVA_HOME/bin:$PATH"
mkdir -p android/out/tests
JSON_JAR=android/out/android-json-tests.jar
if [[ ! -f "$JSON_JAR" ]]; then
    curl -fsSL --max-time 30 https://repo.maven.apache.org/maven2/com/vaadin/external/google/android-json/0.0.20131108.vaadin1/android-json-0.0.20131108.vaadin1.jar -o "$JSON_JAR"
fi
python3 - "$JSON_JAR" <<'PY'
import hashlib, sys
from pathlib import Path
assert hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest() == 'dfb7bae2f404cfe0b72b4d23944698cb716b7665171812a0a4d0f5926c0fac79', 'Test dependency hash mismatch'
PY
javac -encoding UTF-8 -cp "$JSON_JAR" -d android/out/tests \
    vendor/AdbLib/src/com/cgutman/adblib/{AdbBase64,AdbCrypto,AdbProtocol}.java \
    android/src/com/cgutman/adblib/LegacyClient.java android/src/io/akshat/tvsetup/Catalog.java \
    tests/LegacyClientTest.java tests/CatalogTest.java
java -cp "android/out/tests:$JSON_JAR" com.cgutman.adblib.LegacyClientTest
java -cp "android/out/tests:$JSON_JAR" io.akshat.tvsetup.CatalogTest shared/catalog.json
(cd ios && swift test)
printf '\nAll automated tests passed. Tests use fake ADB streams; no TV was contacted.\n'
