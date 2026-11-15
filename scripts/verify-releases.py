#!/usr/bin/env python3
"""Release preparation only: verify official APKs locally; never connects to ADB.

Usage: verify-releases.py --apk artifact-id=/path/to/app.apk
       verify-releases.py --download tizentube-arm64
Downloads, if explicitly requested, stay in ignored private/release-artifacts/.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / 'shared/catalog.json').read_text())
ARTIFACTS = {a['id']: a for f in CATALOG['features'] for a in f['artifacts']}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', action='append', default=[])
parser.add_argument('--download', action='append', choices=list(ARTIFACTS), default=[])
args = parser.parse_args()
sdk = Path(os.environ.get('ANDROID_SDK_ROOT', os.environ.get('ANDROID_HOME', '/opt/homebrew/share/android-commandlinetools')))
build_tools = sdk / 'build-tools/34.0.0'
env = dict(os.environ, JAVA_HOME=os.environ.get('JAVA_HOME', '/opt/homebrew/opt/openjdk@17'))
inputs = {}
for item in args.apk:
    key, path = item.split('=', 1)
    if key not in ARTIFACTS:
        parser.error('Unknown artifact ID')
    inputs[key] = Path(path)
for key in args.download:
    artifact = ARTIFACTS[key]
    if artifact['url'].startswith('bundled:'):
        inputs[key] = ROOT / 'shared/assets/search-handoff-1.0.apk'
        continue
    path = ROOT / 'private/release-artifacts' / (key + '.apk')
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        try:
            request = urllib.request.Request(artifact['url'], headers={'User-Agent': 'TVSetup-release-verifier'})
            with urllib.request.urlopen(request, timeout=60) as response, path.open('wb') as output:
                total = 0
                while chunk := response.read(65536):
                    total += len(chunk)
                    if total > artifact['size']:
                        raise ValueError('Publisher download exceeds pinned size')
                    output.write(chunk)
        except BaseException:
            path.unlink(missing_ok=True)
            raise
    inputs[key] = path
if not inputs:
    parser.error('Choose a local APK or an explicit download')
for key, path in inputs.items():
    artifact = ARTIFACTS[key]
    digest = hashlib.sha256()
    with path.open('rb') as source:
        while chunk := source.read(65536):
            digest.update(chunk)
    assert path.stat().st_size == artifact['size'], (key, 'size')
    assert digest.hexdigest() == artifact['sha256'], (key, 'SHA256')
    verified = subprocess.run([str(build_tools / 'apksigner'), 'verify', '--verbose', '--print-certs', str(path)], env=env, check=True, text=True, capture_output=True).stdout
    signers = re.findall(r'Signer #\d+ certificate SHA-256 digest: ([a-f0-9]+)', verified)
    assert signers == [artifact['signerSha256']], (key, 'publisher')
    assert 'Verified using v2 scheme (APK Signature Scheme v2): true' in verified, (key, 'APK v2 signature')
    badging = subprocess.run([str(build_tools / 'aapt'), 'dump', 'badging', str(path)], check=True, text=True, capture_output=True).stdout
    assert f"name='{artifact['package']}'" in badging.splitlines()[0], (key, 'package')
    assert f"versionName='{artifact['version']}'" in badging.splitlines()[0], (key, 'version')
    assert f"sdkVersion:'{artifact['minSdk']}'" in badging.splitlines(), (key, 'minimum SDK')
    for abi in artifact['abis']:
        assert f"'{abi}'" in next(line for line in badging.splitlines() if line.startswith('native-code:')), (key, 'ABI')
    print(f"Verified {key}: size, SHA256, v2 signature, publisher, package, version, SDK, ABI.")
