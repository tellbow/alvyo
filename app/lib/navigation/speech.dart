import 'package:flutter/services.dart';

/// Spoken prompts (AppDelegate.swift): other audio is turned down meanwhile,
/// also with the screen locked.
class Speech {
  static const _channel = MethodChannel('alvyo/speech');

  /// Says [text] in [language] (de, en, fr or it).
  Future<void> say(String text, String language) async {
    try {
      await _channel.invokeMethod<void>('say', {'text': text, 'language': language});
    } on PlatformException {
      // no voice: the banner shows it all the same
    } on MissingPluginException {
      // not on iOS
    }
  }
}
