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
      'No hikes in Apple Health in the last 60 days. Record them with the Workout app on your Apple Watch («Hiking» or «Outdoor Walk»). If you did not allow access: Settings → Apps → Health → Data Access & Devices → odysgeh.';

  @override
  String get watchUnavailable => 'Apple Health is not available on this device.';

  @override
  String watchOutside(String reason) {
    return 'Not imported: $reason';
  }

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
}
