import 'package:flutter/material.dart';

import '../api.dart';
import '../errors.dart';
import '../l10n/app_localizations.dart';

/// A screen that could not load: what went wrong, and «Nochmals versuchen»
/// unless trying again cannot help (gone, private, refused).
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final refused = error is ApiException && (error as ApiException).status < 500;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('error-state'),
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Icon(refused ? Icons.error_outline : Icons.cloud_off, size: 40),
            Text(errorText(t, error), textAlign: TextAlign.center),
            if (onRetry != null && !refused)
              TextButton(key: const Key('error-retry'), onPressed: onRetry, child: Text(t.discoverRetry)),
          ],
        ),
      ),
    );
  }
}
