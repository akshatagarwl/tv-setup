#!/usr/bin/env python3
"""Copy the ONE reviewed catalog and helper to platform bundles. No TV access."""
from pathlib import Path
import argparse
import shutil

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
notice_sources = [
    'THIRD_PARTY_NOTICES.md', 'LICENSE', 'vendor/AdbLib/LICENSE',
    'vendor/SwiftADB/LICENSE-APACHE-2.0', 'vendor/licenses/BigInt-LICENSE.md',
    'vendor/licenses/swift-asn1-LICENSE.txt', 'vendor/licenses/swift-asn1-NOTICE.txt',
]
notices = '\n\n'.join(f'===== {name} =====\n{(root / name).read_text()}' for name in notice_sources).encode()
notice_path = root / 'shared/NOTICES.txt'
if args.check:
    if not notice_path.exists() or notice_path.read_bytes() != notices:
        raise SystemExit('License resource is stale; run scripts/sync-resources.py')
else:
    notice_path.write_bytes(notices)
for source in [root / 'shared/catalog.json', root / 'shared/assets/search-handoff-1.0.apk', notice_path]:
    for destination in [root / 'ios/Sources/TVSetupCore/Resources' / source.name, root / 'android/assets' / source.name]:
        if args.check:
            if not destination.exists() or source.read_bytes() != destination.read_bytes():
                raise SystemExit(f'Resource mismatch: {destination.relative_to(root)}')
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
print('Platform resources match the reviewed shared inputs.')
