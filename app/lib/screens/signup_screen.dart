import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'wide.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';

/// Creates an account in the app, as the website's sign-up page does; the
/// address is confirmed by the link in the e-mail, then one logs in.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.server, this.client});
  final String server;

  /// For tests: the server's answers.
  final http.Client? client;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _usernameTaken;
  String? _error;
  String? _sent;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _usernameTaken = null;
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final email = _email.text.trim();
    try {
      await Api(widget.server, client: widget.client).signup(
        email: email,
        username: _username.text.trim(),
        displayName: _displayName.text.trim(),
        password: _password.text,
        locale: t.localeName,
      );
      if (mounted) setState(() => _sent = email);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          if (e.status == 409 && e.errors.any((d) => d['location'] == 'body.username')) {
            _usernameTaken = t.signupUsernameTaken;
          } else {
            _error = e.status == 429 ? t.errorTooMany : t.errorGeneric;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = t.errorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.loginSignup)),
      body: Readable(
        child: SafeArea(
          child: _sent != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(key: const Key('signup-sent'), t.signupSent(_sent!)),
                )
              : Form(
                  key: _form,
                  child: AutofillGroup(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        TextFormField(
                          key: const Key('signup-email'),
                          controller: _email,
                          decoration: InputDecoration(labelText: t.contactsEmail),
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.email],
                          validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch(v!.trim()) ? null : t.shareBadEmail,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('signup-username'),
                          controller: _username,
                          decoration: InputDecoration(
                            labelText: t.signupUsername,
                            helperText: t.signupUsernameHint,
                            errorText: _usernameTaken,
                          ),
                          autocorrect: false,
                          autofillHints: const [AutofillHints.newUsername],
                          validator: (v) =>
                              RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(v!.trim()) ? null : t.signupUsernameHint,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('signup-name'),
                          controller: _displayName,
                          decoration: InputDecoration(labelText: t.signupDisplayName, counterText: ''),
                          autofillHints: const [AutofillHints.name],
                          maxLength: 60,
                          validator: (v) => v!.trim().isEmpty ? t.signupDisplayNameMissing : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('signup-password'),
                          controller: _password,
                          decoration: InputDecoration(labelText: t.password, helperText: t.signupPasswordHint),
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (v) => v!.length < 10 || v.length > 128 ? t.signupPasswordHint : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        FilledButton(
                          key: const Key('signup-submit'),
                          onPressed: _busy ? null : _submit,
                          child: Text(t.loginSignup),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
