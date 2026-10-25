import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// The app's Firebase settings, for Google Analytics (analytics.dart), as
/// `flutterfire configure` writes them, from GoogleService-Info.plist and
/// google-services.json (project alvyo-d40db). Not secret: every
/// installed app holds them, and each API key is restricted to its app in
/// Google Cloud. null: not set up (forks, a platform not yet registered),
/// so no statistics.
class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform => switch (defaultTargetPlatform) {
    TargetPlatform.android => android,
    TargetPlatform.iOS => ios,
    _ => null,
  };

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyAN_rFlQA0kyP5tWer9Ia_BAtdz5TSURnk',
    appId: '1:206355517966:android:a73827a538aebe67e0225f',
    messagingSenderId: '206355517966',
    projectId: 'alvyo-d40db',
    storageBucket: 'alvyo-d40db.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyBdP5_xbsH9t4XgVbagbmhCYL3Bbyb3SIo',
    appId: '1:206355517966:ios:ed373835e1699c23e0225f',
    messagingSenderId: '206355517966',
    projectId: 'alvyo-d40db',
    storageBucket: 'alvyo-d40db.firebasestorage.app',
    iosBundleId: 'ch.tellbow.alvyo',
  );
}
