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

  @override
  String get navStart => 'Wanderung starten';

  @override
  String get navResume => 'Wanderung fortsetzen';

  @override
  String get navDone => 'Gegangen';

  @override
  String get navRemaining => 'Noch';

  @override
  String get navElapsed => 'Unterwegs';

  @override
  String navOffRoute(int metres) {
    return '$metres m neben der Route';
  }

  @override
  String get navOffRouteTitle => 'Nicht mehr auf der Route';

  @override
  String get navArrived => 'Ziel erreicht';

  @override
  String get navWaiting => 'Warte auf GPS …';

  @override
  String get navFinish => 'Beenden';

  @override
  String get navFinishQuestion => 'Wanderung beenden und die Aufzeichnung speichern?';

  @override
  String get navContinue => 'Weitergehen';

  @override
  String get navNoPermission => 'Dafür braucht die App deinen Standort. Erlaube ihn in den Einstellungen.';

  @override
  String navSaved(String distance, String duration) {
    return 'Aufgezeichnet: $distance in $duration. Wird hochgeladen, sobald du online bist.';
  }

  @override
  String get navFollow => 'Meiner Position folgen';

  @override
  String navUploaded(String distance, String duration) {
    return 'Gespeichert unter «Meine Routen»: $distance in $duration';
  }

  @override
  String routesHiked(String date) {
    return 'Gewandert am $date';
  }

  @override
  String get watchTitle => 'Von der Apple Watch';

  @override
  String get watchHike => 'Wanderung';

  @override
  String get watchWalk => 'Spaziergang';

  @override
  String get watchImport => 'Importieren';

  @override
  String get watchImported => 'Importiert – in «Meine Routen»';

  @override
  String get watchNoTrack => 'Dieses Training hat keine GPS-Strecke.';

  @override
  String get watchEmpty =>
      'Keine Wanderungen der letzten 60 Tage in Apple Health. Zeichne sie auf der Apple Watch mit der App «Training» auf («Wandern» oder «Gehen» im Freien). Falls du den Zugriff nicht erlaubt hast: Einstellungen → Apps → Health → Datenzugriff & Geräte → odysgeh.';

  @override
  String get watchUnavailable => 'Apple Health ist auf diesem Gerät nicht verfügbar.';

  @override
  String watchOutside(String reason) {
    return 'Nicht importiert: $reason';
  }
}
