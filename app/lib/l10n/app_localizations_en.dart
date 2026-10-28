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
  String get errorNotFound => 'This doesn’t exist (any more): it may have been deleted or made private.';

  @override
  String get errorServer => 'The server cannot be reached.';

  @override
  String get routesTitle => 'My routes';

  @override
  String get routesEmpty => 'No routes yet. Plan them on the website.';

  @override
  String get logout => 'Log out';

  @override
  String get loginUnverified => 'Confirm your e-mail address first. We sent you a new link.';

  @override
  String get appleContinue => 'Continue with Apple';

  @override
  String get appleExists =>
      'An account with this e-mail address exists already. Log in with your password and connect Apple on the website under «Account».';

  @override
  String get logoutOthers => 'Log out on all other devices';

  @override
  String get logoutOthersDone => 'The other devices are logged out.';

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
  String get navPause => 'Pause';

  @override
  String get navUnpause => 'Carry on';

  @override
  String get navPaused => 'Paused: nothing is being recorded';

  @override
  String get navNoPermission => 'This needs your location. Allow it in Settings.';

  @override
  String get gpsOff => 'Location is switched off: turn it on in Settings.';

  @override
  String get recordSaveFailed => 'The recording cannot be saved. Is the phone’s storage full?';

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
  String get watchImportAgain => 'Again';

  @override
  String get watchAgainTitle => 'Already imported';

  @override
  String get watchAgainBody => 'Import it again as a new route? The existing one stays as it is.';

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
  String labelled(String label, String value) {
    return '$label: $value';
  }

  @override
  String elevationSummary(String length, String low, String high) {
    return 'Elevation profile: $length, from $low to $high';
  }

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
  String get mapMyLocation => 'My location';

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
  String get accountPace => 'Your pace';

  @override
  String get accountPaceHint =>
      'Hiking times as a percentage of the times on the yellow signposts: below 100 % you are faster, above it slower.';

  @override
  String get accountPaceSignposts => '100 % – as the signposts';

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
  String get feedIntro =>
      'What your friends hike and publish, new hikes of the people you follow, and comments on your hikes.';

  @override
  String get feedEmpty => 'Nothing yet. Add friends or follow people whose hikes interest you.';

  @override
  String get feedMore => 'Load older';

  @override
  String get feedHiked => 'went hiking';

  @override
  String get feedPublishedRoute => 'published a route';

  @override
  String get feedPublishedJourney => 'published a journey';

  @override
  String get feedCommented => 'commented';

  @override
  String get feedHikePrivate => 'A route of their own';

  @override
  String profileSince(String date) {
    return 'member since $date';
  }

  @override
  String get profileStatFollowers => 'Followers';

  @override
  String get profileStatFollowing => 'Following';

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
  String collectionHidden(int n) {
    return 'Private items you cannot see: $n';
  }

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
  String collectionRemoveConfirm(String title) {
    return 'Remove “$title” from the collection? The route or journey itself stays.';
  }

  @override
  String get collectionDelete => 'Delete collection';

  @override
  String get collectionDeleteConfirm => 'Delete the collection? Routes and journeys stay.';

  @override
  String get collectionMap => 'Map of the collection';

  @override
  String collectionStages(int n) {
    return '$n stages';
  }

  @override
  String get myMapKindHike => 'Hiked';

  @override
  String get connectionsFromHere => 'Connections from here to the start';

  @override
  String get connectionsNoPosition => 'Your location is not known. Allow Alvyo to use it in the phone’s settings.';

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
  String get mapPois => 'Along the way';

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
  String get mapBase => 'Base map';

  @override
  String get mapOverlays => 'Overlays';

  @override
  String get mapBaseNational => 'National map';

  @override
  String get mapBaseGrey => 'National map grey';

  @override
  String get mapBaseAerial => 'Aerial imagery';

  @override
  String get mapOverlayTrails => 'Hiking trails';

  @override
  String get mapOverlayWanderland => 'SwitzerlandMobility hiking routes';

  @override
  String get mapOverlaySlope => 'Slopes over 30°';

  @override
  String get mapOverlayRestAreas => 'Wildlife rest areas';

  @override
  String get mapOverlayHuntingReserves => 'Federal hunting reserves';

  @override
  String get mapOverlayRelief => 'Hillshade';

  @override
  String get mapOverlayPrecip => 'Rain (radar and forecast)';

  @override
  String get precipRadar => 'Radar, measured';

  @override
  String get precipForecast => 'Model forecast';

  @override
  String get precipPlay => 'Play';

  @override
  String get precipPause => 'Pause';

  @override
  String get precipNone => 'No rain data at the moment.';

  @override
  String get precipLight => 'light';

  @override
  String get precipHeavy => 'heavy';

  @override
  String get mapOverlaySnow => 'Snow (satellite)';

  @override
  String snowDate(String date) {
    return 'Snow cover on $date';
  }

  @override
  String get snowNone => 'No snow data yet.';

  @override
  String get snowNote => 'Satellite, 60 m; up to 7 days old under clouds';

  @override
  String get snowPatchy => 'patches';

  @override
  String get snowMostly => 'mostly';

  @override
  String get snowFull => 'complete';

  @override
  String get snowHint =>
      'Shows where snow lies, not how deep it is or whether the trail is passable. The BFU advises planning hikes so as not to meet snow fields, and turning back when in doubt.';

  @override
  String get snowMore => 'More about it';

  @override
  String get snowLess => 'Less';

  @override
  String get showOnMap => 'Show on the map';

  @override
  String get snowAlongTitle => 'Snow on the way';

  @override
  String snowAlongNote(String snow) {
    return '$snow of snow';
  }

  @override
  String snowAlongNoteSteep(String snow, String steep) {
    return '$snow of snow, $steep steep';
  }

  @override
  String snowAlongSummary(String snow) {
    return 'Crosses $snow of snow.';
  }

  @override
  String snowAlongSummarySteep(String snow, String steep) {
    return 'Crosses $snow of snow, $steep of it steeper than 30°.';
  }

  @override
  String snowAlongPatches(String distance) {
    return 'Patches of snow on another $distance.';
  }

  @override
  String snowAlongPatchesOnly(String distance, String date) {
    return 'Patches of snow on $distance, as of $date.';
  }

  @override
  String snowAlongStretch(String at, String length) {
    return 'After $at: $length of snow';
  }

  @override
  String snowAlongStretchSteep(String steep) {
    return '$steep of it steeper than 30°';
  }

  @override
  String get snowAlongLimits =>
      'Satellite, 60 m; up to 7 days old under clouds. A short snow field can be missing; depth and hardness are not shown. Steep means terrain steeper than 30° (swissALTI3D, Switzerland only).';

  @override
  String get poiFirepit => 'Fire place';

  @override
  String get poiPicnic => 'Picnic spot';

  @override
  String get poiRestaurant => 'Restaurant, café';

  @override
  String get poiToilets => 'Toilets';

  @override
  String get poiCablecar => 'Cable car station';

  @override
  String get poisTitle => 'Along the way';

  @override
  String get routeTabOverview => 'Overview';

  @override
  String get routeTabTravel => 'Getting there';

  @override
  String get journeyTabStages => 'Stages';

  @override
  String get statTime => 'Hiking time';

  @override
  String get statDistance => 'Distance';

  @override
  String get statHeights => 'Ascent/descent';

  @override
  String get statSac => 'Difficulty';

  @override
  String poisFilterAll(int count) {
    return 'All $count';
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
  String get weatherTomorrow => 'Tomorrow';

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

  @override
  String get areasNow => 'applies now';

  @override
  String get areasOnDate => 'applies on a planned day';

  @override
  String hintsOpen(int count) {
    return 'Show $count';
  }

  @override
  String get weatherOtherDay => 'Another date';

  @override
  String weatherClimate(String month, String min, String max, String days, String total, String mm) {
    return 'Usual in $month: $min–$max °C, rain on $days of $total days, $mm mm in the month';
  }

  @override
  String weatherClimateSource(String station, String rain) {
    return 'No forecast for this day yet: MeteoSwiss climate normals 1991–2020 (temperature: $station, adjusted to the height; precipitation: $rain). The forecast covers the next 9 days.';
  }

  @override
  String get journeyMap => 'Map of the journey';

  @override
  String get journeyAddStage => 'Add stage';

  @override
  String get routeEditLine => 'Change on the map';

  @override
  String get bugOpen => 'Report a bug';

  @override
  String get bugWhat => 'What happened? What did you expect?';

  @override
  String get bugWithScreenshot => 'Send a screenshot';

  @override
  String get bugScreenshotAlt => 'Screenshot of this page';

  @override
  String bugPrivacy(String place) {
    return 'The report becomes an issue in a private GitHub repository that only the Alvyo team can see: your text, the address ($place), the version, your username and the screenshot.';
  }

  @override
  String get bugSend => 'Send';

  @override
  String get bugSent => 'Thank you! The bug is reported.';

  @override
  String get bugFailed => 'That did not work. Please try again later.';

  @override
  String get bugBusy => 'You have reported several bugs today already. Please try again later.';

  @override
  String get close => 'Close';

  @override
  String get peopleTitle => 'Who comes along';

  @override
  String get peopleNone => 'Nobody yet. Those who come along see the journey and the stages they are on.';

  @override
  String get peopleInvited => 'Invited';

  @override
  String get peopleRemove => 'Not coming';

  @override
  String get peopleWho => 'Username or e-mail address';

  @override
  String get peopleAdd => 'Add';

  @override
  String get peopleHint =>
      'Someone without access yet is invited and can view the journey. The numbers are the stages: tap who is on which.';

  @override
  String get peopleUnknown => 'There is no such person, or it is you.';

  @override
  String get peopleVerify => 'Confirm your e-mail address first.';

  @override
  String get peopleFailed => 'That did not work. Please try again.';

  @override
  String peopleOnStage(String names) {
    return 'With $names';
  }

  @override
  String peopleStages(String name) {
    return 'Stages of $name';
  }

  @override
  String get remindersTitle => 'Reminders';

  @override
  String get remindersOn => 'Reminders by e-mail before the start';

  @override
  String get remindersHint => 'For you and everyone coming along; in the app also on the phone.';

  @override
  String get reminderBook => 'It starts in three weeks: are all nights booked?';

  @override
  String get reminderWeather => 'It starts the day after tomorrow: have a look at the weather.';

  @override
  String get reminderStart => 'It starts tomorrow. Have a good hike!';

  @override
  String get friendsTitle => 'Friends';

  @override
  String get friendsSearch => 'Find people';

  @override
  String get friendsSearchHint => 'Username or name; only public profiles are found.';

  @override
  String get friendsNoneFound => 'Nobody found.';

  @override
  String get friendsIncoming => 'Requests to you';

  @override
  String get friendsOutgoing => 'Your requests';

  @override
  String get friendsList => 'Your friends';

  @override
  String get friendsEmpty => 'No friends yet. Find people or send your invite link.';

  @override
  String get friendAdd => 'Add as friend';

  @override
  String get friendRequested => 'Request sent';

  @override
  String get friendWithdraw => 'Withdraw';

  @override
  String get friendAccept => 'Accept';

  @override
  String get friendDecline => 'Decline';

  @override
  String get friendFriends => 'Friends';

  @override
  String get friendRemove => 'Unfriend';

  @override
  String get friendsLinkTitle => 'Your invite link';

  @override
  String get friendsLinkHint =>
      'Whoever opens this link becomes your friend – even when your profile is private. Send it only to people you know.';

  @override
  String get friendsLinkShare => 'Send the link';

  @override
  String get friendsLinkRenew => 'Make a new link';

  @override
  String get profilePublic => 'Public profile';

  @override
  String get profilePublicHint => 'Others find you in the search. A private profile is seen by your friends only.';

  @override
  String get shareHikes => 'Share hikes with friends';

  @override
  String get shareHikesHint => 'Your friends see in their news when you went hiking, with distance and time.';

  @override
  String get doneMark => 'Mark as hiked';

  @override
  String get doneRemove => 'Not hiked';

  @override
  String get doneByHike => 'recorded';

  @override
  String get doneByStages => 'all stages done';

  @override
  String get doneFilterAll => 'All';

  @override
  String get doneFilterPlanned => 'Planned';

  @override
  String get doneFilterDone => 'Hiked';

  @override
  String get doneFilterNone => 'Nothing in this selection.';

  @override
  String doneOn(String date) {
    return 'Hiked on $date';
  }

  @override
  String get breakdownTitle => 'Trail conditions';

  @override
  String get breakdownTrail => 'Trail network';

  @override
  String get breakdownSurface => 'Surface';

  @override
  String get breakdownWay => 'Way type';

  @override
  String get breakdownOther => 'Other';

  @override
  String get breakdownDetails => 'Details in km';

  @override
  String get trailWanderweg => 'Hiking trail';

  @override
  String get trailBergwanderweg => 'Mountain trail';

  @override
  String get trailAlpinwanderweg => 'Alpine trail';

  @override
  String get trailNone => 'No official trail';

  @override
  String get surfacePaved => 'Paved';

  @override
  String get surfaceGravel => 'Gravel';

  @override
  String get surfaceNatural => 'Natural';

  @override
  String get surfaceUnknown => 'Unknown';

  @override
  String get wayRoad => 'Road';

  @override
  String get wayTrack => 'Track';

  @override
  String get wayPath => 'Path';

  @override
  String get waySteps => 'Steps';

  @override
  String get wayUnknown => 'Unknown';

  @override
  String get offTrailTitle => 'No official trail';

  @override
  String offTrailAll(String distance) {
    return 'The whole route ($distance) runs off marked hiking trails.';
  }

  @override
  String inviteTitle(String name) {
    return '$name invites you';
  }

  @override
  String get inviteText => 'Become friends on Alvyo: you see each other\'s profiles, private ones too.';

  @override
  String get inviteAccept => 'Become friends';

  @override
  String get inviteDone => 'You are friends now.';

  @override
  String get inviteInvalid => 'This invite link is no longer valid.';

  @override
  String get inviteSelf => 'This is your own link.';

  @override
  String get reachTitle => 'How far can I get?';

  @override
  String get reachBackHint => 'There and back, uphill and downhill each with its own time';

  @override
  String get importFile => 'File (GPX, KML, TCX, FIT)';

  @override
  String get importFileHint => 'Becomes a private route';

  @override
  String get importNotTrack => 'This file contains no track Alvyo can read (GPX, KML, TCX or FIT).';

  @override
  String reachWithinBack(int hours) {
    return 'up to $hours hours, there and back';
  }

  @override
  String get plannerVia => 'Stop';

  @override
  String get plannerSearchVia => 'Search a stop …';

  @override
  String get plannerRoundTrip => 'Round trip';

  @override
  String get plannerReturn => 'Back to the start';

  @override
  String get recordFollow => 'Follow a tour (optional)';

  @override
  String get recordChooseTour => 'Choose a tour';

  @override
  String get recordWithoutTour => 'Without a tour';

  @override
  String get recordNoTours => 'No planned tours yet. Plan one under «Plan».';

  @override
  String get devicesTitle => 'Connected devices';

  @override
  String get devicesSubtitle => 'Apple Watch · import tours automatically';

  @override
  String get devicesWatch => 'Apple Watch';

  @override
  String get devicesWatchHint => 'Hikes from the Workout app, through Apple Health';

  @override
  String get devicesWatchAuto => 'Import new hikes automatically';

  @override
  String get devicesWatchAutoHint => 'When you open the app – hikes from now on';

  @override
  String get devicesWatchPick => 'Choose hikes and import them';

  @override
  String get profileAccount => 'Account';

  @override
  String get accountPaceShort => 'Hiking times relative to the signposts';

  @override
  String devicesWatchImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hikes imported from the Apple Watch',
      one: '1 hike imported from the Apple Watch',
    );
    return '$_temp0';
  }

  @override
  String get importTitle => 'Import';

  @override
  String get importAction => 'Import';

  @override
  String get importWatchHint => 'Hikes you recorded with your watch';

  @override
  String get planDay => 'Day tour';

  @override
  String get planMulti => 'Several days';

  @override
  String get planReach => 'Reach';

  @override
  String get discoverSearchHint => 'Search a place or summit';

  @override
  String get discoverSearchNone => 'Nothing found. Try another name.';

  @override
  String get discoverReachHint => 'Reach from where you are';

  @override
  String get discoverPeaks => 'Look at summits';

  @override
  String get discoverPeaksHint => 'Camera on the horizon';

  @override
  String get discoverFollowing => 'News';

  @override
  String get discoverAll => 'All';

  @override
  String get discoverFollowingEmpty => 'Nothing yet. Add friends or follow people whose hikes interest you.';

  @override
  String get discoverNearby => 'Near you';

  @override
  String get discoverNearbyNoPosition => 'Allow the location to see tours near you.';

  @override
  String get discoverNearbyAllow => 'Allow location';

  @override
  String get discoverNearbyUnknown =>
      'Your location is not known right now. Outdoors or with Wi-Fi the phone usually finds it faster.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get discoverNearbyEmpty => 'No tour has been published around you yet. You find more on the map.';

  @override
  String get toursTitle => 'Tours';

  @override
  String get toursMap => 'Map';

  @override
  String get toursList => 'List';

  @override
  String get toursJourneys => 'Journeys';

  @override
  String get toursShared => 'Shared';

  @override
  String get toursEmptyPlanned => 'No planned tours yet. Plan a route or a journey – it then appears here.';

  @override
  String get toursEmptyHiked => 'Nothing hiked yet. Record your next hike – it then appears here.';

  @override
  String get toursPlanAction => 'Plan a tour';

  @override
  String get barDiscover => 'Discover';

  @override
  String get barPlan => 'Plan';

  @override
  String get barTours => 'Tours';

  @override
  String get tourRoute => 'Route';

  @override
  String get tourJourney => 'Journey';

  @override
  String get tourSharedBy => 'shared by';

  @override
  String get tourBy => 'by';

  @override
  String get peaksTitle => 'Name the mountains';

  @override
  String get peaksDownloadText =>
      'To name the summits in the camera view, the app needs the heights of Switzerland and around it with all summits once (about 9 MB). After that it also works without reception.';

  @override
  String get peaksDownload => 'Download';

  @override
  String get peaksDownloadFailed => 'The download failed. Please try again.';

  @override
  String get peaksPreparing => 'Being prepared …';

  @override
  String get peaksComputing => 'Working out what you see from here …';

  @override
  String get peaksNoPosition => 'Where you are is not known: allow the location.';

  @override
  String get peaksNoCamera => 'Alvyo may not use the camera: allow it in Settings.';

  @override
  String get peaksNoCompass => 'This device has no compass.';

  @override
  String get peaksCompass => 'Compass inaccurate: move the phone in a figure eight a few times.';

  @override
  String get peaksAlign => 'If the line does not match the horizon, drag it there with your finger.';

  @override
  String get peaksReset => 'Reset';

  @override
  String peaksDirection(int azimuth, int elevation) {
    return 'Direction $azimuth° · tilt $elevation°';
  }

  @override
  String get reachAction => 'Reach';

  @override
  String get reachIntro =>
      'Tap the map, search for a place or use where you are: the areas show how far you get from there in 2, 4 and 8 hours, at your pace and with every climb and descent.';

  @override
  String get reachSearch => 'Search for a start';

  @override
  String get reachHere => 'Where I am';

  @override
  String get reachNoPosition => 'Your position is not known. Allow location in Settings or tap the map.';

  @override
  String reachStart(String place) {
    return 'Start: $place';
  }

  @override
  String get reachMapPoint => 'Point on the map';

  @override
  String get reachBusy => 'Working out how far you get …';

  @override
  String reachWithin(int hours) {
    return 'within $hours hours';
  }

  @override
  String get reachNote =>
      'Approximate: an area takes in everything reached, lakes and slopes without paths between them too. The times follow the Swiss hiking time by slope, without breaks.';

  @override
  String reachPace(String pace) {
    return 'At your pace: $pace times the signposts’ time.';
  }

  @override
  String get reachErrorNoPath => 'No path near this point. Choose a point on or near a path.';

  @override
  String get reachErrorBusy => 'Too many requests. Please wait a moment.';

  @override
  String get reachErrorOther => 'Could not be worked out. Please try again.';

  @override
  String get reachPlanHere => 'Plan a route here';

  @override
  String get reachStartHere => 'Start from here instead';

  @override
  String get reachPlanHint => 'Tap inside an area to plan a route there.';

  @override
  String officialNational(String number) {
    return 'National route $number';
  }

  @override
  String officialRegional(String number) {
    return 'Regional route $number';
  }

  @override
  String officialLocal(String number) {
    return 'Local route $number';
  }

  @override
  String officialHandicap(String number) {
    return 'Barrier-free route $number';
  }

  @override
  String get officialLink => 'on SwitzerlandMobility';

  @override
  String get officialSource => 'Official route of Hiking in Switzerland – data: FEDRO and SwitzerlandMobility';

  @override
  String get discoverOriginAll => 'Official routes and from people';

  @override
  String get discoverOriginOnly => 'Official routes only';

  @override
  String get discoverOriginNone => 'From people only';

  @override
  String get routeCopy => 'Edit as your own route';

  @override
  String get journeyCopy => 'Edit as your own journey';

  @override
  String get copyFailed => 'Copying did not work. Try again.';

  @override
  String get tokensOnWebsite => 'You manage access tokens for AI assistants on alvyo.tellbow.ch.';

  @override
  String get aboutTitle => 'About Alvyo';

  @override
  String get aboutIntro => 'Alvyo is an open platform for planning and sharing hikes in Switzerland.';

  @override
  String get aboutDataTitle => 'Data';

  @override
  String get aboutDataIntro =>
      'Alvyo shows data from these sources; thanks to everyone who makes them openly available:';

  @override
  String get aboutSrcSwisstopo =>
      'Federal Office of Topography swisstopo: national maps, aerial images, base map, swissALTI3D elevation model, relief, slopes and hiking trails (swissTLM3D)';

  @override
  String get aboutSrcAstra =>
      'Federal Roads Office FEDRO (ASTRA) and SchweizMobil: the official routes of Wanderland Schweiz, closures and diversions of hiking trails';

  @override
  String get aboutSrcBafu =>
      'Federal Office for the Environment FOEN (BAFU) and the cantons: wildlife rest areas and federal hunting reserves';

  @override
  String get aboutSrcVbs => 'Federal Department of Defence, Civil Protection and Sport DDPS (VBS): shooting notices';

  @override
  String get aboutSrcMeteo =>
      'Source: MeteoSwiss – weather forecasts, rain radar, precipitation forecast (ICON-CH1) and climate normals';

  @override
  String get aboutSrcCopernicus =>
      'Generated using European Union\'s Copernicus Land Monitoring Service information: snow cover (HR-WSI, daily, 60 m), coloured and cut to Switzerland by us';

  @override
  String get aboutSrcTransport => 'opentransportdata.swiss: timetable and connections (Open Journey Planner)';

  @override
  String get aboutSrcBav => 'Federal Office of Transport FOT (BAV): public transport stops';

  @override
  String get aboutSrcOsm =>
      '© OpenStreetMap contributors: the path network for routing, huts, accommodation, places and summits';

  @override
  String get aboutSrcMapterhorn =>
      'Mapterhorn (from Copernicus GLO-30, swissALTI3D and the neighbouring countries\' elevation models): terrain for the 3D map and «Name the mountains» in the app';

  @override
  String get aboutSrcTerrain =>
      'Terrain Tiles by Mapzen (EU-DEM: produced using Copernicus data and information funded by the European Union; SRTM: courtesy of the U.S. Geological Survey): slopes for «How far can I get?»';

  @override
  String get aboutSrcHikingtime => 'Hiking times after the formula of SchweizMobil / Swiss Hiking Trail Federation';

  @override
  String get aboutSafety =>
      'Hiking times and difficulties are computed estimates. Check weather, conditions and the signposts on site.';

  @override
  String get aboutCodeTitle => 'Source code and licences';

  @override
  String get aboutCode => 'Alvyo is free software under the AGPL-3.0.';

  @override
  String get aboutSourceLink => 'Source code on GitHub';

  @override
  String get aboutNoticeLink => 'Sources and licences of other people\'s code and data (NOTICE)';

  @override
  String get aboutLicenses => 'Licences of this app\'s components';

  @override
  String get aboutPrivacy => 'Privacy';

  @override
  String get aboutPrivacyHint => 'What we store and where data goes – on the website';

  @override
  String get aboutOperator => 'Operator and contact';

  @override
  String get mapCreditLabel => 'Map sources';

  @override
  String get peaksCredit => 'Terrain: Mapterhorn · Summits: © OpenStreetMap contributors';

  @override
  String get gpsServiceTitle => 'Hike in progress';

  @override
  String get gpsServiceText => 'Alvyo follows your location, also with the screen locked.';

  @override
  String get channelReminders => 'Journey reminders';

  @override
  String get signupUsername => 'Username';

  @override
  String get signupUsernameHint => '3–30 characters: lowercase letters, digits and _';

  @override
  String get signupUsernameTaken => 'This username is taken.';

  @override
  String get signupDisplayName => 'Display name';

  @override
  String get signupDisplayNameMissing => 'Enter a name.';

  @override
  String get signupPasswordHint => 'At least 10 characters';

  @override
  String signupSent(String email) {
    return 'Almost there: we sent an e-mail to $email. Confirm your address in it, then you can log in here. If you already have an account, the e-mail says how to get in.';
  }

  @override
  String get errorTooMany => 'Too many attempts. Please wait a moment.';

  @override
  String get statisticsTitle => 'Statistics';

  @override
  String get statisticsAsk =>
      'May we measure with Google Analytics which parts of the app are used? Google learns only the kind of screen (such as «Route»), no titles, places or links, and no advertising ID. Without your consent Google receives nothing.';

  @override
  String get statisticsAccept => 'Accept';

  @override
  String get statisticsDecline => 'Decline';

  @override
  String get statisticsGranted => 'Accepted';

  @override
  String get statisticsDenied => 'Declined';
}
