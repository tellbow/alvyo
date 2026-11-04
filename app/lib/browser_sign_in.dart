import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The alvyo://signin link a provider's sign-in in the browser comes back
/// with (Android: SignInAnswerActivity); the login screen waits for it.
final signInAnswer = ValueNotifier<Uri?>(null);

/// The PKCE challenge of [verifier]: only this app can fetch the sign-in.
String challengeOf(String verifier) =>
    base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
