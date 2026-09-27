// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Alvyo';

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
      'Keine Wanderungen der letzten 60 Tage in Apple Health. Zeichne sie auf der Apple Watch mit der App «Training» auf («Wandern» oder «Gehen» im Freien). Falls du den Zugriff nicht erlaubt hast: Einstellungen → Apps → Health → Datenzugriff & Geräte → Alvyo.';

  @override
  String get watchUnavailable => 'Apple Health ist auf diesem Gerät nicht verfügbar.';

  @override
  String watchOutside(String reason) {
    return 'Nicht importiert: $reason';
  }

  @override
  String get watchReasonOutside => 'sie verlässt die Schweiz und Liechtenstein.';

  @override
  String get watchReasonShort => 'sie ist zu kurz.';

  @override
  String get turnSharpLeft => 'Scharf links abbiegen';

  @override
  String get turnLeft => 'Links abbiegen';

  @override
  String get turnSlightLeft => 'Leicht links abbiegen';

  @override
  String get turnKeepLeft => 'Links halten';

  @override
  String get turnUTurn => 'Umkehren';

  @override
  String get turnSlightRight => 'Leicht rechts abbiegen';

  @override
  String get turnRight => 'Rechts abbiegen';

  @override
  String get turnSharpRight => 'Scharf rechts abbiegen';

  @override
  String get turnKeepRight => 'Rechts halten';

  @override
  String turnIn(int metres, String turn) {
    return 'In $metres Metern $turn';
  }

  @override
  String get navVoiceOn => 'Ansagen einschalten';

  @override
  String get navVoiceOff => 'Ansagen ausschalten';

  @override
  String get journeysTitle => 'Etappentouren';

  @override
  String get journeysEmpty => 'Noch keine Etappentouren. Plane sie auf der Website.';

  @override
  String get journeysOffline => 'Offline – nur gespeicherte Etappentouren';

  @override
  String journeyStagesCount(int done, int total) {
    return '$done von $total Etappen';
  }

  @override
  String journeyStage(int n) {
    return 'Etappe $n';
  }

  @override
  String get journeyNoRoute => 'Noch keine Route';

  @override
  String get statusDone => 'Gewandert';

  @override
  String get statusSkipped => 'Ausgelassen';

  @override
  String gapWarning(String distance) {
    return '$distance Abstand zum Ende der vorherigen Etappe';
  }

  @override
  String gapTransfer(String how) {
    return 'Überbrückt mit $how';
  }

  @override
  String get transferPt => 'öffentlichem Verkehr';

  @override
  String get transferCablecar => 'Seilbahn';

  @override
  String get transferOther => 'anders';

  @override
  String stageAccommodation(String name) {
    return 'Unterkunft: $name';
  }

  @override
  String get stageBooked => 'gebucht';

  @override
  String get journeySaveAll => 'Alle Etappen offline speichern';

  @override
  String journeySaving(int n, int total) {
    return 'Etappe $n von $total wird gespeichert …';
  }

  @override
  String get journeySaved => 'Alle Etappen offline gespeichert';

  @override
  String navSwitchQuestion(String title) {
    return 'Du zeichnest gerade «$title» auf. Diese Wanderung beenden und hier eine neue beginnen? Die bisherige Aufzeichnung bleibt gespeichert.';
  }

  @override
  String get navSwitch => 'Beenden und hier beginnen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get stageMarkDone => 'Als gewandert markieren';

  @override
  String get stageMarkPlanned => 'Wieder als geplant markieren';

  @override
  String get navMarkStageDone => 'Etappe als gewandert markieren';

  @override
  String get stageConflict => 'Jemand hat die Etappe inzwischen geändert. Hier ist der neue Stand.';

  @override
  String get stageMarkedDone => 'Etappe als gewandert markiert';

  @override
  String get areasTitle => 'Schutzgebiete auf dem Weg';

  @override
  String get areasWildlifeRest => 'Wildruhezone';

  @override
  String get areasHuntingReserve => 'Eidg. Jagdbanngebiet';

  @override
  String get areasBinding => 'verbindlich';

  @override
  String get areasRecommended => 'empfohlen';

  @override
  String areasPeriod(String from, String to) {
    return '$from bis $to';
  }

  @override
  String areasStages(String list) {
    return 'Etappe $list';
  }

  @override
  String liveSharedUntil(String time) {
    return 'Standort geteilt · Ende geplant um $time';
  }

  @override
  String get liveLater => 'Später';

  @override
  String get liveLaterFailed => 'Ohne Verbindung geht das nicht. Versuche es gleich noch einmal.';

  @override
  String get liveShareTitle => 'Standort teilen';

  @override
  String get liveShareIntro =>
      'Die gewählten Kontakte bekommen einen Link mit deinem Standort. Ist die Wanderung 30 Minuten nach dem geplanten Ende nicht beendet, bekommen sie eine E-Mail mit dem letzten Standort.';

  @override
  String get liveShareEnd => 'Geplantes Ende';

  @override
  String get liveShareStart => 'Teilen und losgehen';

  @override
  String get liveShareSkip => 'Ohne Teilen';

  @override
  String get liveShareFailed => 'Das Teilen hat nicht geklappt; die Wanderung wird trotzdem aufgezeichnet.';

  @override
  String get liveNoContacts => 'Kontakte zum Teilen legst du auf der Website unter «Konto» an.';

  @override
  String get navRecord => 'Aufzeichnen';

  @override
  String get navProfile => 'Profil';

  @override
  String recordHint(String start) {
    return 'Wähle eine Route und tippe auf «$start», um die Wanderung aufzuzeichnen.';
  }

  @override
  String get mapLayers => 'Karten';

  @override
  String get mapHuts => 'Hütten';

  @override
  String get mapLodging => 'Hotels und Campingplätze';

  @override
  String get placeHut => 'Hütte';

  @override
  String get placeHotel => 'Unterkunft';

  @override
  String get placeCampsite => 'Camping';

  @override
  String get placeWildernessHut => 'Unbewartete Hütte';

  @override
  String get placePtStop => 'ÖV-Haltestelle';

  @override
  String get placeAddress => 'Adresse';

  @override
  String get placeWebsite => 'Website';

  @override
  String get placeSearch => 'Ort suchen …';

  @override
  String get placeNothingFound => 'Nichts gefunden.';

  @override
  String get plannerTitle => 'Route planen';

  @override
  String get plannerHint => 'Suche Start und Ziel oder tippe auf die Karte.';

  @override
  String get plannerProfileHike => 'Wandern (bis T3)';

  @override
  String get plannerProfileAlpine => 'Alpinwandern (bis T6)';

  @override
  String get plannerPointMap => 'Punkt auf der Karte';

  @override
  String get plannerUp => 'Nach oben';

  @override
  String get plannerDown => 'Nach unten';

  @override
  String get plannerRemove => 'Entfernen';

  @override
  String get plannerSearchStart => 'Start suchen …';

  @override
  String get plannerSearchEnd => 'Ziel suchen …';

  @override
  String get plannerSearchMore => 'Weiteres Ziel suchen …';

  @override
  String get plannerLegNoPath => 'Kein Weg in der Nähe. Entferne den Punkt oder setze einen anderen.';

  @override
  String get plannerLegFailed => 'Dieser Abschnitt konnte nicht berechnet werden.';

  @override
  String get plannerRetry => 'Nochmals versuchen';

  @override
  String get plannerAddPlace => 'Als Routenpunkt hinzufügen';

  @override
  String get plannerSave => 'Route speichern';

  @override
  String get plannerRouteTitle => 'Titel';

  @override
  String get plannerSaveConfirm => 'Speichern';

  @override
  String get plannerSaveFailed => 'Speichern fehlgeschlagen.';

  @override
  String get discoverAction => 'Entdecken';

  @override
  String get discoverTitle => 'Touren entdecken';

  @override
  String get discoverKindAll => 'Routen und Etappentouren';

  @override
  String get discoverKindRoute => 'Nur Routen';

  @override
  String get discoverKindJourney => 'Nur Etappentouren';

  @override
  String get discoverSacAny => 'Jede Schwierigkeit';

  @override
  String discoverSacMax(String grade) {
    return 'bis $grade';
  }

  @override
  String get discoverDurationAny => 'Jede Wanderzeit';

  @override
  String get discoverDurationShort => 'bis 2 h';

  @override
  String get discoverDurationMedium => '2–4 h';

  @override
  String get discoverDurationLong => '4–6 h';

  @override
  String get discoverDurationXlong => 'über 6 h';

  @override
  String get discoverDurationHint => 'Bei Etappentouren zählt die längste Etappe.';

  @override
  String get discoverRoute => 'Route';

  @override
  String get discoverJourney => 'Etappentour';

  @override
  String discoverBy(String user) {
    return 'von $user';
  }

  @override
  String discoverStages(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n Etappen', one: '1 Etappe');
    return '$_temp0';
  }

  @override
  String discoverLongest(String time) {
    return 'längste $time';
  }

  @override
  String get discoverEmpty =>
      'Hier gibt es noch keine öffentlichen Touren. Verschiebe die Karte oder lockere die Filter.';

  @override
  String get discoverMore => 'Es gibt weitere Touren – zoome hinein oder filtere genauer.';

  @override
  String get discoverFailed => 'Die Suche hat nicht geklappt. Versuche es gleich noch einmal.';

  @override
  String get discoverOffline => 'Du bist offline. Zum Entdecken braucht es eine Verbindung.';

  @override
  String get discoverRetry => 'Nochmals versuchen';

  @override
  String get jplanTitle => 'Etappentour planen';

  @override
  String get jplanIntro =>
      'Wähle Start und Ziel – Alvyo teilt den Weg in Tage, die bei einer Hütte, einem Hotel, einem Campingplatz oder einer Haltestelle für die Heimreise enden.';

  @override
  String get jplanMapHint => 'Tippe auf die Karte, um einen Punkt zu setzen, oder suche einen Ort.';

  @override
  String get jplanPointMap => 'Punkt auf der Karte';

  @override
  String get jplanPointRemove => 'Entfernen';

  @override
  String get jplanSearchStart => 'Start suchen …';

  @override
  String get jplanSearchEnd => 'Ziel suchen …';

  @override
  String get jplanSearchMore => 'Weiteres Ziel suchen …';

  @override
  String get jplanBy => 'Aufteilen nach';

  @override
  String get jplanByDays => 'Anzahl Tage';

  @override
  String get jplanByHours => 'Stunden pro Tag';

  @override
  String get jplanDays => 'Tage';

  @override
  String get jplanHoursMin => 'Mindestens Stunden pro Tag';

  @override
  String get jplanHoursMax => 'Höchstens Stunden pro Tag';

  @override
  String get jplanMax => 'Höchstens (h pro Tag, leer: etwas mehr)';

  @override
  String get jplanKinds => 'Übernachten am liebsten in';

  @override
  String get jplanKindHut => 'Hütten';

  @override
  String get jplanKindHotel => 'Hotels und Gasthäusern';

  @override
  String get jplanKindCampsite => 'Campingplätzen';

  @override
  String get jplanKindPtStop => 'Haltestelle (Heimreise)';

  @override
  String get jplanProfile => 'Profil';

  @override
  String get jplanProfileHike => 'Wandern (bis T3)';

  @override
  String get jplanProfileAlpine => 'Alpinwandern (bis T6)';

  @override
  String get jplanSubmit => 'Etappen vorschlagen';

  @override
  String get jplanSuggest => 'Mehrere Wege vorschlagen';

  @override
  String get jplanRunning => 'Wird geplant …';

  @override
  String jplanDay(int n) {
    return 'Tag $n';
  }

  @override
  String get jplanToEnd => 'bis zum Ziel';

  @override
  String jplanEarlier(String place) {
    return 'Früher: $place';
  }

  @override
  String jplanLater(String place) {
    return 'Später: $place';
  }

  @override
  String get jplanOverMax => 'Länger als gewünscht: vorher gibt es keinen Ort zum Übernachten.';

  @override
  String get jplanUnderMin =>
      'Kürzer als gewünscht: anders lassen sich die Tage mit den Orten zum Übernachten nicht einteilen.';

  @override
  String get jplanHutHint =>
      'Ob die Hütte offen ist und ob du reservieren musst, weiss OpenStreetMap selten – prüfe es vorher.';

  @override
  String get jplanWebsite => 'Website';

  @override
  String get jplanFailed => 'Die Planung hat nicht geklappt. Versuche es gleich noch einmal.';

  @override
  String get jplanNoPath => 'Zwischen diesen Punkten gibt es mit diesem Profil keinen Weg.';

  @override
  String jplanSummary(int days, String distance) {
    String _temp0 = intl.Intl.pluralLogic(days, locale: localeName, other: '$days Tage', one: '1 Tag');
    return '$_temp0 · $distance';
  }

  @override
  String get jplanWays => 'Wege';

  @override
  String jplanWay(int n) {
    return 'Weg $n';
  }

  @override
  String jplanWayDirect(int n) {
    return 'Weg $n: direkt';
  }

  @override
  String jplanWayVia(int n, String place) {
    return 'Weg $n: über $place';
  }

  @override
  String get jplanWaysHint =>
      'Wo zwei Wege am gleichen Ort übernachten, kannst du dort von einem auf den anderen wechseln.';

  @override
  String jplanSwitch(int n) {
    return 'Ab hier weiter auf Weg $n';
  }

  @override
  String get jplanTitleField => 'Titel';

  @override
  String get jplanCreate => 'Etappentour erstellen';

  @override
  String get delete => 'Löschen';

  @override
  String get routeDeleteConfirm => 'Route löschen? Das lässt sich nicht rückgängig machen.';

  @override
  String get journeyDeleteConfirm =>
      'Etappentour mit allen Etappen und Routen löschen? Das lässt sich nicht rückgängig machen.';

  @override
  String jplanTooLong(String hours, int days) {
    return 'Mit höchstens $hours h pro Tag geht das nicht: dafür braucht es mindestens $days Tage.';
  }

  @override
  String jplanTooLongNone(String hours) {
    return 'Mit höchstens $hours h pro Tag geht das nicht: unterwegs gibt es zu wenige Orte zum Übernachten.';
  }

  @override
  String jplanPlanIn(int days) {
    return 'In $days Tagen planen';
  }
}
