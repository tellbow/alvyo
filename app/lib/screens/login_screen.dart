import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'signup_screen.dart';
import 'wide.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import '../session.dart';

/// Log in to an Alvyo server, or sign up; a forgotten password on its website.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.session,
    required this.onLoggedIn,
    this.client,
    this.showServer = kDebugMode,
  });
  final Session session;
  final void Function(Api api) onLoggedIn;

  /// The server field: only in debug builds (local servers, the tests);
  /// release builds always use [Session.defaultServer].
  final bool showServer;

  /// For tests: the server's answers.
  final http.Client? client;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.showServer) {
      _server.text = Session.defaultServer;
      return;
    }
    // Unless typed in meanwhile: secure storage can take a moment (Android).
    widget.session.lastServer().then((s) {
      if (mounted && _server.text.isEmpty) _server.text = s;
    });
  }

  @override
  void dispose() {
    _server.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = Api(_server.text.trim(), client: widget.client);
    try {
      await api.login(_login.text.trim(), _password.text);
      await widget.session.save(api);
      widget.onLoggedIn(api);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e.status) {
            401 => t.loginInvalid,
            403 when e.errors.any((d) => d['message'] == 'unverified') => t.loginUnverified,
            _ => t.errorGeneric,
          },
        );
      }
    } catch (_) {
      // offline, no such server, or an address that is none
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A page of the server's website, in a browser view inside the app
  /// (App Review wants no switch to Safari around signing in).
  Future<void> _web(String page) =>
      launchUrl(Uri.parse('${Api(_server.text).server}$page'), mode: LaunchMode.inAppBrowserView);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.loginTitle)),
      body: Readable(
        child: SafeArea(
          // One group: iOS offers to keep the login in the Keychain.
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.showServer)
                  TextField(
                    key: const Key('server'),
                    controller: _server,
                    decoration: InputDecoration(labelText: t.server),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                TextField(
                  key: const Key('login'),
                  controller: _login,
                  decoration: InputDecoration(labelText: t.login),
                  autocorrect: false,
                  autofillHints: const [AutofillHints.username],
                ),
                TextField(
                  key: const Key('password'),
                  controller: _password,
                  decoration: InputDecoration(labelText: t.password),
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(key: const Key('submit'), onPressed: _busy ? null : _submit, child: Text(t.loginSubmit)),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('signup'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SignupScreen(server: _server.text.trim(), client: widget.client),
                    ),
                  ),
                  child: Text(t.loginSignup),
                ),
                TextButton(
                  key: const Key('forgot'),
                  onPressed: () => _web('/forgot-password'),
                  child: Text(t.loginForgot),
                ),
                TextButton(
                  key: const Key('privacy'),
                  onPressed: () => _web('/about#privacy'),
                  child: Text(t.aboutPrivacy),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
