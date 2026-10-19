import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

/// What the system's «Sign in with Apple» sheet hands over: tokens for the
/// API, and the name only on the first sign-in.
typedef AppleCredential = ({String identityToken, String authorizationCode, String name});

/// Shows the system's sheet (AppleSignIn in AppDelegate.swift); null when
/// the person cancels. [nonce] goes into the identity token as its SHA-256.
Future<AppleCredential?> appleSignIn(String nonce) async {
  try {
    final r = await const MethodChannel('alvyo/apple-sign-in').invokeMapMethod<String, String>('signIn', nonce);
    if (r == null) return null;
    return (identityToken: r['identityToken']!, authorizationCode: r['authorizationCode']!, name: r['name'] ?? '');
  } on PlatformException catch (e) {
    if (e.code == 'canceled') return null;
    rethrow;
  }
}

/// A fresh random nonce: it binds the identity token to this sign-in.
String newNonce() {
  final r = Random.secure();
  return base64Url.encode(List.generate(32, (_) => r.nextInt(256))).replaceAll('=', '');
}
