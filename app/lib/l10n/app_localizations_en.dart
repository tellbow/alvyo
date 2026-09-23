// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'odysgeh';

  @override
  String get loginTitle => 'Log in';

  @override
  String get server => 'Server';

  @override
  String get login => 'E-mail or username';

  @override
  String get password => 'Password';

  @override
  String get loginSubmit => 'Log in';

  @override
  String get loginInvalid => 'Wrong e-mail/username or password.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorServer => 'The server cannot be reached.';

  @override
  String get routesTitle => 'My routes';

  @override
  String get routesEmpty => 'No routes yet. Plan them on the website.';

  @override
  String get logout => 'Log out';

  @override
  String get offlineSave => 'Save offline';

  @override
  String get offlineSaved => 'Saved offline – remove';

  @override
  String get offlinePreparing => 'Preparing the offline map …';

  @override
  String get offlineDownloading => 'Downloading the offline map …';

  @override
  String get offlineOutdated => 'Route changed – update the offline map';

  @override
  String get offlineFailed => 'The offline map could not be saved.';

  @override
  String get routesOffline => 'Offline – saved routes only';
}
