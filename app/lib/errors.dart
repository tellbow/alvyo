import 'api.dart';
import 'l10n/app_localizations.dart';

/// What to say when loading failed: gone or private is not the server being
/// unreachable.
String errorText(AppLocalizations t, Object? error) => switch (error) {
  ApiException(status: 404) => t.errorNotFound,
  ApiException(:final status) when status >= 400 && status < 500 => t.errorGeneric,
  _ => t.errorServer,
};
