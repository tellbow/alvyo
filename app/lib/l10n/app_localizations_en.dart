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
  String get watchReasonOutside => 'it goes more than 15 km beyond Switzerland and Liechtenstein.';

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
  String get plannerTitle => 'Plan a route';

  @override
  String get plannerHint => 'Search for the start and destination or tap the map.';

  @override
  String get plannerProfileHike => 'Hiking (up to T3)';

  @override
  String get plannerProfileAlpine => 'Alpine hiking (up to T6)';

  @override
  String get plannerPointMap => 'Point on the map';

  @override
  String get plannerUp => 'Move up';

  @override
  String get plannerDown => 'Move down';

  @override
  String get plannerRemove => 'Remove';

  @override
  String get plannerSearchStart => 'Search for the start …';

  @override
  String get plannerSearchEnd => 'Search for the destination …';

  @override
  String get plannerSearchMore => 'Search for a further destination …';

  @override
  String get plannerLegNoPath => 'No path nearby. Remove the point or set another one.';

  @override
  String get plannerLegFailed => 'This leg could not be computed.';

  @override
  String get plannerRetry => 'Try again';

  @override
  String get plannerAddPlace => 'Add as route point';

  @override
  String get plannerSave => 'Save route';

  @override
  String get plannerRouteTitle => 'Title';

  @override
  String get plannerSaveConfirm => 'Save';

  @override
  String get plannerSaveFailed => 'Saving failed.';

  @override
  String get discoverAction => 'Discover';

  @override
  String get discoverTitle => 'Discover hikes';

  @override
  String get discoverKindAll => 'Routes and journeys';

  @override
  String get discoverKindRoute => 'Routes only';

  @override
  String get discoverKindJourney => 'Journeys only';

  @override
  String get discoverSacAny => 'Any difficulty';

  @override
  String discoverSacMax(String grade) {
    return 'up to $grade';
  }

  @override
  String get discoverDurationAny => 'Any hiking time';

  @override
  String get discoverDurationShort => 'up to 2 h';

  @override
  String get discoverDurationMedium => '2–4 h';

  @override
  String get discoverDurationLong => '4–6 h';

  @override
  String get discoverDurationXlong => 'over 6 h';

  @override
  String get discoverDurationHint => 'For journeys, the longest stage counts.';

  @override
  String get discoverRoute => 'Route';

  @override
  String get discoverJourney => 'Journey';

  @override
  String discoverBy(String user) {
    return 'by $user';
  }

  @override
  String discoverStages(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n stages', one: '1 stage');
    return '$_temp0';
  }

  @override
  String discoverLongest(String time) {
    return 'longest $time';
  }

  @override
  String get discoverEmpty => 'There are no public hikes here yet. Move the map or loosen the filters.';

  @override
  String get discoverMore => 'There are more hikes – zoom in or narrow the filters.';

  @override
  String get discoverFailed => 'The search did not work. Please try again in a moment.';

  @override
  String get discoverOffline => 'You are offline. Discovering hikes needs a connection.';

  @override
  String get discoverRetry => 'Try again';

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

  @override
  String get delete => 'Delete';

  @override
  String get routeDeleteConfirm => 'Delete the route? This cannot be undone.';

  @override
  String get journeyDeleteConfirm => 'Delete the multi-day hike with all its stages and routes? This cannot be undone.';

  @override
  String jplanTooLong(String hours, int days) {
    return 'Not possible with at most $hours h a day: it takes at least $days days.';
  }

  @override
  String jplanTooLongNone(String hours) {
    return 'Not possible with at most $hours h a day: there are too few places to stay along the way.';
  }

  @override
  String jplanPlanIn(int days) {
    return 'Plan in $days days';
  }

  @override
  String get navFeed => 'News';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get themeTitle => 'Appearance';

  @override
  String get themeSystem => 'Automatic';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageTitle => 'Language';

  @override
  String get profileMine => 'My profile';

  @override
  String get accountNotifications => 'E-mail notifications';

  @override
  String get accountNotifyComments => 'When someone comments on my routes and journeys';

  @override
  String get accountNotifyFollows => 'When someone follows me';

  @override
  String get contactsTitle => 'Contacts for shared hikes';

  @override
  String get contactsIntro =>
      'When you start a hike in the app, you can show chosen contacts where you are. If the hike has not ended 30 minutes after the expected end, they get an e-mail with the last position.';

  @override
  String get contactsName => 'Name';

  @override
  String get contactsEmail => 'E-mail';

  @override
  String get contactsAdd => 'Add';

  @override
  String get contactsRemove => 'Remove';

  @override
  String get contactsDuplicate => 'This address is a contact already.';

  @override
  String get contactsFull => 'At most 10 contacts.';

  @override
  String get blockedTitle => 'Blocked people';

  @override
  String get blockedEmpty => 'You have not blocked anyone.';

  @override
  String get accountDeleteTitle => 'Delete account';

  @override
  String get accountDeleteText => 'Permanently deletes your account and all your routes. Shared links stop working.';

  @override
  String get accountDeleteSubmit => 'Delete account permanently';

  @override
  String get accountDeleteWrong => 'Wrong password.';

  @override
  String get accountDeleteRecent =>
      'Your account has no password: to confirm, you must have logged in within the last 15 minutes.';

  @override
  String get accountDeleteLoginAgain => 'Please log in again, then try again right away.';

  @override
  String get loginForgot => 'Forgot your password?';

  @override
  String get loginSignup => 'Create an account';

  @override
  String get myMapTitle => 'Map of my hikes';

  @override
  String get myMapEmpty => 'Nothing in this view matches the filters.';

  @override
  String get feedIntro => 'New public hikes of the people you follow.';

  @override
  String get feedEmpty => 'Nothing yet – follow people whose tours interest you. You find them under Discover.';

  @override
  String get feedMore => 'Load older';

  @override
  String profileSince(String date) {
    return 'member since $date';
  }

  @override
  String profileFollowers(int n) {
    return '$n followers';
  }

  @override
  String profileFollowing(int n) {
    return 'follows $n';
  }

  @override
  String get profileFollow => 'Follow';

  @override
  String get profileUnfollow => 'Unfollow';

  @override
  String get profileBlock => 'Block';

  @override
  String get profileUnblock => 'Unblock';

  @override
  String get profileBlockedNote =>
      'Blocked: this person cannot comment on your hikes or follow you, and you do not see their comments.';

  @override
  String get profileRoutes => 'Routes';

  @override
  String get profileJourneys => 'Journeys';

  @override
  String get reportAction => 'Report';

  @override
  String get reportReason => 'Reason';

  @override
  String get reportReasonSpam => 'Spam or advertising';

  @override
  String get reportReasonOffensive => 'Offensive or inappropriate';

  @override
  String get reportReasonDangerous => 'Dangerous or wrong';

  @override
  String get reportReasonOther => 'Other';

  @override
  String get reportNote => 'What is wrong? (optional)';

  @override
  String get reportThanks => 'Thank you, we will look into it.';

  @override
  String get editAction => 'Edit';

  @override
  String get save => 'Save';

  @override
  String get saveConflict =>
      'Someone changed this in the meantime. Here is the new version – your change was not saved.';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldDescription => 'Description';

  @override
  String get fieldVisibility => 'Visibility';

  @override
  String get visibilityPrivate => 'Private';

  @override
  String get visibilityUnlisted => 'Anyone with the link';

  @override
  String get visibilityPublic => 'Public';

  @override
  String get visibilityNeedsVerify => 'Confirm your e-mail address to publish routes.';

  @override
  String get tagsLabel => 'Tags';

  @override
  String get tagsHint => 'Separated by commas';

  @override
  String ownerBy(String user) {
    return 'by $user';
  }

  @override
  String get shareAction => 'Share';

  @override
  String get shareLink => 'Share link';

  @override
  String get shareSend => 'Send link …';

  @override
  String get shareCopied => 'Copied';

  @override
  String get shareLinkHint => 'Choose «Anyone with the link» or «Public» to send a link.';

  @override
  String get shareRotate => 'Create a new link';

  @override
  String get shareRotateHint => 'The previous link stops working.';

  @override
  String get sharePeople => 'Share with people';

  @override
  String get sharePending => 'invited';

  @override
  String get shareRemove => 'Remove access';

  @override
  String get shareWho => 'Username or e-mail address';

  @override
  String get shareInvite => 'Invite';

  @override
  String get shareHint => 'Invitees get an e-mail. Anyone without an account signs up with that address.';

  @override
  String get shareNeedsVerify => 'Confirm your e-mail address to share with others.';

  @override
  String get shareRate => 'Too many invitations – try again later.';

  @override
  String get shareNoUser => 'There is no user with this name.';

  @override
  String get shareSelf => 'You cannot invite yourself.';

  @override
  String get shareTooMany => 'Too many people have access already.';

  @override
  String get shareBadEmail => 'Invalid e-mail address.';

  @override
  String get roleViewer => 'Can view';

  @override
  String get roleEditor => 'Can plan';

  @override
  String get sharedTitle => 'Shared with me';

  @override
  String get gpxRoute => 'Share GPX …';

  @override
  String get gpxJourney => 'Share all stages as GPX (ZIP) …';

  @override
  String get photosTitle => 'Photos';

  @override
  String get photosAdd => 'Add photos';

  @override
  String get photosCamera => 'Take a photo';

  @override
  String get photosLibrary => 'From the library';

  @override
  String photosUploading(int done, int total) {
    return '$done of $total uploaded …';
  }

  @override
  String get photosHint =>
      'JPEG, PNG, WebP or HEIC up to 20 MB. We remove all metadata; photos taken along the route appear on the map.';

  @override
  String get photosProblemFormat => 'not a JPEG, PNG, WebP or HEIC image';

  @override
  String get photosProblemSize => 'too large (at most 20 MB)';

  @override
  String get photosProblemLimit => 'too many photos (at most 100 per hike and 1000 per person)';

  @override
  String get photosProblemRate => 'too many uploads – please try again in a moment';

  @override
  String get photosProblemOther => 'upload failed';

  @override
  String get photosCaption => 'Caption';

  @override
  String photosBy(String user) {
    return 'by $user';
  }

  @override
  String get photosDelete => 'Delete';

  @override
  String get photosDeleteConfirm => 'Really delete?';

  @override
  String get communityLike => 'Like';

  @override
  String communityLikes(int n) {
    return 'liked $n times';
  }

  @override
  String communityComments(int n) {
    return '$n comments';
  }

  @override
  String get communityCommentsAllowed => 'Allow comments';

  @override
  String get communityCommentsOff => 'Comments are switched off.';

  @override
  String get communityCommentPlaceholder => 'Write a comment …';

  @override
  String get communityCommentSend => 'Comment';

  @override
  String get communityReply => 'Reply';

  @override
  String get communityReplyPlaceholder => 'Your reply …';

  @override
  String get communityEdited => 'edited';

  @override
  String get communityRate => 'That was too fast – please try again in a moment.';

  @override
  String get communityVerifyToComment => 'Confirm your e-mail address to comment.';

  @override
  String get stageEdit => 'Edit stage';

  @override
  String get stageDate => 'Date';

  @override
  String get stageDateNone => 'No date';

  @override
  String get stageStatus => 'Status';

  @override
  String get statusPlanned => 'Planned';

  @override
  String get stageAccommodationLabel => 'Accommodation';

  @override
  String get stageAccommodationPlaceholder => 'e.g. Gasthaus Alpenhof';

  @override
  String get stageBookedLabel => 'Booked';

  @override
  String get stageNotes => 'Notes';

  @override
  String get stageTransfer => 'Covered by';

  @override
  String get transferNone => '–';

  @override
  String get sbbToStart => 'SBB timetable: getting there';

  @override
  String get sbbFromEnd => 'SBB timetable: getting home';

  @override
  String get sbbTransfer => 'SBB timetable';

  @override
  String get connectionsShow => 'Show connections';

  @override
  String get connectionsDepart => 'Dep';

  @override
  String get connectionsArrive => 'Arr';

  @override
  String get connectionsSearch => 'Search';

  @override
  String get connectionsNone => 'No connection found.';

  @override
  String get connectionsUnavailable => 'The timetable is not available right now – use the SBB timetable.';

  @override
  String connectionsTransfers(int n) {
    return '$n changes';
  }

  @override
  String connectionsWalk(int min) {
    return '$min min walk';
  }

  @override
  String connectionsPlatform(String p) {
    return 'platform $p';
  }

  @override
  String get connectionsSource => 'Timetable data: opentransportdata.swiss';

  @override
  String get collectionsTitle => 'Collections';

  @override
  String get collectionsIntro =>
      'Gather routes and journeys – as a wish list, for ideas, or to share. A collection grants no access: everyone sees only what they may open anyway.';

  @override
  String get collectionsEmpty => 'No collections yet.';

  @override
  String get collectionNew => 'New collection';

  @override
  String collectionItemsCount(int n) {
    return '$n items';
  }

  @override
  String get collectionEmpty => 'Still empty. Add routes and journeys from their menu: «Add to collection …».';

  @override
  String get collectionAddTo => 'Add to collection …';

  @override
  String collectionAdded(String title) {
    return 'Added to “$title”';
  }

  @override
  String collectionAlready(String title) {
    return 'Already in “$title”';
  }

  @override
  String get collectionRemoveItem => 'Remove';

  @override
  String get collectionDelete => 'Delete collection';

  @override
  String get collectionDeleteConfirm => 'Delete the collection? Routes and journeys stay.';

  @override
  String collectionStages(int n) {
    return '$n stages';
  }

  @override
  String get myMapKindHike => 'Hiked';

  @override
  String get connectionsFromHere => 'Connections from here to the start';

  @override
  String get connectionsNoPosition => 'Your location is not known. Allow Alvyo to use it in the iPhone settings.';

  @override
  String get stageMore => 'Details and getting there';

  @override
  String get travelTitle => 'Getting there and back';

  @override
  String get travelTo => 'Getting there';

  @override
  String get travelBack => 'Getting home';

  @override
  String get travelFrom => 'From';

  @override
  String get travelToHome => 'To';

  @override
  String get travelNone => '– none –';

  @override
  String travelOn(String date) {
    return 'on $date';
  }

  @override
  String get travelNoDate => 'The stage has no date: today’s connections.';

  @override
  String get travelNoHomes => 'Add a home you often need in your account.';

  @override
  String get travelPrivate => 'Only you see how you get there and back.';

  @override
  String get travelNoRoute => 'Once a stage has a route.';

  @override
  String get travelChoose => 'From where and when';

  @override
  String get homesTitle => 'Homes';

  @override
  String get homesIntro =>
      'From here you plan getting to your journeys and home again by public transport. At most 5; only you see them.';

  @override
  String get homesName => 'Name';

  @override
  String get homesNamePlaceholder => 'e.g. Home, Office';

  @override
  String get homesAddress => 'Search an address …';

  @override
  String get homesAdd => 'Add';

  @override
  String get homesRemove => 'Remove';

  @override
  String get homesFull => 'At most 5 homes.';

  @override
  String get travelStart => 'Start of the journey';

  @override
  String get travelEnd => 'End of the journey';

  @override
  String get recordTitle => 'Hike';

  @override
  String get recordStart => 'Start recording';

  @override
  String get recordRefused =>
      'Not saved: the hike is too short or goes more than 15 km beyond Switzerland and Liechtenstein.';

  @override
  String get barRoutes => 'Routes';

  @override
  String get barJourneys => 'Journeys';

  @override
  String get planAction => 'Plan';

  @override
  String get routePrivacyOwner => 'Others see this hike without its first and last 500 m.';

  @override
  String get routePrivacyOthers => 'The start and end of the hike are hidden.';

  @override
  String get routePrivacyAll => 'This hike is too short to show to others: its start and end are hidden.';

  @override
  String plannerAlpineShorter(String alpine, String hike) {
    return 'With “Alpine hiking” only $alpine instead of $hike.';
  }

  @override
  String plannerAlpineGrade(String grade) {
    return 'The shorter way leads over $grade.';
  }

  @override
  String get plannerAlpineUse => 'Plan this part as alpine';

  @override
  String get plannerAlpineUsed => 'Planned with “Alpine hiking”.';

  @override
  String get plannerAlpineUndo => 'Back to hiking';

  @override
  String get noticesTitle => 'Closures and shooting';

  @override
  String get noticesClosure => 'trail closed';

  @override
  String get noticesShooting => 'army shooting';

  @override
  String get mapPois => 'Along the way: summits, views, water';

  @override
  String get poiPeak => 'Summit';

  @override
  String get poiViewpoint => 'Viewpoint';

  @override
  String get poiWaterfall => 'Waterfall';

  @override
  String get poiWater => 'Drinking water';

  @override
  String get poiShelter => 'Shelter';

  @override
  String get poisTitle => 'Along the way';

  @override
  String poisAll(int count) {
    return 'Show all $count';
  }

  @override
  String get weatherTitle => 'Weather';

  @override
  String get weatherStart => 'Start';

  @override
  String get weatherTop => 'Highest point';

  @override
  String get weatherEnd => 'End';

  @override
  String get weatherToday => 'Today';

  @override
  String get weatherDry => 'dry';

  @override
  String weatherRain(String mm, String lo, String hi) {
    return '$mm mm precipitation ($lo–$hi mm)';
  }

  @override
  String weatherSource(String time) {
    return 'MeteoSwiss forecast for the nearby place of the most similar height, of $time.';
  }

  @override
  String weatherStage(int n, String date) {
    return 'Stage $n, $date';
  }

  @override
  String get travelElsewhere => 'Another place …';

  @override
  String get travelPlaceSearch => 'Place, stop or address';

  @override
  String get travelDay => 'On';

  @override
  String get travelRouteStart => 'Start';

  @override
  String get travelRouteEnd => 'End';
}
