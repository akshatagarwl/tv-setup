# Reviewed vendor subset

Pins and licenses are recorded in `../THIRD_PARTY_NOTICES.md`.

## SwiftADB

Only `AdbError.swift`, `AdbProtocol.swift`, `AndroidPubkey.swift` and `KeyPair.swift` are retained from the pin. `ReadExactly.swift` extracts the small read helper and explicitly handles TCP segmentation. `Package.swift` is a local replacement selecting just these primitives, with exact BigInt/SwiftASN1 versions from upstream's resolved lockfile. Packet decoding uses `loadUnaligned` rather than trapping on unaligned `Data` storage. The original connection/stream/pairing implementations are **not shipped or used**.

Our `LegacyADB` adapter owns single-stream serialization, close/error behavior, output limits and I/O deadlines. Pairing-code/TLS support is deliberately absent; there is no automatic fallback or downgrade.

## AdbLib

Only `AdbBase64`, `AdbCrypto`, `AdbProtocol` and the package documentation are retained. The protocol parser has a local pre-allocation guard: invalid magic, negative lengths and payloads above 262,144 bytes are rejected before allocating. Original connection and stream implementations are **not shipped or used**. Our sequential adapter lives under `android/src/com/cgutman/adblib/LegacyClient.java`.

These are recorded source snapshots, not unmodified mirrors. Tests exercise the adapters through fake byte/packet transports; real-TV validation remains a separate, user-authorized step.
