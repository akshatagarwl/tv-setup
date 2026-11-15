#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}}"
BT="$SDK/build-tools/34.0.0"
JAR="$SDK/platforms/android-34/android.jar"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export PATH="$JAVA_HOME/bin:$PATH"
for file in "$BT/aapt" "$BT/d8" "$BT/apksigner" "$JAR"; do
    [[ -f "$file" ]] || { echo "Missing tool: $file" >&2; exit 1; }
done
python3 scripts/sync-resources.py --check
mkdir -p android/out/classes android/out/dex private dist
"$BT/aapt" package -f -m -M android/AndroidManifest.xml -S android/res -A android/assets -I "$JAR" -J android/out -F android/out/resources.apk
# Bash 3 compatible: sources passed as a generated argument file.
find android/src -name '*.java' > android/out/sources.txt
for name in AdbBase64 AdbCrypto AdbProtocol; do
    printf '%s\n' "vendor/AdbLib/src/com/cgutman/adblib/$name.java" >> android/out/sources.txt
done
javac -source 8 -target 8 -encoding UTF-8 -classpath "$JAR" -d android/out/classes @android/out/sources.txt
(cd android/out/classes && jar cf ../classes.jar .)
"$BT/d8" --min-api 26 --lib "$JAR" --output android/out/dex android/out/classes.jar
cp android/out/resources.apk android/out/unsigned.apk
(cd android/out/dex && zip -q -u ../unsigned.apk classes.dex)
"$BT/zipalign" -f 4 android/out/unsigned.apk android/out/aligned.apk
if [[ ! -f private/debug.keystore ]]; then
    keytool -genkeypair -keystore private/debug.keystore -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 3650 -dname 'CN=TV Setup Local Debug'
fi
"$BT/apksigner" sign --ks private/debug.keystore --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out dist/tv-setup-debug.apk android/out/aligned.apk
"$BT/apksigner" verify --verbose dist/tv-setup-debug.apk
shasum -a 256 dist/tv-setup-debug.apk
printf '\nBuilt dist/tv-setup-debug.apk. Nothing was installed or contacted on a TV.\n'
