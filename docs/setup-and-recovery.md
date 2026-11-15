# Setup and recovery

Use this preview only when you are happy to stop using the TV for setup. **Do not connect to, install on, or change an in-use TV.** A connection can itself show an authorization prompt.

## Guided setup

1. Put the phone and TV on the same trusted, non-guest LAN. Find the TV's IPv4 address in its network settings.
2. Enable developer options using your TV manufacturer's instructions. If it exposes **classic network debugging**, enable it and note its port, commonly 5555. USB debugging alone does not guarantee network ADB is listening. This app cannot turn on an unauthenticated TV's debugging remotely.
3. If the only option is wireless debugging with a **pairing code**, stop: this preview does not support that protocol. Do not disable TLS or expose ADB to the Internet to work around it.
4. Enter the address/port in TV Setup. On iPhone, allow Local Network access. If you denied it, enable it for TV Setup in iOS Settings.
5. Check that the TV's authorization prompt corresponds to your connection, then approve on the TV. Remembering that phone is your choice.
6. Read compatibility. Choose only wanted features; all start off. Preview changes.
7. Check the consent box only when the TV is not in use. Install; keep the phone unlocked and TV Setup foregrounded. Backgrounding during an active operation cancels unfinished work.
8. Read the result for each app. A download, package-presence check or successful installation does not verify actual playback.

## Finish on the TV

- **TizenTube:** open the app yourself, sign into YouTube if needed, search and play an allowed video. The installer never copies someone else's profile. The official APK's upstream web scripts can update separately from its APK.
- **Voice handoff:** explicitly enable the helper in TV Accessibility settings if wanted. It reads the completed Google search query and hands it to TizenTube; it neither records audio nor filters remote keys. Google still recognizes/processes your voice. Test the physical microphone button, repeated searches, navigation, held-volume repeat and actual playback. The installer does not reproduce those hardware tests.
- **Proton VPN:** open the official TV app yourself, use its sign-in QR/code and approve Android's VPN permission. No credentials or QR tokens are captured here. If wanted, configure startup auto-connect in Proton's own settings. Verify the tunnel, external exit, actual target playback, other streaming apps, LAN access and reboot/recovery before relying on it. Free streaming access/country choice is not guaranteed. Do not enable network lockdown as an untested shortcut.

## Cancel or partial failure

Disconnect/cancel closes the ADB connection and stops further operations; already-installed apps remain. Closing a socket is not an atomic rollback of Android package manager. The last app may have finished even if its success reply was lost. Reconnect and preview again: existing apps are kept, not updated or replaced. Earlier app installs are not silently undone.

A stale preview is not an instruction to overwrite an app: package presence is rechecked immediately before installation and installation never uses `-r`.

## Undo

No prior TV settings or packages were modified, so undo is limited to the **new apps explicitly marked Installed** in that run:

1. Wait until the TV is not in use.
2. If you manually enabled the handoff, turn off only that helper in TV Accessibility settings. Do not clear the entire enabled-services list. Google Assistant should remain selected.
3. If you manually connected Proton, disconnect it and undo your own startup/always-on changes in its/system settings. Check ordinary connectivity before any removal.
4. In TV Settings → Apps, disable the newly installed app if supported. Disabling preserves its app data. Uninstall only if you accept deleting that app's local data.
5. Leave apps marked **kept unchanged** alone. No automated uninstall/rollback is provided in this preview, and no app profiles/backups are collected.

After setup, consider turning off network debugging on the TV. Uninstalling TV Setup from the phone is **not** revocation of that phone's stored ADB authorization. The TV may offer per-device revocation; a global “revoke debugging authorizations” action also affects other trusted computers. iOS Keychain identities can outlive removal of the phone app.

If a VPN breaks LAN access, recover using the physical TV remote and Proton/system settings. This installer deliberately does not enable lockdown or silently reroute traffic.
