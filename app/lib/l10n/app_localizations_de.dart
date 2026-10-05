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
  String get watchReasonOutside => 'sie führt mehr als 15 km über die Grenze der Schweiz und Liechtensteins.';

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

  @override
  String get navFeed => 'Neuigkeiten';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get themeTitle => 'Darstellung';

  @override
  String get themeSystem => 'Automatisch';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get languageTitle => 'Sprache';

  @override
  String get profileMine => 'Mein Profil';

  @override
  String get accountNotifications => 'Benachrichtigungen per E-Mail';

  @override
  String get accountNotifyComments => 'Wenn jemand meine Routen und Etappentouren kommentiert';

  @override
  String get accountNotifyFollows => 'Wenn mir jemand folgt';

  @override
  String get accountPace => 'Dein Tempo';

  @override
  String get accountPaceHint =>
      'Wanderzeiten in Prozent der Zeiten auf den gelben Wegweisern: unter 100 % bist du schneller, darüber langsamer.';

  @override
  String get accountPaceSignposts => '100 % – wie die Wegweiser';

  @override
  String get contactsTitle => 'Kontakte für geteilte Wanderungen';

  @override
  String get contactsIntro =>
      'Starte in der App eine Wanderung, kannst du ausgewählten Kontakten deinen Standort zeigen. Ist die Wanderung 30 Minuten nach dem geplanten Ende nicht beendet, bekommen sie eine E-Mail mit dem letzten Standort.';

  @override
  String get contactsName => 'Name';

  @override
  String get contactsEmail => 'E-Mail';

  @override
  String get contactsAdd => 'Hinzufügen';

  @override
  String get contactsRemove => 'Entfernen';

  @override
  String get contactsDuplicate => 'Diese Adresse ist schon ein Kontakt.';

  @override
  String get contactsFull => 'Höchstens 10 Kontakte.';

  @override
  String get blockedTitle => 'Blockierte Personen';

  @override
  String get blockedEmpty => 'Du hast niemanden blockiert.';

  @override
  String get accountDeleteTitle => 'Konto löschen';

  @override
  String get accountDeleteText =>
      'Löscht dein Konto und alle deine Routen endgültig. Geteilte Links funktionieren danach nicht mehr.';

  @override
  String get accountDeleteSubmit => 'Konto endgültig löschen';

  @override
  String get accountDeleteWrong => 'Das Passwort ist falsch.';

  @override
  String get accountDeleteRecent =>
      'Dein Konto hat kein Passwort: Zum Bestätigen musst du dich in den letzten 15 Minuten angemeldet haben.';

  @override
  String get accountDeleteLoginAgain => 'Bitte melde dich neu an und versuche es dann gleich noch einmal.';

  @override
  String get loginForgot => 'Passwort vergessen?';

  @override
  String get loginSignup => 'Konto erstellen';

  @override
  String get myMapTitle => 'Karte meiner Touren';

  @override
  String get myMapEmpty => 'In diesem Ausschnitt passt nichts zu den Filtern.';

  @override
  String get feedIntro => 'Neue öffentliche Touren der Leute, denen du folgst.';

  @override
  String get feedEmpty => 'Noch nichts – folge Leuten, deren Touren dich interessieren. Du findest sie beim Entdecken.';

  @override
  String get feedMore => 'Ältere laden';

  @override
  String profileSince(String date) {
    return 'dabei seit $date';
  }

  @override
  String profileFollowers(int n) {
    return '$n Follower';
  }

  @override
  String profileFollowing(int n) {
    return 'folgt $n';
  }

  @override
  String get profileFollow => 'Folgen';

  @override
  String get profileUnfollow => 'Nicht mehr folgen';

  @override
  String get profileBlock => 'Blockieren';

  @override
  String get profileUnblock => 'Nicht mehr blockieren';

  @override
  String get profileBlockedNote =>
      'Blockiert: Diese Person kann deine Touren nicht kommentieren und dir nicht folgen, und du siehst ihre Kommentare nicht.';

  @override
  String get profileRoutes => 'Routen';

  @override
  String get profileJourneys => 'Etappentouren';

  @override
  String get reportAction => 'Melden';

  @override
  String get reportReason => 'Grund';

  @override
  String get reportReasonSpam => 'Spam oder Werbung';

  @override
  String get reportReasonOffensive => 'Beleidigend oder unangemessen';

  @override
  String get reportReasonDangerous => 'Gefährlich oder falsch';

  @override
  String get reportReasonOther => 'Anderes';

  @override
  String get reportNote => 'Was ist los? (freiwillig)';

  @override
  String get reportThanks => 'Danke, wir schauen es uns an.';

  @override
  String get editAction => 'Bearbeiten';

  @override
  String get save => 'Speichern';

  @override
  String get saveConflict =>
      'Jemand hat das inzwischen geändert. Hier ist der neue Stand – deine Änderung ist nicht gespeichert.';

  @override
  String get fieldTitle => 'Titel';

  @override
  String get fieldDescription => 'Beschreibung';

  @override
  String get fieldVisibility => 'Sichtbarkeit';

  @override
  String get visibilityPrivate => 'Privat';

  @override
  String get visibilityUnlisted => 'Mit Link teilen';

  @override
  String get visibilityPublic => 'Öffentlich';

  @override
  String get visibilityNeedsVerify => 'Bestätige deine E-Mail-Adresse, um Routen zu veröffentlichen.';

  @override
  String get tagsLabel => 'Tags';

  @override
  String get tagsHint => 'Durch Kommas getrennt';

  @override
  String ownerBy(String user) {
    return 'von $user';
  }

  @override
  String get shareAction => 'Teilen';

  @override
  String get shareLink => 'Link zum Teilen';

  @override
  String get shareSend => 'Link senden …';

  @override
  String get shareCopied => 'Kopiert';

  @override
  String get shareLinkHint => 'Wähle «Mit Link teilen» oder «Öffentlich», um einen Link zu senden.';

  @override
  String get shareRotate => 'Neuen Link erzeugen';

  @override
  String get shareRotateHint => 'Der bisherige Link funktioniert danach nicht mehr.';

  @override
  String get sharePeople => 'Mit Personen teilen';

  @override
  String get sharePending => 'eingeladen';

  @override
  String get shareRemove => 'Zugriff entfernen';

  @override
  String get shareWho => 'Benutzername oder E-Mail-Adresse';

  @override
  String get shareInvite => 'Einladen';

  @override
  String get shareHint =>
      'Eingeladene erhalten eine E-Mail. Wer noch kein Konto hat, registriert sich mit dieser Adresse.';

  @override
  String get shareNeedsVerify => 'Bestätige deine E-Mail-Adresse, um mit anderen zu teilen.';

  @override
  String get shareRate => 'Zu viele Einladungen – versuche es später wieder.';

  @override
  String get shareNoUser => 'Diesen Benutzernamen gibt es nicht.';

  @override
  String get shareSelf => 'Du kannst dich nicht selbst einladen.';

  @override
  String get shareTooMany => 'Es haben bereits zu viele Personen Zugriff.';

  @override
  String get shareBadEmail => 'Ungültige E-Mail-Adresse.';

  @override
  String get roleViewer => 'Kann ansehen';

  @override
  String get roleEditor => 'Kann mitplanen';

  @override
  String get sharedTitle => 'Mit mir geteilt';

  @override
  String get gpxRoute => 'GPX teilen …';

  @override
  String get gpxJourney => 'Alle Etappen als GPX (ZIP) teilen …';

  @override
  String get photosTitle => 'Fotos';

  @override
  String get photosAdd => 'Fotos hinzufügen';

  @override
  String get photosCamera => 'Foto aufnehmen';

  @override
  String get photosLibrary => 'Aus der Mediathek';

  @override
  String photosUploading(int done, int total) {
    return '$done von $total hochgeladen …';
  }

  @override
  String get photosHint =>
      'JPEG, PNG, WebP oder HEIC bis 20 MB. Wir entfernen alle Metadaten; Fotos, die entlang der Route aufgenommen wurden, erscheinen auf der Karte.';

  @override
  String get photosProblemFormat => 'kein JPEG-, PNG-, WebP- oder HEIC-Bild';

  @override
  String get photosProblemSize => 'zu gross (höchstens 20 MB)';

  @override
  String get photosProblemLimit => 'zu viele Fotos (höchstens 100 pro Tour und 1000 pro Person)';

  @override
  String get photosProblemRate => 'zu viele Uploads – versuche es gleich noch einmal';

  @override
  String get photosProblemOther => 'Hochladen fehlgeschlagen';

  @override
  String get photosCaption => 'Beschreibung';

  @override
  String photosBy(String user) {
    return 'von $user';
  }

  @override
  String get photosDelete => 'Löschen';

  @override
  String get photosDeleteConfirm => 'Wirklich löschen?';

  @override
  String get communityLike => 'Merken';

  @override
  String communityLikes(int n) {
    return '$n Mal gemerkt';
  }

  @override
  String communityComments(int n) {
    return '$n Kommentare';
  }

  @override
  String get communityCommentsAllowed => 'Kommentare erlauben';

  @override
  String get communityCommentsOff => 'Kommentare sind ausgeschaltet.';

  @override
  String get communityCommentPlaceholder => 'Kommentar schreiben …';

  @override
  String get communityCommentSend => 'Kommentieren';

  @override
  String get communityReply => 'Antworten';

  @override
  String get communityReplyPlaceholder => 'Deine Antwort …';

  @override
  String get communityEdited => 'bearbeitet';

  @override
  String get communityRate => 'Das ging zu schnell – versuche es gleich noch einmal.';

  @override
  String get communityVerifyToComment => 'Bestätige deine E-Mail-Adresse, um zu kommentieren.';

  @override
  String get stageEdit => 'Etappe bearbeiten';

  @override
  String get stageDate => 'Datum';

  @override
  String get stageDateNone => 'Kein Datum';

  @override
  String get stageStatus => 'Status';

  @override
  String get statusPlanned => 'Geplant';

  @override
  String get stageAccommodationLabel => 'Unterkunft';

  @override
  String get stageAccommodationPlaceholder => 'z. B. Gasthaus Alpenhof';

  @override
  String get stageBookedLabel => 'Gebucht';

  @override
  String get stageNotes => 'Notizen';

  @override
  String get stageTransfer => 'Überbrückt mit';

  @override
  String get transferNone => '–';

  @override
  String get sbbToStart => 'SBB-Fahrplan: Anreise';

  @override
  String get sbbFromEnd => 'SBB-Fahrplan: Rückreise';

  @override
  String get sbbTransfer => 'SBB-Fahrplan';

  @override
  String get connectionsShow => 'Verbindungen anzeigen';

  @override
  String get connectionsDepart => 'Ab';

  @override
  String get connectionsArrive => 'An';

  @override
  String get connectionsSearch => 'Suchen';

  @override
  String get connectionsNone => 'Keine Verbindung gefunden.';

  @override
  String get connectionsUnavailable => 'Fahrplanabfrage gerade nicht möglich – nutze den SBB-Fahrplan.';

  @override
  String connectionsTransfers(int n) {
    return '$n Umst.';
  }

  @override
  String connectionsWalk(int min) {
    return '$min min zu Fuss';
  }

  @override
  String connectionsPlatform(String p) {
    return 'Gl./Kante $p';
  }

  @override
  String get connectionsSource => 'Fahrplandaten: opentransportdata.swiss';

  @override
  String get collectionsTitle => 'Sammlungen';

  @override
  String get collectionsIntro =>
      'Routen und Etappentouren zusammenstellen – als Wunschliste, Ideensammlung oder zum Teilen. Eine Sammlung gibt keinen Zugriff: Jede Person sieht nur, was sie ohnehin öffnen darf.';

  @override
  String get collectionsEmpty => 'Noch keine Sammlungen.';

  @override
  String get collectionNew => 'Neue Sammlung';

  @override
  String collectionItemsCount(int n) {
    return '$n Einträge';
  }

  @override
  String get collectionEmpty =>
      'Noch leer. Füge Routen und Etappentouren über ihr Menü hinzu: «Zur Sammlung hinzufügen …».';

  @override
  String get collectionAddTo => 'Zur Sammlung hinzufügen …';

  @override
  String collectionAdded(String title) {
    return 'Hinzugefügt zu «$title»';
  }

  @override
  String collectionAlready(String title) {
    return 'Schon in «$title»';
  }

  @override
  String get collectionRemoveItem => 'Entfernen';

  @override
  String get collectionDelete => 'Sammlung löschen';

  @override
  String get collectionDeleteConfirm => 'Sammlung löschen? Routen und Etappentouren bleiben.';

  @override
  String collectionStages(int n) {
    return '$n Etappen';
  }

  @override
  String get myMapKindHike => 'Gewanderte';

  @override
  String get connectionsFromHere => 'Verbindungen von hier zum Start';

  @override
  String get connectionsNoPosition =>
      'Dein Standort ist nicht bekannt. Erlaube Alvyo den Standort in den iPhone-Einstellungen.';

  @override
  String get stageMore => 'Details und Anreise';

  @override
  String get travelTitle => 'An- und Heimreise';

  @override
  String get travelTo => 'Anreise';

  @override
  String get travelBack => 'Heimreise';

  @override
  String get travelFrom => 'Von';

  @override
  String get travelToHome => 'Nach';

  @override
  String get travelNone => '– keine –';

  @override
  String travelOn(String date) {
    return 'am $date';
  }

  @override
  String get travelNoDate => 'Die Etappe hat kein Datum: Verbindungen von heute.';

  @override
  String get travelNoHomes => 'Ein Zuhause, das du oft brauchst, fügst du in deinem Konto hinzu.';

  @override
  String get travelPrivate => 'Nur du siehst deine An- und Heimreise.';

  @override
  String get travelNoRoute => 'Sobald eine Etappe eine Route hat.';

  @override
  String get travelChoose => 'Von wo und wann';

  @override
  String get homesTitle => 'Zuhause';

  @override
  String get homesIntro =>
      'Von hier planst du die Anreise zu deinen Etappentouren und die Heimreise mit dem öffentlichen Verkehr. Höchstens 5; nur du siehst sie.';

  @override
  String get homesName => 'Name';

  @override
  String get homesNamePlaceholder => 'z. B. Zuhause, Büro';

  @override
  String get homesAddress => 'Adresse suchen …';

  @override
  String get homesAdd => 'Hinzufügen';

  @override
  String get homesRemove => 'Entfernen';

  @override
  String get homesFull => 'Höchstens 5 Zuhause.';

  @override
  String get travelStart => 'Start der Tour';

  @override
  String get travelEnd => 'Ende der Tour';

  @override
  String get recordTitle => 'Wanderung';

  @override
  String get recordStart => 'Aufzeichnung starten';

  @override
  String get recordRefused =>
      'Nicht gespeichert: Die Wanderung ist zu kurz oder führt mehr als 15 km über die Grenze der Schweiz und Liechtensteins.';

  @override
  String get barRoutes => 'Routen';

  @override
  String get barJourneys => 'Etappen';

  @override
  String get planAction => 'Planen';

  @override
  String get routePrivacyOwner => 'Andere sehen diese Wanderung ohne die ersten und letzten 500 m.';

  @override
  String get routePrivacyOthers => 'Start und Ende der Wanderung sind verborgen.';

  @override
  String get routePrivacyAll => 'Diese Wanderung ist zu kurz, um sie anderen zu zeigen: Start und Ende sind verborgen.';

  @override
  String plannerAlpineShorter(String alpine, String hike) {
    return 'Mit «Alpinwandern» nur $alpine statt $hike.';
  }

  @override
  String plannerAlpineGrade(String grade) {
    return 'Der kürzere Weg führt über $grade.';
  }

  @override
  String get plannerAlpineUse => 'Diesen Abschnitt alpin planen';

  @override
  String get plannerAlpineUsed => 'Mit «Alpinwandern» geplant.';

  @override
  String get plannerAlpineUndo => 'Wieder als Wanderung';

  @override
  String get noticesTitle => 'Sperrungen und Schiessen';

  @override
  String get noticesClosure => 'Wanderweg gesperrt';

  @override
  String get noticesShooting => 'Schiessen der Armee';

  @override
  String get mapPois => 'Unterwegs';

  @override
  String get poiPeak => 'Gipfel';

  @override
  String get poiViewpoint => 'Aussichtspunkt';

  @override
  String get poiWaterfall => 'Wasserfall';

  @override
  String get poiWater => 'Trinkwasser';

  @override
  String get poiShelter => 'Unterstand';

  @override
  String get mapBase => 'Hintergrund';

  @override
  String get mapOverlays => 'Überlagerungen';

  @override
  String get mapBaseNational => 'Landeskarte';

  @override
  String get mapBaseGrey => 'Landeskarte grau';

  @override
  String get mapBaseAerial => 'Luftbild';

  @override
  String get mapOverlayTrails => 'Wanderwege';

  @override
  String get mapOverlayWanderland => 'SchweizMobil-Wanderrouten';

  @override
  String get mapOverlaySlope => 'Hangneigung über 30°';

  @override
  String get mapOverlayRestAreas => 'Wildruhezonen';

  @override
  String get mapOverlayHuntingReserves => 'Eidg. Jagdbanngebiete';

  @override
  String get mapOverlayRelief => 'Relief';

  @override
  String get poiFirepit => 'Feuerstelle';

  @override
  String get poiPicnic => 'Picknickplatz';

  @override
  String get poiRestaurant => 'Restaurant, Café';

  @override
  String get poiToilets => 'Toilette';

  @override
  String get poiCablecar => 'Seilbahnstation';

  @override
  String get poisTitle => 'Unterwegs';

  @override
  String get routeTabOverview => 'Übersicht';

  @override
  String get routeTabTravel => 'Anreise';

  @override
  String get journeyTabStages => 'Etappen';

  @override
  String get statTime => 'Wanderzeit';

  @override
  String get statDistance => 'Distanz';

  @override
  String get statHeights => 'Höhenmeter';

  @override
  String get statSac => 'Schwierigkeit';

  @override
  String poisFilterAll(int count) {
    return 'Alle $count';
  }

  @override
  String get weatherTitle => 'Wetter';

  @override
  String get weatherStart => 'Start';

  @override
  String get weatherTop => 'Höchster Punkt';

  @override
  String get weatherEnd => 'Ziel';

  @override
  String get weatherToday => 'Heute';

  @override
  String get weatherTomorrow => 'Morgen';

  @override
  String get weatherDry => 'trocken';

  @override
  String weatherRain(String mm, String lo, String hi) {
    return '$mm mm Niederschlag ($lo–$hi mm)';
  }

  @override
  String weatherSource(String time) {
    return 'Prognose von MeteoSchweiz für den Ort in der Nähe mit der ähnlichsten Höhe, von $time.';
  }

  @override
  String weatherStage(int n, String date) {
    return 'Etappe $n, $date';
  }

  @override
  String get travelElsewhere => 'Anderer Ort …';

  @override
  String get travelPlaceSearch => 'Ort, Haltestelle oder Adresse';

  @override
  String get travelDay => 'Am';

  @override
  String get travelRouteStart => 'Start';

  @override
  String get travelRouteEnd => 'Ziel';

  @override
  String get areasNow => 'gilt jetzt';

  @override
  String get areasOnDate => 'gilt an einem geplanten Tag';

  @override
  String hintsOpen(int count) {
    return '$count anzeigen';
  }

  @override
  String get weatherOtherDay => 'Anderes Datum';

  @override
  String weatherClimate(String month, String min, String max, String days, String total, String mm) {
    return 'Üblich im $month: $min–$max °C, an $days von $total Tagen Regen, $mm mm im Monat';
  }

  @override
  String weatherClimateSource(String station, String rain) {
    return 'Noch keine Prognose für diesen Tag: Klimanormwerte 1991–2020 von MeteoSchweiz (Temperatur: $station, auf die Höhe umgerechnet; Niederschlag: $rain). Die Prognose gibt es für die nächsten 9 Tage.';
  }

  @override
  String get journeyMap => 'Karte der Etappentour';

  @override
  String get journeyAddStage => 'Etappe hinzufügen';

  @override
  String get routeEditLine => 'Auf der Karte ändern';

  @override
  String get bugOpen => 'Fehler melden';

  @override
  String get bugWhat => 'Was ist passiert? Was hast du erwartet?';

  @override
  String get bugWithScreenshot => 'Bildschirmfoto mitsenden';

  @override
  String get bugScreenshotAlt => 'Bildschirmfoto dieser Seite';

  @override
  String bugPrivacy(String place) {
    return 'Mit dem Bericht gehen die Adresse ($place), die Version, dein Benutzername und das Bildschirmfoto an die Entwickler (GitHub). Das Bildschirmfoto bleibt bei Alvyo und wird mit deinem Konto gelöscht.';
  }

  @override
  String get bugSend => 'Senden';

  @override
  String get bugSent => 'Danke! Der Fehler ist gemeldet.';

  @override
  String get bugFailed => 'Das hat nicht geklappt. Versuch es später nochmals.';

  @override
  String get bugBusy => 'Du hast heute schon einige Fehler gemeldet. Versuch es später nochmals.';

  @override
  String get close => 'Schliessen';

  @override
  String get peopleTitle => 'Wer kommt mit';

  @override
  String get peopleNone =>
      'Noch niemand. Wer mitkommt, sieht die Etappentour und die Etappen, auf denen er oder sie dabei ist.';

  @override
  String get peopleInvited => 'Eingeladen';

  @override
  String get peopleRemove => 'Kommt nicht mit';

  @override
  String get peopleWho => 'Benutzername oder E-Mail-Adresse';

  @override
  String get peopleAdd => 'Hinzufügen';

  @override
  String get peopleHint =>
      'Wer noch keinen Zugang hat, wird eingeladen und kann die Etappentour ansehen. Die Zahlen sind die Etappen: antippen, wer wo dabei ist.';

  @override
  String get peopleUnknown => 'Diese Person gibt es nicht, oder du bist es selbst.';

  @override
  String get peopleVerify => 'Bestätige zuerst deine E-Mail-Adresse.';

  @override
  String get peopleFailed => 'Das hat nicht geklappt. Versuch es nochmals.';

  @override
  String peopleOnStage(String names) {
    return 'Mit $names';
  }

  @override
  String peopleStages(String name) {
    return 'Etappen von $name';
  }

  @override
  String get remindersTitle => 'Erinnerungen';

  @override
  String get remindersOn => 'Erinnerungen per E-Mail vor dem Start';

  @override
  String get remindersHint => 'Für dich und alle, die mitkommen; in der App auch auf dem Telefon.';

  @override
  String get reminderBook => 'In drei Wochen geht es los: Sind alle Übernachtungen gebucht?';

  @override
  String get reminderWeather => 'Übermorgen geht es los: Schau dir das Wetter an.';

  @override
  String get reminderStart => 'Morgen geht es los. Gute Wanderung!';

  @override
  String get friendsTitle => 'Freunde';

  @override
  String get friendsSearch => 'Personen suchen';

  @override
  String get friendsSearchHint => 'Benutzername oder Name; gefunden werden nur öffentliche Profile.';

  @override
  String get friendsNoneFound => 'Niemand gefunden.';

  @override
  String get friendsIncoming => 'Anfragen an dich';

  @override
  String get friendsOutgoing => 'Deine Anfragen';

  @override
  String get friendsList => 'Deine Freunde';

  @override
  String get friendsEmpty => 'Noch keine Freunde. Suche nach Personen oder schicke deinen Einladungslink.';

  @override
  String get friendAdd => 'Als Freund hinzufügen';

  @override
  String get friendRequested => 'Anfrage gesendet';

  @override
  String get friendWithdraw => 'Zurückziehen';

  @override
  String get friendAccept => 'Annehmen';

  @override
  String get friendDecline => 'Ablehnen';

  @override
  String get friendFriends => 'Befreundet';

  @override
  String get friendRemove => 'Freundschaft beenden';

  @override
  String get friendsLinkTitle => 'Dein Einladungslink';

  @override
  String get friendsLinkHint =>
      'Wer diesen Link öffnet, wird dein Freund – auch wenn dein Profil privat ist. Schick ihn nur Leuten, die du kennst.';

  @override
  String get friendsLinkShare => 'Link senden';

  @override
  String get friendsLinkRenew => 'Neuen Link erzeugen';

  @override
  String get profilePublic => 'Öffentliches Profil';

  @override
  String get profilePublicHint => 'Andere finden dich in der Suche. Ein privates Profil sehen nur deine Freunde.';

  @override
  String get doneMark => 'Als gewandert markieren';

  @override
  String get doneRemove => 'Nicht gewandert';

  @override
  String get doneByHike => 'aufgezeichnet';

  @override
  String get doneByStages => 'alle Etappen erledigt';

  @override
  String get doneFilterAll => 'Alle';

  @override
  String get doneFilterPlanned => 'Geplant';

  @override
  String get doneFilterDone => 'Gewandert';

  @override
  String get doneFilterNone => 'Nichts in dieser Auswahl.';

  @override
  String doneOn(String date) {
    return 'Gewandert am $date';
  }

  @override
  String get breakdownTitle => 'Wegbeschaffenheit';

  @override
  String get breakdownTrail => 'Wanderwegnetz';

  @override
  String get breakdownSurface => 'Belag';

  @override
  String get breakdownWay => 'Wegtyp';

  @override
  String get breakdownOther => 'Andere';

  @override
  String get breakdownDetails => 'Details in km';

  @override
  String get trailWanderweg => 'Wanderweg';

  @override
  String get trailBergwanderweg => 'Bergwanderweg';

  @override
  String get trailAlpinwanderweg => 'Alpinwanderweg';

  @override
  String get trailNone => 'Kein Wanderweg';

  @override
  String get surfacePaved => 'Asphalt, Pflaster';

  @override
  String get surfaceGravel => 'Kies, Schotter';

  @override
  String get surfaceNatural => 'Naturbelag';

  @override
  String get surfaceUnknown => 'Unbekannt';

  @override
  String get wayRoad => 'Strasse';

  @override
  String get wayTrack => 'Fahrweg';

  @override
  String get wayPath => 'Pfad';

  @override
  String get waySteps => 'Treppe';

  @override
  String get wayUnknown => 'Unbekannt';

  @override
  String get offTrailTitle => 'Kein offizieller Wanderweg';

  @override
  String offTrailAll(String distance) {
    return 'Die ganze Route ($distance) verläuft abseits markierter Wanderwege.';
  }

  @override
  String inviteTitle(String name) {
    return '$name lädt dich ein';
  }

  @override
  String get inviteText => 'Werdet Freunde auf Alvyo: ihr seht eure Profile, auch private.';

  @override
  String get inviteAccept => 'Freunde werden';

  @override
  String get inviteDone => 'Ihr seid jetzt Freunde.';

  @override
  String get inviteInvalid => 'Dieser Einladungslink gilt nicht mehr.';

  @override
  String get inviteSelf => 'Das ist dein eigener Link.';
}
