#!/bin/bash
# Builds the app + UI tests and runs them on a simulator against a local OpenSSH server.
# Usage: scripts/run-uitests.sh <simulator-udid> <sshd-dir with hostkey.pub, userkey_enc> <user> <passphrase> [port]
set -e
cd "$(dirname "$0")/.."
D=$1; SP=$2; USER_NAME=$3; PASS=$4; PORT=${5:-2222}
xcodebuild build-for-testing -project PuTTY.xcodeproj -scheme PuTTY -destination "platform=iOS Simulator,id=$D" \
  -derivedDataPath build/dd -skipPackagePluginValidation -skipMacroValidation > build/log.txt 2>&1 || { grep -E "error:" build/log.txt | sort -u; exit 1; }
# Xcode 26 runners built outside Xcode's test flow miss the Swift Testing support libraries.
PLAT=$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer
R=build/dd/Build/Products/Debug-iphonesimulator/PuTTYUITests-Runner.app
for f in $PLAT/Library/Frameworks/*.framework $PLAT/Library/PrivateFrameworks/*.framework $PLAT/usr/lib/*.dylib; do
  n=$(basename "$f"); case $n in *Testing*|XC*|libXCTest*) [ -e "$R/Frameworks/$n" ] || cp -R "$f" "$R/Frameworks/";; esac
done
for f in $R/Frameworks/*; do codesign -f -s - "$f" >/dev/null 2>&1; done
codesign -f -s - --preserve-metadata=entitlements "$R" >/dev/null 2>&1
xcrun simctl uninstall "$D" com.oxapayy.puttyios || true
xcrun simctl install "$D" build/dd/Build/Products/Debug-iphonesimulator/PuTTY.app
xcrun simctl install "$D" "$R"
FP=$(ssh-keygen -lf "$SP/hostkey.pub" | awk '{print $2}')
SIMCTL_CHILD_SSH_FP="$FP" SIMCTL_CHILD_SSH_KEY="$SP/userkey_enc" SIMCTL_CHILD_SSH_PASS="$PASS" SIMCTL_CHILD_SSH_USER="$USER_NAME" SIMCTL_CHILD_SSH_PORT=$PORT SIMCTL_CHILD_SHOT_DIR="${SHOT_DIR:-}" SIMCTL_CHILD_DEMO_SCRIPT="${DEMO_SCRIPT:-}" SIMCTL_CHILD_DEMO_CLIP="${DEMO_CLIP:-}" SIMCTL_CHILD_SSH_PLAIN_KEY="$SP/userkey" \
  xcrun simctl launch --console-pty --terminate-running-process "$D" com.oxapayy.puttyios.uitests.xctrunner > build/runner.txt 2>&1 || true
grep -E "Test Case|error:|Screen:|Executed" build/runner.txt | grep -v "implemented in both"
