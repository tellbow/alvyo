import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('de'), Locale('en'), Locale('fr'), Locale('it')];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Alvyo'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get loginTitle;

  /// No description provided for @server.
  ///
  /// In de, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @login.
  ///
  /// In de, this message translates to:
  /// **'E-Mail oder Benutzername'**
  String get login;

  /// No description provided for @password.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get password;

  /// No description provided for @loginSubmit.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get loginSubmit;

  /// No description provided for @loginInvalid.
  ///
  /// In de, this message translates to:
  /// **'E-Mail/Benutzername oder Passwort ist falsch.'**
  String get loginInvalid;

  /// No description provided for @errorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen. Bitte versuche es nochmals.'**
  String get errorGeneric;

  /// No description provided for @errorServer.
  ///
  /// In de, this message translates to:
  /// **'Der Server ist nicht erreichbar.'**
  String get errorServer;

  /// No description provided for @routesTitle.
  ///
  /// In de, this message translates to:
  /// **'Meine Routen'**
  String get routesTitle;

  /// No description provided for @routesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Routen. Plane sie auf der Website.'**
  String get routesEmpty;

  /// No description provided for @logout.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get logout;

  /// No description provided for @offlineSave.
  ///
  /// In de, this message translates to:
  /// **'Offline speichern'**
  String get offlineSave;

  /// No description provided for @offlineSaved.
  ///
  /// In de, this message translates to:
  /// **'Offline gespeichert – entfernen'**
  String get offlineSaved;

  /// No description provided for @offlinePreparing.
  ///
  /// In de, this message translates to:
  /// **'Die Offline-Karte wird vorbereitet …'**
  String get offlinePreparing;

  /// No description provided for @offlineDownloading.
  ///
  /// In de, this message translates to:
  /// **'Die Offline-Karte wird geladen …'**
  String get offlineDownloading;

  /// No description provided for @offlineOutdated.
  ///
  /// In de, this message translates to:
  /// **'Route geändert – Offline-Karte aktualisieren'**
  String get offlineOutdated;

  /// No description provided for @offlineFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Offline-Karte konnte nicht gespeichert werden.'**
  String get offlineFailed;

  /// No description provided for @routesOffline.
  ///
  /// In de, this message translates to:
  /// **'Offline – nur gespeicherte Routen'**
  String get routesOffline;

  /// No description provided for @navStart.
  ///
  /// In de, this message translates to:
  /// **'Wanderung starten'**
  String get navStart;

  /// No description provided for @navResume.
  ///
  /// In de, this message translates to:
  /// **'Wanderung fortsetzen'**
  String get navResume;

  /// No description provided for @navDone.
  ///
  /// In de, this message translates to:
  /// **'Gegangen'**
  String get navDone;

  /// No description provided for @navRemaining.
  ///
  /// In de, this message translates to:
  /// **'Noch'**
  String get navRemaining;

  /// No description provided for @navElapsed.
  ///
  /// In de, this message translates to:
  /// **'Unterwegs'**
  String get navElapsed;

  /// No description provided for @navOffRoute.
  ///
  /// In de, this message translates to:
  /// **'{metres} m neben der Route'**
  String navOffRoute(int metres);

  /// No description provided for @navOffRouteTitle.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr auf der Route'**
  String get navOffRouteTitle;

  /// No description provided for @navArrived.
  ///
  /// In de, this message translates to:
  /// **'Ziel erreicht'**
  String get navArrived;

  /// No description provided for @navWaiting.
  ///
  /// In de, this message translates to:
  /// **'Warte auf GPS …'**
  String get navWaiting;

  /// No description provided for @navFinish.
  ///
  /// In de, this message translates to:
  /// **'Beenden'**
  String get navFinish;

  /// No description provided for @navFinishQuestion.
  ///
  /// In de, this message translates to:
  /// **'Wanderung beenden und die Aufzeichnung speichern?'**
  String get navFinishQuestion;

  /// No description provided for @navContinue.
  ///
  /// In de, this message translates to:
  /// **'Weitergehen'**
  String get navContinue;

  /// No description provided for @navNoPermission.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht die App deinen Standort. Erlaube ihn in den Einstellungen.'**
  String get navNoPermission;

  /// No description provided for @navSaved.
  ///
  /// In de, this message translates to:
  /// **'Aufgezeichnet: {distance} in {duration}. Wird hochgeladen, sobald du online bist.'**
  String navSaved(String distance, String duration);

  /// No description provided for @navFollow.
  ///
  /// In de, this message translates to:
  /// **'Meiner Position folgen'**
  String get navFollow;

  /// No description provided for @navUploaded.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert unter «Meine Routen»: {distance} in {duration}'**
  String navUploaded(String distance, String duration);

  /// No description provided for @routesHiked.
  ///
  /// In de, this message translates to:
  /// **'Gewandert am {date}'**
  String routesHiked(String date);

  /// No description provided for @watchTitle.
  ///
  /// In de, this message translates to:
  /// **'Von der Apple Watch'**
  String get watchTitle;

  /// No description provided for @watchHike.
  ///
  /// In de, this message translates to:
  /// **'Wanderung'**
  String get watchHike;

  /// No description provided for @watchWalk.
  ///
  /// In de, this message translates to:
  /// **'Spaziergang'**
  String get watchWalk;

  /// No description provided for @watchImport.
  ///
  /// In de, this message translates to:
  /// **'Importieren'**
  String get watchImport;

  /// No description provided for @watchImported.
  ///
  /// In de, this message translates to:
  /// **'Importiert – in «Meine Routen»'**
  String get watchImported;

  /// No description provided for @watchNoTrack.
  ///
  /// In de, this message translates to:
  /// **'Dieses Training hat keine GPS-Strecke.'**
  String get watchNoTrack;

  /// No description provided for @watchEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine Wanderungen der letzten 60 Tage in Apple Health. Zeichne sie auf der Apple Watch mit der App «Training» auf («Wandern» oder «Gehen» im Freien). Falls du den Zugriff nicht erlaubt hast: Einstellungen → Apps → Health → Datenzugriff & Geräte → Alvyo.'**
  String get watchEmpty;

  /// No description provided for @watchUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Apple Health ist auf diesem Gerät nicht verfügbar.'**
  String get watchUnavailable;

  /// No description provided for @watchOutside.
  ///
  /// In de, this message translates to:
  /// **'Nicht importiert: {reason}'**
  String watchOutside(String reason);

  /// No description provided for @watchReasonOutside.
  ///
  /// In de, this message translates to:
  /// **'sie führt mehr als 15 km über die Grenze der Schweiz und Liechtensteins.'**
  String get watchReasonOutside;

  /// No description provided for @watchReasonShort.
  ///
  /// In de, this message translates to:
  /// **'sie ist zu kurz.'**
  String get watchReasonShort;

  /// No description provided for @turnSharpLeft.
  ///
  /// In de, this message translates to:
  /// **'Scharf links abbiegen'**
  String get turnSharpLeft;

  /// No description provided for @turnLeft.
  ///
  /// In de, this message translates to:
  /// **'Links abbiegen'**
  String get turnLeft;

  /// No description provided for @turnSlightLeft.
  ///
  /// In de, this message translates to:
  /// **'Leicht links abbiegen'**
  String get turnSlightLeft;

  /// No description provided for @turnKeepLeft.
  ///
  /// In de, this message translates to:
  /// **'Links halten'**
  String get turnKeepLeft;

  /// No description provided for @turnUTurn.
  ///
  /// In de, this message translates to:
  /// **'Umkehren'**
  String get turnUTurn;

  /// No description provided for @turnSlightRight.
  ///
  /// In de, this message translates to:
  /// **'Leicht rechts abbiegen'**
  String get turnSlightRight;

  /// No description provided for @turnRight.
  ///
  /// In de, this message translates to:
  /// **'Rechts abbiegen'**
  String get turnRight;

  /// No description provided for @turnSharpRight.
  ///
  /// In de, this message translates to:
  /// **'Scharf rechts abbiegen'**
  String get turnSharpRight;

  /// No description provided for @turnKeepRight.
  ///
  /// In de, this message translates to:
  /// **'Rechts halten'**
  String get turnKeepRight;

  /// Said about 100 m before a turn; {turn} is one of the turn texts, starting lower case.
  ///
  /// In de, this message translates to:
  /// **'In {metres} Metern {turn}'**
  String turnIn(int metres, String turn);

  /// No description provided for @navVoiceOn.
  ///
  /// In de, this message translates to:
  /// **'Ansagen einschalten'**
  String get navVoiceOn;

  /// No description provided for @navVoiceOff.
  ///
  /// In de, this message translates to:
  /// **'Ansagen ausschalten'**
  String get navVoiceOff;

  /// No description provided for @journeysTitle.
  ///
  /// In de, this message translates to:
  /// **'Etappentouren'**
  String get journeysTitle;

  /// No description provided for @journeysEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Etappentouren. Plane sie auf der Website.'**
  String get journeysEmpty;

  /// No description provided for @journeysOffline.
  ///
  /// In de, this message translates to:
  /// **'Offline – nur gespeicherte Etappentouren'**
  String get journeysOffline;

  /// No description provided for @journeyStagesCount.
  ///
  /// In de, this message translates to:
  /// **'{done} von {total} Etappen'**
  String journeyStagesCount(int done, int total);

  /// No description provided for @journeyStage.
  ///
  /// In de, this message translates to:
  /// **'Etappe {n}'**
  String journeyStage(int n);

  /// No description provided for @journeyNoRoute.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Route'**
  String get journeyNoRoute;

  /// No description provided for @statusDone.
  ///
  /// In de, this message translates to:
  /// **'Gewandert'**
  String get statusDone;

  /// No description provided for @statusSkipped.
  ///
  /// In de, this message translates to:
  /// **'Ausgelassen'**
  String get statusSkipped;

  /// No description provided for @gapWarning.
  ///
  /// In de, this message translates to:
  /// **'{distance} Abstand zum Ende der vorherigen Etappe'**
  String gapWarning(String distance);

  /// {how} is transferPt, transferCablecar or transferOther.
  ///
  /// In de, this message translates to:
  /// **'Überbrückt mit {how}'**
  String gapTransfer(String how);

  /// No description provided for @transferPt.
  ///
  /// In de, this message translates to:
  /// **'öffentlichem Verkehr'**
  String get transferPt;

  /// No description provided for @transferCablecar.
  ///
  /// In de, this message translates to:
  /// **'Seilbahn'**
  String get transferCablecar;

  /// No description provided for @transferOther.
  ///
  /// In de, this message translates to:
  /// **'anders'**
  String get transferOther;

  /// No description provided for @stageAccommodation.
  ///
  /// In de, this message translates to:
  /// **'Unterkunft: {name}'**
  String stageAccommodation(String name);

  /// No description provided for @stageBooked.
  ///
  /// In de, this message translates to:
  /// **'gebucht'**
  String get stageBooked;

  /// No description provided for @journeySaveAll.
  ///
  /// In de, this message translates to:
  /// **'Alle Etappen offline speichern'**
  String get journeySaveAll;

  /// No description provided for @journeySaving.
  ///
  /// In de, this message translates to:
  /// **'Etappe {n} von {total} wird gespeichert …'**
  String journeySaving(int n, int total);

  /// No description provided for @journeySaved.
  ///
  /// In de, this message translates to:
  /// **'Alle Etappen offline gespeichert'**
  String get journeySaved;

  /// No description provided for @navSwitchQuestion.
  ///
  /// In de, this message translates to:
  /// **'Du zeichnest gerade «{title}» auf. Diese Wanderung beenden und hier eine neue beginnen? Die bisherige Aufzeichnung bleibt gespeichert.'**
  String navSwitchQuestion(String title);

  /// No description provided for @navSwitch.
  ///
  /// In de, this message translates to:
  /// **'Beenden und hier beginnen'**
  String get navSwitch;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @stageMarkDone.
  ///
  /// In de, this message translates to:
  /// **'Als gewandert markieren'**
  String get stageMarkDone;

  /// No description provided for @stageMarkPlanned.
  ///
  /// In de, this message translates to:
  /// **'Wieder als geplant markieren'**
  String get stageMarkPlanned;

  /// No description provided for @navMarkStageDone.
  ///
  /// In de, this message translates to:
  /// **'Etappe als gewandert markieren'**
  String get navMarkStageDone;

  /// No description provided for @stageConflict.
  ///
  /// In de, this message translates to:
  /// **'Jemand hat die Etappe inzwischen geändert. Hier ist der neue Stand.'**
  String get stageConflict;

  /// No description provided for @stageMarkedDone.
  ///
  /// In de, this message translates to:
  /// **'Etappe als gewandert markiert'**
  String get stageMarkedDone;

  /// No description provided for @areasTitle.
  ///
  /// In de, this message translates to:
  /// **'Schutzgebiete auf dem Weg'**
  String get areasTitle;

  /// No description provided for @areasWildlifeRest.
  ///
  /// In de, this message translates to:
  /// **'Wildruhezone'**
  String get areasWildlifeRest;

  /// No description provided for @areasHuntingReserve.
  ///
  /// In de, this message translates to:
  /// **'Eidg. Jagdbanngebiet'**
  String get areasHuntingReserve;

  /// No description provided for @areasBinding.
  ///
  /// In de, this message translates to:
  /// **'verbindlich'**
  String get areasBinding;

  /// No description provided for @areasRecommended.
  ///
  /// In de, this message translates to:
  /// **'empfohlen'**
  String get areasRecommended;

  /// No description provided for @areasPeriod.
  ///
  /// In de, this message translates to:
  /// **'{from} bis {to}'**
  String areasPeriod(String from, String to);

  /// No description provided for @areasStages.
  ///
  /// In de, this message translates to:
  /// **'Etappe {list}'**
  String areasStages(String list);

  /// No description provided for @liveSharedUntil.
  ///
  /// In de, this message translates to:
  /// **'Standort geteilt · Ende geplant um {time}'**
  String liveSharedUntil(String time);

  /// No description provided for @liveLater.
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get liveLater;

  /// No description provided for @liveLaterFailed.
  ///
  /// In de, this message translates to:
  /// **'Ohne Verbindung geht das nicht. Versuche es gleich noch einmal.'**
  String get liveLaterFailed;

  /// No description provided for @liveShareTitle.
  ///
  /// In de, this message translates to:
  /// **'Standort teilen'**
  String get liveShareTitle;

  /// No description provided for @liveShareIntro.
  ///
  /// In de, this message translates to:
  /// **'Die gewählten Kontakte bekommen einen Link mit deinem Standort. Ist die Wanderung 30 Minuten nach dem geplanten Ende nicht beendet, bekommen sie eine E-Mail mit dem letzten Standort.'**
  String get liveShareIntro;

  /// No description provided for @liveShareEnd.
  ///
  /// In de, this message translates to:
  /// **'Geplantes Ende'**
  String get liveShareEnd;

  /// No description provided for @liveShareStart.
  ///
  /// In de, this message translates to:
  /// **'Teilen und losgehen'**
  String get liveShareStart;

  /// No description provided for @liveShareSkip.
  ///
  /// In de, this message translates to:
  /// **'Ohne Teilen'**
  String get liveShareSkip;

  /// No description provided for @liveShareFailed.
  ///
  /// In de, this message translates to:
  /// **'Das Teilen hat nicht geklappt; die Wanderung wird trotzdem aufgezeichnet.'**
  String get liveShareFailed;

  /// No description provided for @liveNoContacts.
  ///
  /// In de, this message translates to:
  /// **'Kontakte zum Teilen legst du auf der Website unter «Konto» an.'**
  String get liveNoContacts;

  /// No description provided for @navRecord.
  ///
  /// In de, this message translates to:
  /// **'Aufzeichnen'**
  String get navRecord;

  /// No description provided for @navProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get navProfile;

  /// No description provided for @mapLayers.
  ///
  /// In de, this message translates to:
  /// **'Karten'**
  String get mapLayers;

  /// No description provided for @mapHuts.
  ///
  /// In de, this message translates to:
  /// **'Hütten'**
  String get mapHuts;

  /// No description provided for @mapLodging.
  ///
  /// In de, this message translates to:
  /// **'Hotels und Campingplätze'**
  String get mapLodging;

  /// No description provided for @placeHut.
  ///
  /// In de, this message translates to:
  /// **'Hütte'**
  String get placeHut;

  /// No description provided for @placeHotel.
  ///
  /// In de, this message translates to:
  /// **'Unterkunft'**
  String get placeHotel;

  /// No description provided for @placeCampsite.
  ///
  /// In de, this message translates to:
  /// **'Camping'**
  String get placeCampsite;

  /// No description provided for @placeWildernessHut.
  ///
  /// In de, this message translates to:
  /// **'Unbewartete Hütte'**
  String get placeWildernessHut;

  /// No description provided for @placePtStop.
  ///
  /// In de, this message translates to:
  /// **'ÖV-Haltestelle'**
  String get placePtStop;

  /// No description provided for @placeAddress.
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get placeAddress;

  /// No description provided for @placeWebsite.
  ///
  /// In de, this message translates to:
  /// **'Website'**
  String get placeWebsite;

  /// No description provided for @placeSearch.
  ///
  /// In de, this message translates to:
  /// **'Ort suchen …'**
  String get placeSearch;

  /// No description provided for @placeNothingFound.
  ///
  /// In de, this message translates to:
  /// **'Nichts gefunden.'**
  String get placeNothingFound;

  /// No description provided for @plannerTitle.
  ///
  /// In de, this message translates to:
  /// **'Route planen'**
  String get plannerTitle;

  /// No description provided for @plannerHint.
  ///
  /// In de, this message translates to:
  /// **'Suche Start und Ziel oder tippe auf die Karte.'**
  String get plannerHint;

  /// No description provided for @plannerProfileHike.
  ///
  /// In de, this message translates to:
  /// **'Wandern (bis T3)'**
  String get plannerProfileHike;

  /// No description provided for @plannerProfileAlpine.
  ///
  /// In de, this message translates to:
  /// **'Alpinwandern (bis T6)'**
  String get plannerProfileAlpine;

  /// No description provided for @plannerPointMap.
  ///
  /// In de, this message translates to:
  /// **'Punkt auf der Karte'**
  String get plannerPointMap;

  /// No description provided for @plannerUp.
  ///
  /// In de, this message translates to:
  /// **'Nach oben'**
  String get plannerUp;

  /// No description provided for @plannerDown.
  ///
  /// In de, this message translates to:
  /// **'Nach unten'**
  String get plannerDown;

  /// No description provided for @plannerRemove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get plannerRemove;

  /// No description provided for @plannerSearchStart.
  ///
  /// In de, this message translates to:
  /// **'Start suchen …'**
  String get plannerSearchStart;

  /// No description provided for @plannerSearchEnd.
  ///
  /// In de, this message translates to:
  /// **'Ziel suchen …'**
  String get plannerSearchEnd;

  /// No description provided for @plannerSearchMore.
  ///
  /// In de, this message translates to:
  /// **'Weiteres Ziel suchen …'**
  String get plannerSearchMore;

  /// No description provided for @plannerLegNoPath.
  ///
  /// In de, this message translates to:
  /// **'Kein Weg in der Nähe. Entferne den Punkt oder setze einen anderen.'**
  String get plannerLegNoPath;

  /// No description provided for @plannerLegFailed.
  ///
  /// In de, this message translates to:
  /// **'Dieser Abschnitt konnte nicht berechnet werden.'**
  String get plannerLegFailed;

  /// No description provided for @plannerRetry.
  ///
  /// In de, this message translates to:
  /// **'Nochmals versuchen'**
  String get plannerRetry;

  /// No description provided for @plannerAddPlace.
  ///
  /// In de, this message translates to:
  /// **'Als Routenpunkt hinzufügen'**
  String get plannerAddPlace;

  /// No description provided for @plannerSave.
  ///
  /// In de, this message translates to:
  /// **'Route speichern'**
  String get plannerSave;

  /// No description provided for @plannerRouteTitle.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get plannerRouteTitle;

  /// No description provided for @plannerSaveConfirm.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get plannerSaveConfirm;

  /// No description provided for @plannerSaveFailed.
  ///
  /// In de, this message translates to:
  /// **'Speichern fehlgeschlagen.'**
  String get plannerSaveFailed;

  /// No description provided for @discoverAction.
  ///
  /// In de, this message translates to:
  /// **'Entdecken'**
  String get discoverAction;

  /// No description provided for @discoverTitle.
  ///
  /// In de, this message translates to:
  /// **'Touren entdecken'**
  String get discoverTitle;

  /// No description provided for @discoverKindAll.
  ///
  /// In de, this message translates to:
  /// **'Routen und Etappentouren'**
  String get discoverKindAll;

  /// No description provided for @discoverKindRoute.
  ///
  /// In de, this message translates to:
  /// **'Nur Routen'**
  String get discoverKindRoute;

  /// No description provided for @discoverKindJourney.
  ///
  /// In de, this message translates to:
  /// **'Nur Etappentouren'**
  String get discoverKindJourney;

  /// No description provided for @discoverSacAny.
  ///
  /// In de, this message translates to:
  /// **'Jede Schwierigkeit'**
  String get discoverSacAny;

  /// {grade}: a SAC hiking grade, e.g. T3.
  ///
  /// In de, this message translates to:
  /// **'bis {grade}'**
  String discoverSacMax(String grade);

  /// No description provided for @discoverDurationAny.
  ///
  /// In de, this message translates to:
  /// **'Jede Wanderzeit'**
  String get discoverDurationAny;

  /// No description provided for @discoverDurationShort.
  ///
  /// In de, this message translates to:
  /// **'bis 2 h'**
  String get discoverDurationShort;

  /// No description provided for @discoverDurationMedium.
  ///
  /// In de, this message translates to:
  /// **'2–4 h'**
  String get discoverDurationMedium;

  /// No description provided for @discoverDurationLong.
  ///
  /// In de, this message translates to:
  /// **'4–6 h'**
  String get discoverDurationLong;

  /// No description provided for @discoverDurationXlong.
  ///
  /// In de, this message translates to:
  /// **'über 6 h'**
  String get discoverDurationXlong;

  /// No description provided for @discoverDurationHint.
  ///
  /// In de, this message translates to:
  /// **'Bei Etappentouren zählt die längste Etappe.'**
  String get discoverDurationHint;

  /// No description provided for @discoverRoute.
  ///
  /// In de, this message translates to:
  /// **'Route'**
  String get discoverRoute;

  /// No description provided for @discoverJourney.
  ///
  /// In de, this message translates to:
  /// **'Etappentour'**
  String get discoverJourney;

  /// The owner's username.
  ///
  /// In de, this message translates to:
  /// **'von {user}'**
  String discoverBy(String user);

  /// No description provided for @discoverStages.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Etappe} other{{n} Etappen}}'**
  String discoverStages(int n);

  /// {time}: the hiking time of the longest stage.
  ///
  /// In de, this message translates to:
  /// **'längste {time}'**
  String discoverLongest(String time);

  /// No description provided for @discoverEmpty.
  ///
  /// In de, this message translates to:
  /// **'Hier gibt es noch keine öffentlichen Touren. Verschiebe die Karte oder lockere die Filter.'**
  String get discoverEmpty;

  /// No description provided for @discoverMore.
  ///
  /// In de, this message translates to:
  /// **'Es gibt weitere Touren – zoome hinein oder filtere genauer.'**
  String get discoverMore;

  /// No description provided for @discoverFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Suche hat nicht geklappt. Versuche es gleich noch einmal.'**
  String get discoverFailed;

  /// No description provided for @discoverOffline.
  ///
  /// In de, this message translates to:
  /// **'Du bist offline. Zum Entdecken braucht es eine Verbindung.'**
  String get discoverOffline;

  /// No description provided for @discoverRetry.
  ///
  /// In de, this message translates to:
  /// **'Nochmals versuchen'**
  String get discoverRetry;

  /// No description provided for @jplanTitle.
  ///
  /// In de, this message translates to:
  /// **'Etappentour planen'**
  String get jplanTitle;

  /// No description provided for @jplanIntro.
  ///
  /// In de, this message translates to:
  /// **'Wähle Start und Ziel – Alvyo teilt den Weg in Tage, die bei einer Hütte, einem Hotel, einem Campingplatz oder einer Haltestelle für die Heimreise enden.'**
  String get jplanIntro;

  /// No description provided for @jplanMapHint.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf die Karte, um einen Punkt zu setzen, oder suche einen Ort.'**
  String get jplanMapHint;

  /// No description provided for @jplanPointMap.
  ///
  /// In de, this message translates to:
  /// **'Punkt auf der Karte'**
  String get jplanPointMap;

  /// No description provided for @jplanPointRemove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get jplanPointRemove;

  /// No description provided for @jplanSearchStart.
  ///
  /// In de, this message translates to:
  /// **'Start suchen …'**
  String get jplanSearchStart;

  /// No description provided for @jplanSearchEnd.
  ///
  /// In de, this message translates to:
  /// **'Ziel suchen …'**
  String get jplanSearchEnd;

  /// No description provided for @jplanSearchMore.
  ///
  /// In de, this message translates to:
  /// **'Weiteres Ziel suchen …'**
  String get jplanSearchMore;

  /// No description provided for @jplanBy.
  ///
  /// In de, this message translates to:
  /// **'Aufteilen nach'**
  String get jplanBy;

  /// No description provided for @jplanByDays.
  ///
  /// In de, this message translates to:
  /// **'Anzahl Tage'**
  String get jplanByDays;

  /// No description provided for @jplanByHours.
  ///
  /// In de, this message translates to:
  /// **'Stunden pro Tag'**
  String get jplanByHours;

  /// No description provided for @jplanDays.
  ///
  /// In de, this message translates to:
  /// **'Tage'**
  String get jplanDays;

  /// No description provided for @jplanHoursMin.
  ///
  /// In de, this message translates to:
  /// **'Mindestens Stunden pro Tag'**
  String get jplanHoursMin;

  /// No description provided for @jplanHoursMax.
  ///
  /// In de, this message translates to:
  /// **'Höchstens Stunden pro Tag'**
  String get jplanHoursMax;

  /// No description provided for @jplanMax.
  ///
  /// In de, this message translates to:
  /// **'Höchstens (h pro Tag, leer: etwas mehr)'**
  String get jplanMax;

  /// No description provided for @jplanKinds.
  ///
  /// In de, this message translates to:
  /// **'Übernachten am liebsten in'**
  String get jplanKinds;

  /// No description provided for @jplanKindHut.
  ///
  /// In de, this message translates to:
  /// **'Hütten'**
  String get jplanKindHut;

  /// No description provided for @jplanKindHotel.
  ///
  /// In de, this message translates to:
  /// **'Hotels und Gasthäusern'**
  String get jplanKindHotel;

  /// No description provided for @jplanKindCampsite.
  ///
  /// In de, this message translates to:
  /// **'Campingplätzen'**
  String get jplanKindCampsite;

  /// No description provided for @jplanKindPtStop.
  ///
  /// In de, this message translates to:
  /// **'Haltestelle (Heimreise)'**
  String get jplanKindPtStop;

  /// No description provided for @jplanProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get jplanProfile;

  /// No description provided for @jplanProfileHike.
  ///
  /// In de, this message translates to:
  /// **'Wandern (bis T3)'**
  String get jplanProfileHike;

  /// No description provided for @jplanProfileAlpine.
  ///
  /// In de, this message translates to:
  /// **'Alpinwandern (bis T6)'**
  String get jplanProfileAlpine;

  /// No description provided for @jplanSubmit.
  ///
  /// In de, this message translates to:
  /// **'Etappen vorschlagen'**
  String get jplanSubmit;

  /// No description provided for @jplanSuggest.
  ///
  /// In de, this message translates to:
  /// **'Mehrere Wege vorschlagen'**
  String get jplanSuggest;

  /// No description provided for @jplanRunning.
  ///
  /// In de, this message translates to:
  /// **'Wird geplant …'**
  String get jplanRunning;

  /// No description provided for @jplanDay.
  ///
  /// In de, this message translates to:
  /// **'Tag {n}'**
  String jplanDay(int n);

  /// No description provided for @jplanToEnd.
  ///
  /// In de, this message translates to:
  /// **'bis zum Ziel'**
  String get jplanToEnd;

  /// No description provided for @jplanEarlier.
  ///
  /// In de, this message translates to:
  /// **'Früher: {place}'**
  String jplanEarlier(String place);

  /// No description provided for @jplanLater.
  ///
  /// In de, this message translates to:
  /// **'Später: {place}'**
  String jplanLater(String place);

  /// No description provided for @jplanOverMax.
  ///
  /// In de, this message translates to:
  /// **'Länger als gewünscht: vorher gibt es keinen Ort zum Übernachten.'**
  String get jplanOverMax;

  /// No description provided for @jplanUnderMin.
  ///
  /// In de, this message translates to:
  /// **'Kürzer als gewünscht: anders lassen sich die Tage mit den Orten zum Übernachten nicht einteilen.'**
  String get jplanUnderMin;

  /// No description provided for @jplanHutHint.
  ///
  /// In de, this message translates to:
  /// **'Ob die Hütte offen ist und ob du reservieren musst, weiss OpenStreetMap selten – prüfe es vorher.'**
  String get jplanHutHint;

  /// No description provided for @jplanWebsite.
  ///
  /// In de, this message translates to:
  /// **'Website'**
  String get jplanWebsite;

  /// No description provided for @jplanFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Planung hat nicht geklappt. Versuche es gleich noch einmal.'**
  String get jplanFailed;

  /// No description provided for @jplanNoPath.
  ///
  /// In de, this message translates to:
  /// **'Zwischen diesen Punkten gibt es mit diesem Profil keinen Weg.'**
  String get jplanNoPath;

  /// No description provided for @jplanSummary.
  ///
  /// In de, this message translates to:
  /// **'{days, plural, =1{1 Tag} other{{days} Tage}} · {distance}'**
  String jplanSummary(int days, String distance);

  /// No description provided for @jplanWays.
  ///
  /// In de, this message translates to:
  /// **'Wege'**
  String get jplanWays;

  /// No description provided for @jplanWay.
  ///
  /// In de, this message translates to:
  /// **'Weg {n}'**
  String jplanWay(int n);

  /// No description provided for @jplanWayDirect.
  ///
  /// In de, this message translates to:
  /// **'Weg {n}: direkt'**
  String jplanWayDirect(int n);

  /// No description provided for @jplanWayVia.
  ///
  /// In de, this message translates to:
  /// **'Weg {n}: über {place}'**
  String jplanWayVia(int n, String place);

  /// No description provided for @jplanWaysHint.
  ///
  /// In de, this message translates to:
  /// **'Wo zwei Wege am gleichen Ort übernachten, kannst du dort von einem auf den anderen wechseln.'**
  String get jplanWaysHint;

  /// No description provided for @jplanSwitch.
  ///
  /// In de, this message translates to:
  /// **'Ab hier weiter auf Weg {n}'**
  String jplanSwitch(int n);

  /// No description provided for @jplanTitleField.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get jplanTitleField;

  /// No description provided for @jplanCreate.
  ///
  /// In de, this message translates to:
  /// **'Etappentour erstellen'**
  String get jplanCreate;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @routeDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'Route löschen? Das lässt sich nicht rückgängig machen.'**
  String get routeDeleteConfirm;

  /// No description provided for @journeyDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'Etappentour mit allen Etappen und Routen löschen? Das lässt sich nicht rückgängig machen.'**
  String get journeyDeleteConfirm;

  /// No description provided for @jplanTooLong.
  ///
  /// In de, this message translates to:
  /// **'Mit höchstens {hours} h pro Tag geht das nicht: dafür braucht es mindestens {days} Tage.'**
  String jplanTooLong(String hours, int days);

  /// No description provided for @jplanTooLongNone.
  ///
  /// In de, this message translates to:
  /// **'Mit höchstens {hours} h pro Tag geht das nicht: unterwegs gibt es zu wenige Orte zum Übernachten.'**
  String jplanTooLongNone(String hours);

  /// No description provided for @jplanPlanIn.
  ///
  /// In de, this message translates to:
  /// **'In {days} Tagen planen'**
  String jplanPlanIn(int days);

  /// No description provided for @navFeed.
  ///
  /// In de, this message translates to:
  /// **'Neuigkeiten'**
  String get navFeed;

  /// No description provided for @settingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// No description provided for @themeTitle.
  ///
  /// In de, this message translates to:
  /// **'Darstellung'**
  String get themeTitle;

  /// No description provided for @themeSystem.
  ///
  /// In de, this message translates to:
  /// **'Automatisch'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get themeDark;

  /// No description provided for @languageTitle.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get languageTitle;

  /// No description provided for @profileMine.
  ///
  /// In de, this message translates to:
  /// **'Mein Profil'**
  String get profileMine;

  /// No description provided for @accountNotifications.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen per E-Mail'**
  String get accountNotifications;

  /// No description provided for @accountNotifyComments.
  ///
  /// In de, this message translates to:
  /// **'Wenn jemand meine Routen und Etappentouren kommentiert'**
  String get accountNotifyComments;

  /// No description provided for @accountNotifyFollows.
  ///
  /// In de, this message translates to:
  /// **'Wenn mir jemand folgt'**
  String get accountNotifyFollows;

  /// No description provided for @contactsTitle.
  ///
  /// In de, this message translates to:
  /// **'Kontakte für geteilte Wanderungen'**
  String get contactsTitle;

  /// No description provided for @contactsIntro.
  ///
  /// In de, this message translates to:
  /// **'Starte in der App eine Wanderung, kannst du ausgewählten Kontakten deinen Standort zeigen. Ist die Wanderung 30 Minuten nach dem geplanten Ende nicht beendet, bekommen sie eine E-Mail mit dem letzten Standort.'**
  String get contactsIntro;

  /// No description provided for @contactsName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get contactsName;

  /// No description provided for @contactsEmail.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get contactsEmail;

  /// No description provided for @contactsAdd.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get contactsAdd;

  /// No description provided for @contactsRemove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get contactsRemove;

  /// No description provided for @contactsDuplicate.
  ///
  /// In de, this message translates to:
  /// **'Diese Adresse ist schon ein Kontakt.'**
  String get contactsDuplicate;

  /// No description provided for @contactsFull.
  ///
  /// In de, this message translates to:
  /// **'Höchstens 10 Kontakte.'**
  String get contactsFull;

  /// No description provided for @blockedTitle.
  ///
  /// In de, this message translates to:
  /// **'Blockierte Personen'**
  String get blockedTitle;

  /// No description provided for @blockedEmpty.
  ///
  /// In de, this message translates to:
  /// **'Du hast niemanden blockiert.'**
  String get blockedEmpty;

  /// No description provided for @accountDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get accountDeleteTitle;

  /// No description provided for @accountDeleteText.
  ///
  /// In de, this message translates to:
  /// **'Löscht dein Konto und alle deine Routen endgültig. Geteilte Links funktionieren danach nicht mehr.'**
  String get accountDeleteText;

  /// No description provided for @accountDeleteSubmit.
  ///
  /// In de, this message translates to:
  /// **'Konto endgültig löschen'**
  String get accountDeleteSubmit;

  /// No description provided for @accountDeleteWrong.
  ///
  /// In de, this message translates to:
  /// **'Das Passwort ist falsch.'**
  String get accountDeleteWrong;

  /// No description provided for @accountDeleteRecent.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto hat kein Passwort: Zum Bestätigen musst du dich in den letzten 15 Minuten angemeldet haben.'**
  String get accountDeleteRecent;

  /// No description provided for @accountDeleteLoginAgain.
  ///
  /// In de, this message translates to:
  /// **'Bitte melde dich neu an und versuche es dann gleich noch einmal.'**
  String get accountDeleteLoginAgain;

  /// No description provided for @loginForgot.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen?'**
  String get loginForgot;

  /// No description provided for @loginSignup.
  ///
  /// In de, this message translates to:
  /// **'Konto erstellen'**
  String get loginSignup;

  /// No description provided for @myMapTitle.
  ///
  /// In de, this message translates to:
  /// **'Karte meiner Touren'**
  String get myMapTitle;

  /// No description provided for @myMapEmpty.
  ///
  /// In de, this message translates to:
  /// **'In diesem Ausschnitt passt nichts zu den Filtern.'**
  String get myMapEmpty;

  /// No description provided for @feedIntro.
  ///
  /// In de, this message translates to:
  /// **'Neue öffentliche Touren der Leute, denen du folgst.'**
  String get feedIntro;

  /// No description provided for @feedEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch nichts – folge Leuten, deren Touren dich interessieren. Du findest sie beim Entdecken.'**
  String get feedEmpty;

  /// No description provided for @feedMore.
  ///
  /// In de, this message translates to:
  /// **'Ältere laden'**
  String get feedMore;

  /// No description provided for @profileSince.
  ///
  /// In de, this message translates to:
  /// **'dabei seit {date}'**
  String profileSince(String date);

  /// No description provided for @profileFollowers.
  ///
  /// In de, this message translates to:
  /// **'{n} Follower'**
  String profileFollowers(int n);

  /// No description provided for @profileFollowing.
  ///
  /// In de, this message translates to:
  /// **'folgt {n}'**
  String profileFollowing(int n);

  /// No description provided for @profileFollow.
  ///
  /// In de, this message translates to:
  /// **'Folgen'**
  String get profileFollow;

  /// No description provided for @profileUnfollow.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr folgen'**
  String get profileUnfollow;

  /// No description provided for @profileBlock.
  ///
  /// In de, this message translates to:
  /// **'Blockieren'**
  String get profileBlock;

  /// No description provided for @profileUnblock.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr blockieren'**
  String get profileUnblock;

  /// No description provided for @profileBlockedNote.
  ///
  /// In de, this message translates to:
  /// **'Blockiert: Diese Person kann deine Touren nicht kommentieren und dir nicht folgen, und du siehst ihre Kommentare nicht.'**
  String get profileBlockedNote;

  /// No description provided for @profileRoutes.
  ///
  /// In de, this message translates to:
  /// **'Routen'**
  String get profileRoutes;

  /// No description provided for @profileJourneys.
  ///
  /// In de, this message translates to:
  /// **'Etappentouren'**
  String get profileJourneys;

  /// No description provided for @reportAction.
  ///
  /// In de, this message translates to:
  /// **'Melden'**
  String get reportAction;

  /// No description provided for @reportReason.
  ///
  /// In de, this message translates to:
  /// **'Grund'**
  String get reportReason;

  /// No description provided for @reportReasonSpam.
  ///
  /// In de, this message translates to:
  /// **'Spam oder Werbung'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonOffensive.
  ///
  /// In de, this message translates to:
  /// **'Beleidigend oder unangemessen'**
  String get reportReasonOffensive;

  /// No description provided for @reportReasonDangerous.
  ///
  /// In de, this message translates to:
  /// **'Gefährlich oder falsch'**
  String get reportReasonDangerous;

  /// No description provided for @reportReasonOther.
  ///
  /// In de, this message translates to:
  /// **'Anderes'**
  String get reportReasonOther;

  /// No description provided for @reportNote.
  ///
  /// In de, this message translates to:
  /// **'Was ist los? (freiwillig)'**
  String get reportNote;

  /// No description provided for @reportThanks.
  ///
  /// In de, this message translates to:
  /// **'Danke, wir schauen es uns an.'**
  String get reportThanks;

  /// No description provided for @editAction.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get editAction;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @saveConflict.
  ///
  /// In de, this message translates to:
  /// **'Jemand hat das inzwischen geändert. Hier ist der neue Stand – deine Änderung ist nicht gespeichert.'**
  String get saveConflict;

  /// No description provided for @fieldTitle.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get fieldTitle;

  /// No description provided for @fieldDescription.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get fieldDescription;

  /// No description provided for @fieldVisibility.
  ///
  /// In de, this message translates to:
  /// **'Sichtbarkeit'**
  String get fieldVisibility;

  /// No description provided for @visibilityPrivate.
  ///
  /// In de, this message translates to:
  /// **'Privat'**
  String get visibilityPrivate;

  /// No description provided for @visibilityUnlisted.
  ///
  /// In de, this message translates to:
  /// **'Mit Link teilen'**
  String get visibilityUnlisted;

  /// No description provided for @visibilityPublic.
  ///
  /// In de, this message translates to:
  /// **'Öffentlich'**
  String get visibilityPublic;

  /// No description provided for @visibilityNeedsVerify.
  ///
  /// In de, this message translates to:
  /// **'Bestätige deine E-Mail-Adresse, um Routen zu veröffentlichen.'**
  String get visibilityNeedsVerify;

  /// No description provided for @tagsLabel.
  ///
  /// In de, this message translates to:
  /// **'Tags'**
  String get tagsLabel;

  /// No description provided for @tagsHint.
  ///
  /// In de, this message translates to:
  /// **'Durch Kommas getrennt'**
  String get tagsHint;

  /// No description provided for @ownerBy.
  ///
  /// In de, this message translates to:
  /// **'von {user}'**
  String ownerBy(String user);

  /// No description provided for @shareAction.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get shareAction;

  /// No description provided for @shareLink.
  ///
  /// In de, this message translates to:
  /// **'Link zum Teilen'**
  String get shareLink;

  /// No description provided for @shareSend.
  ///
  /// In de, this message translates to:
  /// **'Link senden …'**
  String get shareSend;

  /// No description provided for @shareCopied.
  ///
  /// In de, this message translates to:
  /// **'Kopiert'**
  String get shareCopied;

  /// No description provided for @shareLinkHint.
  ///
  /// In de, this message translates to:
  /// **'Wähle «Mit Link teilen» oder «Öffentlich», um einen Link zu senden.'**
  String get shareLinkHint;

  /// No description provided for @shareRotate.
  ///
  /// In de, this message translates to:
  /// **'Neuen Link erzeugen'**
  String get shareRotate;

  /// No description provided for @shareRotateHint.
  ///
  /// In de, this message translates to:
  /// **'Der bisherige Link funktioniert danach nicht mehr.'**
  String get shareRotateHint;

  /// No description provided for @sharePeople.
  ///
  /// In de, this message translates to:
  /// **'Mit Personen teilen'**
  String get sharePeople;

  /// No description provided for @sharePending.
  ///
  /// In de, this message translates to:
  /// **'eingeladen'**
  String get sharePending;

  /// No description provided for @shareRemove.
  ///
  /// In de, this message translates to:
  /// **'Zugriff entfernen'**
  String get shareRemove;

  /// No description provided for @shareWho.
  ///
  /// In de, this message translates to:
  /// **'Benutzername oder E-Mail-Adresse'**
  String get shareWho;

  /// No description provided for @shareInvite.
  ///
  /// In de, this message translates to:
  /// **'Einladen'**
  String get shareInvite;

  /// No description provided for @shareHint.
  ///
  /// In de, this message translates to:
  /// **'Eingeladene erhalten eine E-Mail. Wer noch kein Konto hat, registriert sich mit dieser Adresse.'**
  String get shareHint;

  /// No description provided for @shareNeedsVerify.
  ///
  /// In de, this message translates to:
  /// **'Bestätige deine E-Mail-Adresse, um mit anderen zu teilen.'**
  String get shareNeedsVerify;

  /// No description provided for @shareRate.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Einladungen – versuche es später wieder.'**
  String get shareRate;

  /// No description provided for @shareNoUser.
  ///
  /// In de, this message translates to:
  /// **'Diesen Benutzernamen gibt es nicht.'**
  String get shareNoUser;

  /// No description provided for @shareSelf.
  ///
  /// In de, this message translates to:
  /// **'Du kannst dich nicht selbst einladen.'**
  String get shareSelf;

  /// No description provided for @shareTooMany.
  ///
  /// In de, this message translates to:
  /// **'Es haben bereits zu viele Personen Zugriff.'**
  String get shareTooMany;

  /// No description provided for @shareBadEmail.
  ///
  /// In de, this message translates to:
  /// **'Ungültige E-Mail-Adresse.'**
  String get shareBadEmail;

  /// No description provided for @roleViewer.
  ///
  /// In de, this message translates to:
  /// **'Kann ansehen'**
  String get roleViewer;

  /// No description provided for @roleEditor.
  ///
  /// In de, this message translates to:
  /// **'Kann mitplanen'**
  String get roleEditor;

  /// No description provided for @sharedTitle.
  ///
  /// In de, this message translates to:
  /// **'Mit mir geteilt'**
  String get sharedTitle;

  /// No description provided for @gpxRoute.
  ///
  /// In de, this message translates to:
  /// **'GPX teilen …'**
  String get gpxRoute;

  /// No description provided for @gpxJourney.
  ///
  /// In de, this message translates to:
  /// **'Alle Etappen als GPX (ZIP) teilen …'**
  String get gpxJourney;

  /// No description provided for @photosTitle.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get photosTitle;

  /// No description provided for @photosAdd.
  ///
  /// In de, this message translates to:
  /// **'Fotos hinzufügen'**
  String get photosAdd;

  /// No description provided for @photosCamera.
  ///
  /// In de, this message translates to:
  /// **'Foto aufnehmen'**
  String get photosCamera;

  /// No description provided for @photosLibrary.
  ///
  /// In de, this message translates to:
  /// **'Aus der Mediathek'**
  String get photosLibrary;

  /// No description provided for @photosUploading.
  ///
  /// In de, this message translates to:
  /// **'{done} von {total} hochgeladen …'**
  String photosUploading(int done, int total);

  /// No description provided for @photosHint.
  ///
  /// In de, this message translates to:
  /// **'JPEG, PNG, WebP oder HEIC bis 20 MB. Wir entfernen alle Metadaten; Fotos, die entlang der Route aufgenommen wurden, erscheinen auf der Karte.'**
  String get photosHint;

  /// No description provided for @photosProblemFormat.
  ///
  /// In de, this message translates to:
  /// **'kein JPEG-, PNG-, WebP- oder HEIC-Bild'**
  String get photosProblemFormat;

  /// No description provided for @photosProblemSize.
  ///
  /// In de, this message translates to:
  /// **'zu gross (höchstens 20 MB)'**
  String get photosProblemSize;

  /// No description provided for @photosProblemLimit.
  ///
  /// In de, this message translates to:
  /// **'zu viele Fotos (höchstens 100 pro Tour und 1000 pro Person)'**
  String get photosProblemLimit;

  /// No description provided for @photosProblemRate.
  ///
  /// In de, this message translates to:
  /// **'zu viele Uploads – versuche es gleich noch einmal'**
  String get photosProblemRate;

  /// No description provided for @photosProblemOther.
  ///
  /// In de, this message translates to:
  /// **'Hochladen fehlgeschlagen'**
  String get photosProblemOther;

  /// No description provided for @photosCaption.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get photosCaption;

  /// No description provided for @photosBy.
  ///
  /// In de, this message translates to:
  /// **'von {user}'**
  String photosBy(String user);

  /// No description provided for @photosDelete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get photosDelete;

  /// No description provided for @photosDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'Wirklich löschen?'**
  String get photosDeleteConfirm;

  /// No description provided for @communityLike.
  ///
  /// In de, this message translates to:
  /// **'Merken'**
  String get communityLike;

  /// No description provided for @communityLikes.
  ///
  /// In de, this message translates to:
  /// **'{n} Mal gemerkt'**
  String communityLikes(int n);

  /// No description provided for @communityComments.
  ///
  /// In de, this message translates to:
  /// **'{n} Kommentare'**
  String communityComments(int n);

  /// No description provided for @communityCommentsAllowed.
  ///
  /// In de, this message translates to:
  /// **'Kommentare erlauben'**
  String get communityCommentsAllowed;

  /// No description provided for @communityCommentsOff.
  ///
  /// In de, this message translates to:
  /// **'Kommentare sind ausgeschaltet.'**
  String get communityCommentsOff;

  /// No description provided for @communityCommentPlaceholder.
  ///
  /// In de, this message translates to:
  /// **'Kommentar schreiben …'**
  String get communityCommentPlaceholder;

  /// No description provided for @communityCommentSend.
  ///
  /// In de, this message translates to:
  /// **'Kommentieren'**
  String get communityCommentSend;

  /// No description provided for @communityReply.
  ///
  /// In de, this message translates to:
  /// **'Antworten'**
  String get communityReply;

  /// No description provided for @communityReplyPlaceholder.
  ///
  /// In de, this message translates to:
  /// **'Deine Antwort …'**
  String get communityReplyPlaceholder;

  /// No description provided for @communityEdited.
  ///
  /// In de, this message translates to:
  /// **'bearbeitet'**
  String get communityEdited;

  /// No description provided for @communityRate.
  ///
  /// In de, this message translates to:
  /// **'Das ging zu schnell – versuche es gleich noch einmal.'**
  String get communityRate;

  /// No description provided for @communityVerifyToComment.
  ///
  /// In de, this message translates to:
  /// **'Bestätige deine E-Mail-Adresse, um zu kommentieren.'**
  String get communityVerifyToComment;

  /// No description provided for @stageEdit.
  ///
  /// In de, this message translates to:
  /// **'Etappe bearbeiten'**
  String get stageEdit;

  /// No description provided for @stageDate.
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get stageDate;

  /// No description provided for @stageDateNone.
  ///
  /// In de, this message translates to:
  /// **'Kein Datum'**
  String get stageDateNone;

  /// No description provided for @stageStatus.
  ///
  /// In de, this message translates to:
  /// **'Status'**
  String get stageStatus;

  /// No description provided for @statusPlanned.
  ///
  /// In de, this message translates to:
  /// **'Geplant'**
  String get statusPlanned;

  /// No description provided for @stageAccommodationLabel.
  ///
  /// In de, this message translates to:
  /// **'Unterkunft'**
  String get stageAccommodationLabel;

  /// No description provided for @stageAccommodationPlaceholder.
  ///
  /// In de, this message translates to:
  /// **'z. B. Gasthaus Alpenhof'**
  String get stageAccommodationPlaceholder;

  /// No description provided for @stageBookedLabel.
  ///
  /// In de, this message translates to:
  /// **'Gebucht'**
  String get stageBookedLabel;

  /// No description provided for @stageNotes.
  ///
  /// In de, this message translates to:
  /// **'Notizen'**
  String get stageNotes;

  /// No description provided for @stageTransfer.
  ///
  /// In de, this message translates to:
  /// **'Überbrückt mit'**
  String get stageTransfer;

  /// No description provided for @transferNone.
  ///
  /// In de, this message translates to:
  /// **'–'**
  String get transferNone;

  /// No description provided for @sbbToStart.
  ///
  /// In de, this message translates to:
  /// **'SBB-Fahrplan: Anreise'**
  String get sbbToStart;

  /// No description provided for @sbbFromEnd.
  ///
  /// In de, this message translates to:
  /// **'SBB-Fahrplan: Rückreise'**
  String get sbbFromEnd;

  /// No description provided for @sbbTransfer.
  ///
  /// In de, this message translates to:
  /// **'SBB-Fahrplan'**
  String get sbbTransfer;

  /// No description provided for @connectionsShow.
  ///
  /// In de, this message translates to:
  /// **'Verbindungen anzeigen'**
  String get connectionsShow;

  /// No description provided for @connectionsDepart.
  ///
  /// In de, this message translates to:
  /// **'Ab'**
  String get connectionsDepart;

  /// No description provided for @connectionsArrive.
  ///
  /// In de, this message translates to:
  /// **'An'**
  String get connectionsArrive;

  /// No description provided for @connectionsSearch.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get connectionsSearch;

  /// No description provided for @connectionsNone.
  ///
  /// In de, this message translates to:
  /// **'Keine Verbindung gefunden.'**
  String get connectionsNone;

  /// No description provided for @connectionsUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Fahrplanabfrage gerade nicht möglich – nutze den SBB-Fahrplan.'**
  String get connectionsUnavailable;

  /// No description provided for @connectionsTransfers.
  ///
  /// In de, this message translates to:
  /// **'{n} Umst.'**
  String connectionsTransfers(int n);

  /// No description provided for @connectionsWalk.
  ///
  /// In de, this message translates to:
  /// **'{min} min zu Fuss'**
  String connectionsWalk(int min);

  /// No description provided for @connectionsPlatform.
  ///
  /// In de, this message translates to:
  /// **'Gl./Kante {p}'**
  String connectionsPlatform(String p);

  /// No description provided for @connectionsSource.
  ///
  /// In de, this message translates to:
  /// **'Fahrplandaten: opentransportdata.swiss'**
  String get connectionsSource;

  /// No description provided for @collectionsTitle.
  ///
  /// In de, this message translates to:
  /// **'Sammlungen'**
  String get collectionsTitle;

  /// No description provided for @collectionsIntro.
  ///
  /// In de, this message translates to:
  /// **'Routen und Etappentouren zusammenstellen – als Wunschliste, Ideensammlung oder zum Teilen. Eine Sammlung gibt keinen Zugriff: Jede Person sieht nur, was sie ohnehin öffnen darf.'**
  String get collectionsIntro;

  /// No description provided for @collectionsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Sammlungen.'**
  String get collectionsEmpty;

  /// No description provided for @collectionNew.
  ///
  /// In de, this message translates to:
  /// **'Neue Sammlung'**
  String get collectionNew;

  /// No description provided for @collectionItemsCount.
  ///
  /// In de, this message translates to:
  /// **'{n} Einträge'**
  String collectionItemsCount(int n);

  /// No description provided for @collectionEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch leer. Füge Routen und Etappentouren über ihr Menü hinzu: «Zur Sammlung hinzufügen …».'**
  String get collectionEmpty;

  /// No description provided for @collectionAddTo.
  ///
  /// In de, this message translates to:
  /// **'Zur Sammlung hinzufügen …'**
  String get collectionAddTo;

  /// No description provided for @collectionAdded.
  ///
  /// In de, this message translates to:
  /// **'Hinzugefügt zu «{title}»'**
  String collectionAdded(String title);

  /// No description provided for @collectionAlready.
  ///
  /// In de, this message translates to:
  /// **'Schon in «{title}»'**
  String collectionAlready(String title);

  /// No description provided for @collectionRemoveItem.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get collectionRemoveItem;

  /// No description provided for @collectionDelete.
  ///
  /// In de, this message translates to:
  /// **'Sammlung löschen'**
  String get collectionDelete;

  /// No description provided for @collectionDeleteConfirm.
  ///
  /// In de, this message translates to:
  /// **'Sammlung löschen? Routen und Etappentouren bleiben.'**
  String get collectionDeleteConfirm;

  /// No description provided for @collectionStages.
  ///
  /// In de, this message translates to:
  /// **'{n} Etappen'**
  String collectionStages(int n);

  /// No description provided for @myMapKindHike.
  ///
  /// In de, this message translates to:
  /// **'Gewanderte'**
  String get myMapKindHike;

  /// No description provided for @connectionsFromHere.
  ///
  /// In de, this message translates to:
  /// **'Verbindungen von hier zum Start'**
  String get connectionsFromHere;

  /// No description provided for @connectionsNoPosition.
  ///
  /// In de, this message translates to:
  /// **'Dein Standort ist nicht bekannt. Erlaube Alvyo den Standort in den iPhone-Einstellungen.'**
  String get connectionsNoPosition;

  /// No description provided for @stageMore.
  ///
  /// In de, this message translates to:
  /// **'Details und Anreise'**
  String get stageMore;

  /// No description provided for @travelTitle.
  ///
  /// In de, this message translates to:
  /// **'An- und Heimreise'**
  String get travelTitle;

  /// No description provided for @travelTo.
  ///
  /// In de, this message translates to:
  /// **'Anreise'**
  String get travelTo;

  /// No description provided for @travelBack.
  ///
  /// In de, this message translates to:
  /// **'Heimreise'**
  String get travelBack;

  /// No description provided for @travelFrom.
  ///
  /// In de, this message translates to:
  /// **'Von'**
  String get travelFrom;

  /// No description provided for @travelToHome.
  ///
  /// In de, this message translates to:
  /// **'Nach'**
  String get travelToHome;

  /// No description provided for @travelNone.
  ///
  /// In de, this message translates to:
  /// **'– keine –'**
  String get travelNone;

  /// No description provided for @travelOn.
  ///
  /// In de, this message translates to:
  /// **'am {date}'**
  String travelOn(String date);

  /// No description provided for @travelNoDate.
  ///
  /// In de, this message translates to:
  /// **'Die Etappe hat kein Datum: Verbindungen von heute.'**
  String get travelNoDate;

  /// No description provided for @travelNoHomes.
  ///
  /// In de, this message translates to:
  /// **'Füge in deinem Konto ein Zuhause hinzu, um die An- und Heimreise mit dem öffentlichen Verkehr zu planen.'**
  String get travelNoHomes;

  /// No description provided for @travelPrivate.
  ///
  /// In de, this message translates to:
  /// **'Nur du siehst deine An- und Heimreise.'**
  String get travelPrivate;

  /// No description provided for @travelNoRoute.
  ///
  /// In de, this message translates to:
  /// **'Sobald eine Etappe eine Route hat.'**
  String get travelNoRoute;

  /// No description provided for @travelChoose.
  ///
  /// In de, this message translates to:
  /// **'Wähle ein Zuhause'**
  String get travelChoose;

  /// No description provided for @homesTitle.
  ///
  /// In de, this message translates to:
  /// **'Zuhause'**
  String get homesTitle;

  /// No description provided for @homesIntro.
  ///
  /// In de, this message translates to:
  /// **'Von hier planst du die Anreise zu deinen Etappentouren und die Heimreise mit dem öffentlichen Verkehr. Höchstens 5; nur du siehst sie.'**
  String get homesIntro;

  /// No description provided for @homesName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get homesName;

  /// No description provided for @homesNamePlaceholder.
  ///
  /// In de, this message translates to:
  /// **'z. B. Zuhause, Büro'**
  String get homesNamePlaceholder;

  /// No description provided for @homesAddress.
  ///
  /// In de, this message translates to:
  /// **'Adresse suchen …'**
  String get homesAddress;

  /// No description provided for @homesAdd.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get homesAdd;

  /// No description provided for @homesRemove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get homesRemove;

  /// No description provided for @homesFull.
  ///
  /// In de, this message translates to:
  /// **'Höchstens 5 Zuhause.'**
  String get homesFull;

  /// No description provided for @travelStart.
  ///
  /// In de, this message translates to:
  /// **'Start der Tour'**
  String get travelStart;

  /// No description provided for @travelEnd.
  ///
  /// In de, this message translates to:
  /// **'Ende der Tour'**
  String get travelEnd;

  /// The title of a hike recorded without a route; the date is added.
  ///
  /// In de, this message translates to:
  /// **'Wanderung'**
  String get recordTitle;

  /// No description provided for @recordStart.
  ///
  /// In de, this message translates to:
  /// **'Aufzeichnung starten'**
  String get recordStart;

  /// No description provided for @recordRefused.
  ///
  /// In de, this message translates to:
  /// **'Nicht gespeichert: Die Wanderung ist zu kurz oder führt mehr als 15 km über die Grenze der Schweiz und Liechtensteins.'**
  String get recordRefused;

  /// Short name under the icon in the app's bar (routesTitle).
  ///
  /// In de, this message translates to:
  /// **'Routen'**
  String get barRoutes;

  /// Short name under the icon in the app's bar (journeysTitle).
  ///
  /// In de, this message translates to:
  /// **'Etappen'**
  String get barJourneys;

  /// Button above My routes that opens «Route planen».
  ///
  /// In de, this message translates to:
  /// **'Planen'**
  String get planAction;

  /// No description provided for @routePrivacyOwner.
  ///
  /// In de, this message translates to:
  /// **'Andere sehen diese Wanderung ohne die ersten und letzten 500 m.'**
  String get routePrivacyOwner;

  /// No description provided for @routePrivacyOthers.
  ///
  /// In de, this message translates to:
  /// **'Start und Ende der Wanderung sind verborgen.'**
  String get routePrivacyOthers;

  /// No description provided for @routePrivacyAll.
  ///
  /// In de, this message translates to:
  /// **'Diese Wanderung ist zu kurz, um sie anderen zu zeigen: Start und Ende sind verborgen.'**
  String get routePrivacyAll;

  /// A leg planned with the hiking profile is much longer than with the alpine one.
  ///
  /// In de, this message translates to:
  /// **'Mit «Alpinwandern» nur {alpine} statt {hike}.'**
  String plannerAlpineShorter(String alpine, String hike);

  /// {grade} is an SAC grade such as T4.
  ///
  /// In de, this message translates to:
  /// **'Der kürzere Weg führt über {grade}.'**
  String plannerAlpineGrade(String grade);

  /// No description provided for @plannerAlpineUse.
  ///
  /// In de, this message translates to:
  /// **'Diesen Abschnitt alpin planen'**
  String get plannerAlpineUse;

  /// No description provided for @plannerAlpineUsed.
  ///
  /// In de, this message translates to:
  /// **'Mit «Alpinwandern» geplant.'**
  String get plannerAlpineUsed;

  /// No description provided for @plannerAlpineUndo.
  ///
  /// In de, this message translates to:
  /// **'Wieder als Wanderung'**
  String get plannerAlpineUndo;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
