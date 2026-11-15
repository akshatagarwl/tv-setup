import hashlib
import json
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class ResourceTests(unittest.TestCase):
    def test_platforms_share_exact_catalog_and_helper(self):
        for name, source in [('catalog.json', ROOT / 'shared/catalog.json'), ('search-handoff-1.0.apk', ROOT / 'shared/assets/search-handoff-1.0.apk'), ('NOTICES.txt', ROOT / 'shared/NOTICES.txt')]:
            for folder in ['android/assets', 'ios/Sources/TVSetupCore/Resources']:
                self.assertEqual(source.read_bytes(), (ROOT / folder / name).read_bytes())

    def test_no_personal_or_community_data_in_catalog(self):
        catalog = json.loads((ROOT / 'shared/catalog.json').read_text())
        self.assertEqual(catalog['schema'], 1)
        self.assertEqual([f['id'] for f in catalog['features']], ['tizentube', 'voice', 'proton'])
        for feature in catalog['features']:
            for artifact in feature['artifacts']:
                self.assertRegex(artifact['sha256'], r'^[a-f0-9]{64}$')
                self.assertRegex(artifact['signerSha256'], r'^[a-f0-9]{64}$')
                self.assertTrue(artifact['source'].startswith('https://github.com/'))
        self.assertNotIn('communityBlocklist', json.dumps(catalog))

    def test_bundled_helper_exact_public_artifact(self):
        catalog = json.loads((ROOT / 'shared/catalog.json').read_text())
        helper = next(f for f in catalog['features'] if f['id'] == 'voice')['artifacts'][0]
        file = ROOT / 'shared/assets/search-handoff-1.0.apk'
        self.assertEqual(file.stat().st_size, helper['size'])
        self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(), helper['sha256'])
        with zipfile.ZipFile(file) as archive:
            for name in archive.namelist():
                self.assertFalse(name.endswith(('.keystore', '.jks', '.db', '.tar', '.p12')))
                self.assertNotIn('blocked_channel', name)

    def test_phone_permissions_are_minimal(self):
        manifest = ET.parse(ROOT / 'android/AndroidManifest.xml').getroot()
        name = '{http://schemas.android.com/apk/res/android}name'
        self.assertEqual([p.attrib[name] for p in manifest.findall('uses-permission')], ['android.permission.INTERNET'])
        app = manifest.find('application')
        self.assertEqual(app.attrib['{http://schemas.android.com/apk/res/android}allowBackup'], 'false')
        self.assertEqual(app.attrib['{http://schemas.android.com/apk/res/android}usesCleartextTraffic'], 'false')
        self.assertEqual(manifest.findall('.//service'), [])

    def test_installer_does_not_change_permissions_vpn_or_remove_apps(self):
        files = list((ROOT / 'android/src').rglob('*.java')) + list((ROOT / 'ios/Sources/TVSetupCore').glob('*.swift'))
        for file in files:
            source = file.read_text()
            for command in ['settings put', 'pm uninstall', 'pm disable-user', 'pm clear', 'appops set', 'always_on_vpn_lockdown', 'adb -s', 'FLAG_REQUEST_FILTER_KEY_EVENTS']:
                self.assertNotIn(command, source, str(file))
        self.assertIn('exec:cmd package install --user 0 -S', (ROOT / 'android/src/com/cgutman/adblib/LegacyClient.java').read_text())
        self.assertIn('exec:cmd package install --user 0 -S', (ROOT / 'ios/Sources/TVSetupCore/LegacyADB.swift').read_text())


if __name__ == '__main__':
    unittest.main()
