# Security and privacy

## Boundaries

- Bundled, versioned catalog; no remote recipe imports, mutable release URLs, custom shell fields, arbitrary modules or automatic updates.
- Explicit private IPv4 only. No discovery, device enumeration, public hosts, DNS resolution of user-entered names or telemetry.
- Classic ADB authenticates the phone to the TV but does not provide encrypted, mutual server authentication. Private address validation is a scope guard, **not proof of device identity**. Only use a trusted LAN and approve the correct TV prompt. Wireless-debugging pairing/TLS is not implemented; no fallback is attempted.
- One connection and one serial stream/operation at a time. Stream IDs, command types, checksum, payload bounds and 64 KiB output bounds are checked. I/O timeouts close failing sockets; cancellation closes the connection. No original vendor background reader/stream implementation is used.
- Only fixed model/SDK/ABI/TV-feature/current-user commands and catalog package-presence checks are exposed. There is no public arbitrary-shell API. The Android TV owner profile is required.
- Installation is the sole privileged write: `exec:cmd package install --user 0 -S <bounded integer>`. No reinstall/update flags, uninstall, data clear, launches, settings writes, permission grants or profile copies. Existing apps are kept. Sign-ins/TV prompts remain user actions.

## Artifact trust

Pins in `shared/catalog.json` cover exact byte size, whole-file SHA256, APK package/version, SDK/ABI compatibility and publisher certificate. HTTPS release redirects are restricted to GitHub and its release-asset hosts; downloaded bytes are capped before storage can grow beyond the pinned size. Partial/mismatched downloads are discarded. The helper is a pinned public companion, not a clone of personal app data.

Release preparation uses Android `apksigner verify` to verify complete v2 signatures. iOS hashes the complete file, then extracts the first v2 signer's certificate fingerprint; that bounded extractor is **not independently verifying the APK signature**. Android reads archive package/version/signers after hash verification. A pinned, prevalidated APK plus the TV package manager provides the installation trust chain. A malicious publisher, compromised build/pin update or compromised phone/TV is outside what this design can prevent.

Official TizenTube's web-script URL in its native APK follows upstream JSDelivr updates. APK pins **do not pin this runtime code**. This limitation is disclosed before installation. A future custom pinned build needs a reviewed artifact/release pipeline, not a private profile dump.

## Phone-side data

- iPhone ADB RSA identity: phone Keychain, `WhenUnlockedThisDeviceOnly`; no export or backup function. Native RSA/SHA1 is used only as required by legacy ADB authentication, not for download integrity.
- Android ADB identity: app-private `noBackupFilesDir`, on the phone's normal encrypted filesystem; not claimed to be hardware-backed. Backups are disabled. A damaged identity is not silently replaced.
- TV connection details, selection and results live in memory only. No serial numbers, app profiles, broad installed-app inventories, microphone/camera data, passwords, QR tokens or blocklists are collected. Model/Android/CPU and relevant package-presence checks are read for compatibility.
- Public APKs use app-private temporary/cache storage and are removed after completion or a handled failure. An OS kill may leave a partial cache file for normal OS cache cleanup; it contains public APK bytes, not account data.
- Publishers/CDNs see download requests and the phone's public network address under their own privacy policies. YouTube, Google recognition and Proton account/VPN traffic happen in their own TV apps after the user's choices.
- Both apps include license notices. No signing keystore or provisioning profile belongs in the repository or distributed installer.

## Deliberate omissions

No accessibility remote-key filtering, YouTube system-app replacement, signature bypass, root, offline voice-model downloads, certificate bypass, VPN configuration, lockdown, persistent device receipts, community-data redistribution or automatic rollback. Optional preference lists need licensing review, provenance, personal-list separation and reversible per-source controls before implementation.

## Validation still required

All initial tests use fake ADB peers or local APK files. Real-phone permissions/backgrounding, real-TV authentication, stream installation/cancellation/recovery, existing sign-ins, physical mic, held volume, playback and VPN recovery must be tested in a separately authorized session. Do not interpret a compiled installer as evidence those workflows work end to end.
