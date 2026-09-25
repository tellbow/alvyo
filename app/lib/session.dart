import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Keeps the server and session token in the Keychain / Keystore.
class Session {
  Session({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const defaultServer = 'https://alvyo.tellbow.ch';
  final FlutterSecureStorage _storage;

  /// The saved login, if any.
  Future<Api?> restore() async {
    final server = await _storage.read(key: 'server');
    final token = await _storage.read(key: 'token');
    if (server == null || token == null) return null;
    return Api(
      server,
      token: token,
      userId: await _storage.read(key: 'user'),
    );
  }

  Future<void> save(Api api) async {
    await _storage.write(key: 'server', value: api.server);
    await _storage.write(key: 'token', value: api.token);
    await _storage.write(key: 'user', value: api.userId);
  }

  Future<void> clear() async {
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'user');
  }

  Future<String> lastServer() async => await _storage.read(key: 'server') ?? defaultServer;
}
