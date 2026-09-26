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
  /// **'sie verlässt die Schweiz und Liechtenstein.'**
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

  /// {start} is the text of the button that starts a hike (navStart).
  ///
  /// In de, this message translates to:
  /// **'Wähle eine Route und tippe auf «{start}», um die Wanderung aufzuzeichnen.'**
  String recordHint(String start);

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
