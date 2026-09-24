---
name: iphone-install
description: Build the odysgeh iOS app in release mode and install it on the user's iPhone over Wi-Fi, including the fallback when Flutter's install or launch step fails. Use when the user wants the new app on their phone.
---

# Install the app on the iPhone

The iPhone («Wodan») was paired by cable once and is reachable over Wi-Fi.
It uses a free Apple ID: an installed app stops starting after 7 days, and
installing again renews it. The app talks to production, so features that
need new API endpoints work only after a release.

1. The phone must be **unlocked** and on the same Wi-Fi; ask the user if
   unsure.
2. `cd app && flutter devices` lists «Wodan (wireless)» with its id.
3. `flutter run --release --no-resident -d <id>` builds (about a minute),
   installs and starts the app.
4. If it ends with «Could not run build/ios/iphoneos/Runner.app»: the build is
   there, install it directly:
   `xcrun devicectl device install app --device <id> build/ios/iphoneos/Runner.app`.
   Starting it needs the phone unlocked
   (`xcrun devicectl device process launch --device <id> ch.tellbow.odysgeh`),
   otherwise the user opens it. «Device is busy (Connecting to Wodan)» or
   «disconnected immediately» mean the phone is locked or asleep.
5. Signing: Flutter takes the «Apple Development» certificate of the Apple ID
   in Xcode (Settings → Accounts). If
   `security find-identity -v -p codesigning` finds no valid identity,
   Apple's WWDR G3 intermediate certificate is missing from the keychain
   (https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer).

Logins and offline maps survive an update.
