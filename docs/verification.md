# Initial local preview verification

## Passed

- Android phone installer builds with JDK 17, platform 34/build-tools 34.0.0. `dist/tv-setup-debug.apk` passes APK v2/v3 signature verification.
- iPhone project builds unsigned for both `generic/platform=iOS Simulator` and `generic/platform=iOS` using Xcode. Generated products are under `ios/DerivedData/Build/Products/`. These are build artifacts, not provisioned phone installs.
- **15 Swift XCTest tests** pass, including all three reviewed official release APK fixtures, with zero failures.
- **5 Python tests** pass for exact shared resources, data exclusions, companion hash, phone permissions and privileged-command boundaries.
- **89 Java checks** pass: 72 ADB/transport checks plus 17 catalog/planner checks. These use fake byte streams, not hardware.
- Shared catalog, helper APK and complete license notices match both platform bundles byte-for-byte.
- All four catalog artifacts pass independent `apksigner` full-v2-signature validation, pinned SHA256/size/certificate, package/version, minimum SDK and declared ABI checks: TizenTube ARM32/ARM64, Proton VPN and search handoff.
- The native Swift certificate extractor independently recognizes the pinned certificate in the helper and all three official release APKs after whole-file SHA256 verification.
- Bundled helper accessibility XML explicitly declares `canRequestFilterKeyEvents=false`; its flags are `0x50`, not a key-filter request. The phone installer declares only Internet permission and no services.

The Swift tests cover explicit endpoint scope, missing dependencies, unsupported TV/SDK/CPU, keeping existing packages, bad metadata, tampered downloads, malformed APKs/ADB packets, AUTH signature/public-key order, refusing TLS instead of downgrading, read-only probes, byte-exact chunked install streams, no reinstall flags, package confirmation and mismatched stream closure.

## Not verified

No phone app was installed, no simulator UI was launched (no iOS simulator runtime is installed locally), and **no TV was contacted, inspected, installed to, restarted or interrupted**. The currently protected TV session and both reported account sign-ins were left alone.

Pending hardware validation: local-network permissions, TV authorization, actual APK stream installation and cancellation, partial-failure recovery, existing-app preservation on device, account flows, enabling the helper, physical microphone search, held-volume repeat, playback, VPN connection/exit, startup auto-connect, LAN access and reboot/recovery.

Community filtering, personal-list import, shortcut/launcher setup, persistent receipts and automated rollback are not implemented in this preview. Apple signing, TestFlight/App Store delivery and production Android distribution are not configured.

## Repeat

```sh
python3 scripts/sync-resources.py --check
bash scripts/test.sh
bash scripts/build-android.sh
```

The fixture test skips unless `TVSETUP_RELEASE_APK_DIR` points to explicitly reviewed local APKs named by catalog artifact ID. Downloads are not performed by tests. `scripts/verify-releases.py` is a separate opt-in release-preparation tool. Build/test logs and downloaded release APKs remain ignored local files, not published evidence containing private device state.
