import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import '../session.dart';

/// Log in to an Alvyo server.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session, required this.onLoggedIn});
  final Session session;
  final void Function(Api api) onLoggedIn;

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
    widget.session.lastServer().then((s) => _server.text = s);
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = Api(_server.text.trim());
    try {
      await api.login(_login.text.trim(), _password.text);
      await widget.session.save(api);
      widget.onLoggedIn(api);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 401 ? t.loginInvalid : t.errorGeneric);
    } catch (_) {
      // offline, no such server, or an address that is none
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.loginTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
          ],
        ),
      ),
    );
  }
}
