// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Alvyo';

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

  @override
  String get navStart => 'Start hike';

  @override
  String get navResume => 'Resume hike';

  @override
  String get navDone => 'Walked';

  @override
  String get navRemaining => 'To go';

  @override
  String get navElapsed => 'Underway';

  @override
  String navOffRoute(int metres) {
    return '$metres m off the route';
  }

  @override
  String get navOffRouteTitle => 'Off the route';

  @override
  String get navArrived => 'Destination reached';

  @override
  String get navWaiting => 'Waiting for GPS …';

  @override
  String get navFinish => 'Finish';

  @override
  String get navFinishQuestion => 'Finish the hike and save the recording?';

  @override
  String get navContinue => 'Keep going';

  @override
  String get navNoPermission => 'This needs your location. Allow it in Settings.';

  @override
  String navSaved(String distance, String duration) {
    return 'Recorded: $distance in $duration. It will be uploaded once you are online.';
  }

  @override
  String get navFollow => 'Follow my position';

  @override
  String navUploaded(String distance, String duration) {
    return 'Saved to My routes: $distance in $duration';
  }

  @override
  String routesHiked(String date) {
    return 'Hiked on $date';
  }

  @override
  String get watchTitle => 'From Apple Watch';

  @override
  String get watchHike => 'Hike';

  @override
  String get watchWalk => 'Walk';

  @override
  String get watchImport => 'Import';

  @override
  String get watchImported => 'Imported – in My routes';

  @override
  String get watchNoTrack => 'This workout has no GPS track.';

  @override
  String get watchEmpty =>
      'No hikes in Apple Health in the last 60 days. Record them with the Workout app on your Apple Watch («Hiking» or «Outdoor Walk»). If you did not allow access: Settings → Apps → Health → Data Access & Devices → Alvyo.';

  @override
  String get watchUnavailable => 'Apple Health is not available on this device.';

  @override
  String watchOutside(String reason) {
    return 'Not imported: $reason';
  }

  @override
  String get watchReasonOutside => 'it leaves Switzerland and Liechtenstein.';

  @override
  String get watchReasonShort => 'it is too short.';

  @override
  String get turnSharpLeft => 'Turn sharp left';

  @override
  String get turnLeft => 'Turn left';

  @override
  String get turnSlightLeft => 'Turn slightly left';

  @override
  String get turnKeepLeft => 'Keep left';

  @override
  String get turnUTurn => 'Turn around';

  @override
  String get turnSlightRight => 'Turn slightly right';

  @override
  String get turnRight => 'Turn right';

  @override
  String get turnSharpRight => 'Turn sharp right';

  @override
  String get turnKeepRight => 'Keep right';

  @override
  String turnIn(int metres, String turn) {
    return 'In $metres metres, $turn';
  }

  @override
  String get navVoiceOn => 'Turn on voice prompts';

  @override
  String get navVoiceOff => 'Turn off voice prompts';

  @override
  String get journeysTitle => 'Journeys';

  @override
  String get journeysEmpty => 'No journeys yet. Plan them on the website.';

  @override
  String get journeysOffline => 'Offline – saved journeys only';

  @override
  String journeyStagesCount(int done, int total) {
    return '$done of $total stages';
  }

  @override
  String journeyStage(int n) {
    return 'Stage $n';
  }

  @override
  String get journeyNoRoute => 'No route yet';

  @override
  String get statusDone => 'Done';

  @override
  String get statusSkipped => 'Skipped';

  @override
  String gapWarning(String distance) {
    return '$distance from the end of the previous stage';
  }

  @override
  String gapTransfer(String how) {
    return 'Covered by $how';
  }

  @override
  String get transferPt => 'public transport';

  @override
  String get transferCablecar => 'cable car';

  @override
  String get transferOther => 'other means';

  @override
  String stageAccommodation(String name) {
    return 'Accommodation: $name';
  }

  @override
  String get stageBooked => 'booked';

  @override
  String get journeySaveAll => 'Save all stages offline';

  @override
  String journeySaving(int n, int total) {
    return 'Saving stage $n of $total …';
  }

  @override
  String get journeySaved => 'All stages saved offline';

  @override
  String navSwitchQuestion(String title) {
    return 'You are recording “$title”. End that hike and start a new one here? What was recorded so far is kept.';
  }

  @override
  String get navSwitch => 'End it and start here';

  @override
  String get cancel => 'Cancel';

  @override
  String get stageMarkDone => 'Mark as hiked';

  @override
  String get stageMarkPlanned => 'Mark as planned again';

  @override
  String get navMarkStageDone => 'Mark the stage as hiked';

  @override
  String get stageConflict => 'Someone changed the stage in the meantime. Here is the new state.';

  @override
  String get stageMarkedDone => 'Stage marked as hiked';

  @override
  String get areasTitle => 'Protected areas on the way';

  @override
  String get areasWildlifeRest => 'wildlife rest area';

  @override
  String get areasHuntingReserve => 'federal hunting reserve';

  @override
  String get areasBinding => 'binding';

  @override
  String get areasRecommended => 'recommended';

  @override
  String areasPeriod(String from, String to) {
    return '$from to $to';
  }

  @override
  String areasStages(String list) {
    return 'Stage $list';
  }

  @override
  String liveSharedUntil(String time) {
    return 'Position shared · end planned at $time';
  }

  @override
  String get liveLater => 'Later';

  @override
  String get liveLaterFailed => 'That needs a connection. Please try again in a moment.';

  @override
  String get liveShareTitle => 'Share your position';

  @override
  String get liveShareIntro =>
      'The chosen contacts get a link showing where you are. If the hike has not ended 30 minutes after the planned end, they get an e-mail with the last position.';

  @override
  String get liveShareEnd => 'Planned end';

  @override
  String get liveShareStart => 'Share and start';

  @override
  String get liveShareSkip => 'Without sharing';

  @override
  String get liveShareFailed => 'Sharing did not work; the hike is recorded anyway.';

  @override
  String get liveNoContacts => 'Add contacts to share with on the website under “Account”.';

  @override
  String get navRecord => 'Record';

  @override
  String get navProfile => 'Profile';

  @override
  String recordHint(String start) {
    return 'Choose a route and tap “$start” to record the hike.';
  }

  @override
  String get mapLayers => 'Maps';

  @override
  String get mapHuts => 'Huts';

  @override
  String get mapLodging => 'Hotels and campsites';

  @override
  String get placeHut => 'Hut';

  @override
  String get placeHotel => 'Accommodation';

  @override
  String get placeCampsite => 'Campsite';

  @override
  String get placeWildernessHut => 'Unstaffed hut';

  @override
  String get placePtStop => 'Public transport stop';

  @override
  String get placeAddress => 'Address';

  @override
  String get placeWebsite => 'Website';

  @override
  String get placeSearch => 'Search for a place …';

  @override
  String get placeNothingFound => 'Nothing found.';

  @override
  String get jplanTitle => 'Plan a journey';

  @override
  String get jplanIntro =>
      'Choose start and destination – Alvyo splits the way into days that end at a hut, a hotel, a campsite or a stop to travel home.';

  @override
  String get jplanMapHint => 'Tap the map to set a point, or search for a place.';

  @override
  String get jplanPointMap => 'Point on the map';

  @override
  String get jplanPointRemove => 'Remove';

  @override
  String get jplanSearchStart => 'Search for the start …';

  @override
  String get jplanSearchEnd => 'Search for the destination …';

  @override
  String get jplanSearchMore => 'Search for a further destination …';

  @override
  String get jplanBy => 'Split by';

  @override
  String get jplanByDays => 'Number of days';

  @override
  String get jplanByHours => 'Hours per day';

  @override
  String get jplanDays => 'Days';

  @override
  String get jplanHoursMin => 'At least hours per day';

  @override
  String get jplanHoursMax => 'At most hours per day';

  @override
  String get jplanMax => 'At most (h per day, empty: a little more)';

  @override
  String get jplanKinds => 'Preferably spend the nights at';

  @override
  String get jplanKindHut => 'Huts';

  @override
  String get jplanKindHotel => 'Hotels and guest houses';

  @override
  String get jplanKindCampsite => 'Campsites';

  @override
  String get jplanKindPtStop => 'A stop (travel home)';

  @override
  String get jplanProfile => 'Profile';

  @override
  String get jplanProfileHike => 'Hiking (up to T3)';

  @override
  String get jplanProfileAlpine => 'Alpine hiking (up to T6)';

  @override
  String get jplanSubmit => 'Propose stages';

  @override
  String get jplanSuggest => 'Suggest several ways';

  @override
  String get jplanRunning => 'Planning …';

  @override
  String jplanDay(int n) {
    return 'Day $n';
  }

  @override
  String get jplanToEnd => 'to the destination';

  @override
  String jplanEarlier(String place) {
    return 'Earlier: $place';
  }

  @override
  String jplanLater(String place) {
    return 'Later: $place';
  }

  @override
  String get jplanOverMax => 'Longer than wished: there is no place to stay before.';

  @override
  String get jplanUnderMin => 'Shorter than wanted: the places to stay allow no better split of the days.';

  @override
  String get jplanHutHint =>
      'OpenStreetMap rarely knows whether the hut is open and whether you need to book – check before.';

  @override
  String get jplanWebsite => 'Website';

  @override
  String get jplanFailed => 'Planning did not work. Please try again in a moment.';

  @override
  String get jplanNoPath => 'There is no way between these points with this profile.';

  @override
  String jplanSummary(int days, String distance) {
    String _temp0 = intl.Intl.pluralLogic(days, locale: localeName, other: '$days days', one: '1 day');
    return '$_temp0 · $distance';
  }

  @override
  String get jplanWays => 'Ways';

  @override
  String jplanWay(int n) {
    return 'Way $n';
  }

  @override
  String jplanWayDirect(int n) {
    return 'Way $n: direct';
  }

  @override
  String jplanWayVia(int n, String place) {
    return 'Way $n: via $place';
  }

  @override
  String get jplanWaysHint =>
      'Where two ways stay at the same place overnight, you can switch from one to the other there.';

  @override
  String jplanSwitch(int n) {
    return 'From here, continue on way $n';
  }

  @override
  String get jplanTitleField => 'Title';

  @override
  String get jplanCreate => 'Create journey';
}
