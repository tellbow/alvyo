// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'odysgeh';

  @override
  String get loginTitle => 'Anmelden';

  @override
  String get server => 'Server';

  @override
  String get login => 'E-Mail oder Benutzername';

  @override
  String get password => 'Passwort';

  @override
  String get loginSubmit => 'Anmelden';

  @override
  String get loginInvalid => 'E-Mail/Benutzername oder Passwort ist falsch.';

  @override
  String get errorGeneric => 'Etwas ist schiefgelaufen. Bitte versuche es nochmals.';

  @override
  String get errorServer => 'Der Server ist nicht erreichbar.';

  @override
  String get routesTitle => 'Meine Routen';

  @override
  String get routesEmpty => 'Noch keine Routen. Plane sie auf der Website.';

  @override
  String get logout => 'Abmelden';

  @override
  String get offlineSave => 'Offline speichern';

  @override
  String get offlineSaved => 'Offline gespeichert – entfernen';

  @override
  String get offlinePreparing => 'Die Offline-Karte wird vorbereitet …';

  @override
  String get offlineDownloading => 'Die Offline-Karte wird geladen …';

  @override
  String get offlineOutdated => 'Route geändert – Offline-Karte aktualisieren';

  @override
  String get offlineFailed => 'Die Offline-Karte konnte nicht gespeichert werden.';

  @override
  String get routesOffline => 'Offline – nur gespeicherte Routen';
}
