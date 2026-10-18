---
name: android-install
description: Builds the Alvyo Android app in release mode, signed with the release key, and installs it on the user's Android phone over Wi-Fi (wireless debugging, adb); runs on Haiku in a forked subagent and reports whether the app is on the phone. The phone must be paired once, unlocked and on the same Wi-Fi. Use when the user wants the new app on their Android phone.
context: fork
model: haiku
background: false
---

# Install the app on the Android phone

You run without the conversation that asked for this, and you cannot ask
the user anything: do the steps, then report.

The phone takes the app over **wireless debugging** only: USB debugging
cannot be switched on (its security settings). It runs the APK from a
GitHub Release, signed with the release key, so a local build must be
signed with the same key and have a higher version code, or Android
refuses it as an update. Never uninstall the app to get around that: it
deletes the login and the offline maps. The app talks to production, so
features that need new API endpoints work only after a release.

```sh
ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

1. **Release key:** `test -f app/android/key.properties`. Missing: stop
   and report that the one-time setup below is needed. Never read, print
   or copy that file or the keystore it names.
2. **Find the phone:** `$ADB devices -l` lists it as `device` with a
   serial that is an address (`192.168.…:port` or
   `adb-…._adb-tls-connect._tcp`); `emulator-…` does not count. Not
   listed: `$ADB mdns services`, and for a `_adb-tls-connect._tcp` row
   `$ADB connect <ip:port>`. Only a `_adb-tls-pairing` row, nothing, or
   «failed to connect»: stop and report that the phone is not paired
   (setup below), or wireless debugging is off, the phone locked or on
   another Wi-Fi. `unauthorized` or `offline`: the same.
3. **Build** (about a minute), in `app/`, numbered like the release
   workflow:
   ```sh
   flutter build apk --release \
     --build-name=$(git describe --tags --abbrev=0 | sed 's/^v//') \
     --build-number=$(git rev-list --count HEAD) \
     --dart-define=ALVYO_VERSION=$(git describe --tags --always)
   ```
4. **Install and start:**
   `$ADB -s <serial> install -r build/app/outputs/flutter-apk/app-release.apk`,
   then `$ADB -s <serial> shell am start -n ch.tellbow.alvyo/.MainActivity`.
   - `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: the installed app has another
     key than `key.properties` names. Report it; do not uninstall.
   - `INSTALL_FAILED_VERSION_DOWNGRADE`: the phone has a newer build
     (another branch or a later release). Report both version codes
     (`$ADB -s <serial> shell dumpsys package ch.tellbow.alvyo | grep versionCode`).
   - The phone may ask to confirm the install on its screen: report that
     it waits there.

Logins and offline maps survive an update.

Answer in a few lines: the version installed (`git describe --tags --always`)
and the phone (`$ADB -s <serial> shell getprop ro.product.model`), whether
it is installed and started, or the step that failed with its message.
If the setup is needed, give the user its steps as below.

## Once: the release key and pairing (the user does this)

- **Key:** the keystore from the password manager to
  `~/.android/alvyo-release.jks` (outside the repository), and
  `app/android/key.properties` (git-ignored) with four lines:
  `storeFile=/Users/<you>/.android/alvyo-release.jks`, `storePassword=…`,
  `keyAlias=alvyo`, `keyPassword=…` (the same password, as the release
  workflow writes it).
- **Pairing:** on the phone Settings → System → Developer options →
  Wireless debugging → «Pair device with pairing code»; it shows an
  address with a port and a six-digit code. In Claude Code:
  `! /opt/homebrew/share/android-commandlinetools/platform-tools/adb pair <ip:port> <code>`.
  After that the phone is found by mDNS whenever wireless debugging is
  on (it switches off on some phones when the Wi-Fi changes).
  «protocol fault (couldn't read status message)»: the running adb server
  was started where it cannot reach the local network (e.g. by the
  emulator); `$ADB kill-server`, then pair again with a new code.
