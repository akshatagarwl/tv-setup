# Third-party components

TV Setup's own code is MIT licensed. Component licenses continue to apply.

- **SwiftADB**, https://github.com/akshaynexus/SwiftADB, commit `1044bec57ee3aef4b7c556fce2e76b24257769e5`: codec, RSA keys and Android public-key conversion only. The Apache-2.0 option of its `GPL-3.0-or-later OR Apache-2.0` headers is selected. The read helper derived from `AdbConnection.swift` additionally retains BSD-3-Clause. Full licenses: `vendor/SwiftADB/LICENSE-*`.
- **AdbLib**, Copyright (c) 2013 Cameron Gutman, https://github.com/cgutman/AdbLib, commit `d6937951eb98557c76ee2081e383d50886ce109a`: codec, RSA and Base64 interface only; BSD-3-Clause, `vendor/AdbLib/LICENSE`.
- **BigInt 5.7.0**, https://github.com/attaswift/BigInt, Copyright (c) 2016–2017 Károly Lőrentey: MIT, `vendor/licenses/BigInt-LICENSE.md`.
- **SwiftASN1 1.7.1**, https://github.com/apple/swift-asn1, Copyright 2022 The SwiftASN1 Project: Apache-2.0, `vendor/licenses/swift-asn1-LICENSE.txt` and `vendor/licenses/swift-asn1-NOTICE.txt`.
- **TV search handoff 1.0**, https://github.com/akshatagarwl/tv-search-handoff/tree/fbd2c30bf7cbf751984c8bf1bb30b9a8fdcff3d2, Copyright (c) 2026 Akshat Agarwal: MIT, `shared/assets/LICENSE-search-handoff`. Only this small companion APK is bundled. Its public signing certificate is not a signing key.

TizenTube and Proton VPN are downloaded from their official releases on request, not repackaged here. Their own licenses and upstream services apply. No blocklists, account profiles or personal settings are distributed.

The Java test runner downloads the Apache-2.0 Android JSON implementation from `com.vaadin.external.google:android-json:0.0.20131108.vaadin1`, Maven Central, SHA256 `dfb7bae2f404cfe0b72b4d23944698cb716b7665171812a0a4d0f5926c0fac79`. It is test-only and never packaged in the installer; Android supplies `org.json` at runtime.

The resource synchronization script packages this notice and the complete runtime license texts in both apps.
