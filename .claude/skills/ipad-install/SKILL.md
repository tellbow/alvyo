---
name: ipad-install
description: Builds the Alvyo iOS app in release mode and installs it on the user's iPad over Wi-Fi (or cable), including the fallback when Flutter's install or launch step fails; runs on Haiku in a forked subagent and reports whether the app is on the iPad. The iPad must be paired once, unlocked and on the same Wi-Fi. Use when the user wants the new app on their iPad.
context: fork
model: haiku
background: false
---

# Install the app on the iPad

You run without the conversation that asked for this, and you cannot ask
the user anything: do the steps, then report.

The iPad («iPad von Wodan», 10th generation) uses the same free Apple
ID as the iPhone: an installed app stops starting after 7 days, and
installing again renews it. The app talks to production, so features
that need new API endpoints work only after a release. Its wide layout
(rail, maps beside their panel) is requirement 73 in `docs/plan.md`.

1. Find the iPad: `xcrun devicectl list devices` shows it as a row with an
   iPad model (`iPad13,…`) and «physical»; simulated iPads do not count.
   `cd app && flutter devices` lists it by the same name, «(wireless)»
   over Wi-Fi, and its id. «available (paired)» (Wi-Fi) and «connected»
   (cable) both do. If no physical iPad is listed, or it is
   «unavailable», stop and report that the one-time pairing below
   is needed, or that the iPad must be unlocked and on the same Wi-Fi.
2. `flutter run --release --no-resident -d <id> --dart-define=ALVYO_VERSION=$(git describe --tags --always)`
   builds (about a minute), installs and starts the app; bug reports from
   the app name that version.
3. If it ends with «Could not run build/ios/iphoneos/Runner.app»: the build is
   there, install it directly:
   `xcrun devicectl device install app --device <id> build/ios/iphoneos/Runner.app`,
   then start it:
   `xcrun devicectl device process launch --device <id> ch.tellbow.alvyo`.
   «Device is busy (Connecting to …)» or «disconnected immediately» mean
   the iPad is locked or asleep: stop and report that. Do not build again;
   the next try needs only these two commands.
4. Signing: Flutter takes the «Apple Development» certificate of the Apple ID
   in Xcode (Settings → Accounts). If
   `security find-identity -v -p codesigning` finds no valid identity,
   Apple's WWDR G3 intermediate certificate is missing from the keychain
   (https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer): report
   that, do not change the keychain. «No profiles for 'ch.tellbow.alvyo'
   were found» or «device not registered»: the iPad was not yet in Xcode
   (pairing step 3); report that. «unavailable» in step 1 for a paired
   iPad means it is locked, asleep or not on the Mac's Wi-Fi.

Logins and offline maps survive an update.

## One-time pairing (the user does it; report it as needed)

1. Connect the iPad by cable, unlock it, tap «Vertrauen» (Trust).
2. On the iPad: Einstellungen › Datenschutz & Sicherheit › Entwicklermodus
   on, restart, confirm. The switch shows only after the iPad has been
   connected to Xcode once.
3. In Xcode: Window › Devices and Simulators, select the iPad and wait
   until it is prepared. Then the cable can go: since Xcode 15 a paired
   device connects over Wi-Fi by itself (there is no «Connect via
   network» any more).
4. After the first install: Einstellungen › Allgemein › VPN &
   Geräteverwaltung › the Apple ID's developer app › «Vertrauen», or the
   app does not start.

Answer in a few lines: the version installed (`git describe --tags --always`),
the iPad's name, whether it is installed and started, or the step that
failed with its error message. If the iPad was locked or is not paired, say
so first, with the pairing steps when they are needed.
