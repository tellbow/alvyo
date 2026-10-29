// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Alvyo';

  @override
  String get loginTitle => 'Se connecter';

  @override
  String get server => 'Serveur';

  @override
  String get login => 'E-mail ou nom d\'utilisateur';

  @override
  String get password => 'Mot de passe';

  @override
  String get loginSubmit => 'Se connecter';

  @override
  String get loginInvalid => 'E-mail/nom d\'utilisateur ou mot de passe incorrect.';

  @override
  String get errorGeneric => 'Quelque chose n\'a pas fonctionné. Merci de réessayer.';

  @override
  String get errorNotFound => 'Cela n’existe pas (ou plus) : peut-être supprimé ou rendu privé.';

  @override
  String get errorServer => 'Le serveur n\'est pas joignable.';

  @override
  String get routesTitle => 'Mes itinéraires';

  @override
  String get routesEmpty => 'Pas encore d\'itinéraires. Planifie-les sur le site.';

  @override
  String get logout => 'Se déconnecter';

  @override
  String get loginUnverified => 'Confirme d’abord ton adresse e-mail. Nous t’avons envoyé un nouveau lien.';

  @override
  String get appleContinue => 'Continuer avec Apple';

  @override
  String get appleExists =>
      'Un compte avec cette adresse e-mail existe déjà. Connecte-toi avec ton mot de passe et lie Apple sur le site web sous « Compte ».';

  @override
  String get logoutOthers => 'Se déconnecter sur tous les autres appareils';

  @override
  String get logoutOthersDone => 'Les autres appareils sont déconnectés.';

  @override
  String get offlineSave => 'Enregistrer hors ligne';

  @override
  String get offlineSaved => 'Enregistré hors ligne – supprimer';

  @override
  String get offlinePreparing => 'Préparation de la carte hors ligne …';

  @override
  String get offlineDownloading => 'Téléchargement de la carte hors ligne …';

  @override
  String get offlineOutdated => 'Itinéraire modifié – mettre à jour la carte hors ligne';

  @override
  String get offlineFailed => 'La carte hors ligne n\'a pas pu être enregistrée.';

  @override
  String get routesOffline => 'Hors ligne – itinéraires enregistrés uniquement';

  @override
  String get navStart => 'Commencer la randonnée';

  @override
  String get navResume => 'Reprendre la randonnée';

  @override
  String get navDone => 'Parcouru';

  @override
  String get navRemaining => 'Reste';

  @override
  String get navElapsed => 'En route';

  @override
  String navOffRoute(int metres) {
    return 'À $metres m de l\'itinéraire';
  }

  @override
  String get navOffRouteTitle => 'Hors de l\'itinéraire';

  @override
  String get navArrived => 'Arrivée atteinte';

  @override
  String get navWaiting => 'En attente du GPS …';

  @override
  String get navFinish => 'Terminer';

  @override
  String get navFinishQuestion => 'Terminer la randonnée et enregistrer le tracé ?';

  @override
  String get navContinue => 'Continuer';

  @override
  String get navPause => 'Pause';

  @override
  String get navUnpause => 'Reprendre';

  @override
  String get navPaused => 'En pause : rien n\'est enregistré';

  @override
  String get navNoPermission => 'L\'app a besoin de ta position. Autorise-la dans les réglages.';

  @override
  String get gpsOff => 'La localisation est désactivée : active-la dans les réglages.';

  @override
  String get recordSaveFailed =>
      'L’enregistrement ne peut pas être sauvegardé. La mémoire du téléphone est-elle pleine ?';

  @override
  String navSaved(String distance, String duration) {
    return 'Enregistré : $distance en $duration. Envoi dès que tu seras en ligne.';
  }

  @override
  String get navFollow => 'Suivre ma position';

  @override
  String navUploaded(String distance, String duration) {
    return 'Enregistré dans Mes itinéraires : $distance en $duration';
  }

  @override
  String routesHiked(String date) {
    return 'Randonnée du $date';
  }

  @override
  String get watchTitle => 'Depuis l\'Apple Watch';

  @override
  String get watchHike => 'Randonnée';

  @override
  String get watchWalk => 'Marche';

  @override
  String get watchImport => 'Importer';

  @override
  String get watchImported => 'Importé – dans Mes itinéraires';

  @override
  String get watchImportAgain => 'À nouveau';

  @override
  String get watchAgainTitle => 'Déjà importé';

  @override
  String get watchAgainBody => 'L\'importer à nouveau comme nouvel itinéraire ? L\'existant reste tel quel.';

  @override
  String get watchNoTrack => 'Cet entraînement n\'a pas de tracé GPS.';

  @override
  String get watchEmpty =>
      'Aucune randonnée des 60 derniers jours dans Apple Health. Enregistre-les avec l\'app Exercice de l\'Apple Watch («Randonnée» ou «Marche en extérieur»). Si tu n\'as pas autorisé l\'accès : Réglages → Apps → Santé → Accès aux données et appareils → Alvyo.';

  @override
  String get watchUnavailable => 'Apple Santé n\'est pas disponible sur cet appareil.';

  @override
  String watchOutside(String reason) {
    return 'Non importé : $reason';
  }

  @override
  String get watchReasonOutside => 'il va à plus de 15 km au-delà de la Suisse et du Liechtenstein.';

  @override
  String get watchReasonShort => 'il est trop court.';

  @override
  String get turnSharpLeft => 'Tourne fortement à gauche';

  @override
  String get turnLeft => 'Tourne à gauche';

  @override
  String get turnSlightLeft => 'Tourne légèrement à gauche';

  @override
  String get turnKeepLeft => 'Reste à gauche';

  @override
  String get turnUTurn => 'Fais demi-tour';

  @override
  String get turnSlightRight => 'Tourne légèrement à droite';

  @override
  String get turnRight => 'Tourne à droite';

  @override
  String get turnSharpRight => 'Tourne fortement à droite';

  @override
  String get turnKeepRight => 'Reste à droite';

  @override
  String turnIn(int metres, String turn) {
    return 'Dans $metres mètres, $turn';
  }

  @override
  String get navVoiceOn => 'Active les annonces vocales';

  @override
  String get navVoiceOff => 'Désactive les annonces vocales';

  @override
  String get journeysTitle => 'Randonnées par étapes';

  @override
  String get journeysEmpty => 'Pas encore de randonnées par étapes. Planifie-les sur le site.';

  @override
  String get journeysOffline => 'Hors ligne – randonnées par étapes enregistrées uniquement';

  @override
  String journeyStagesCount(int done, int total) {
    return '$done étapes sur $total';
  }

  @override
  String journeyStage(int n) {
    return 'Étape $n';
  }

  @override
  String get journeyNoRoute => 'Pas encore d\'itinéraire';

  @override
  String get statusDone => 'Parcourue';

  @override
  String get statusSkipped => 'Sautée';

  @override
  String gapWarning(String distance) {
    return '$distance d\'écart avec la fin de l\'étape précédente';
  }

  @override
  String gapTransfer(String how) {
    return 'Reliée par $how';
  }

  @override
  String get transferPt => 'transports publics';

  @override
  String get transferCablecar => 'remontée mécanique';

  @override
  String get transferOther => 'autre moyen';

  @override
  String stageAccommodation(String name) {
    return 'Hébergement : $name';
  }

  @override
  String get stageBooked => 'réservé';

  @override
  String get journeySaveAll => 'Enregistrer toutes les étapes hors ligne';

  @override
  String journeySaving(int n, int total) {
    return 'Enregistrement de l\'étape $n sur $total …';
  }

  @override
  String get journeySaved => 'Toutes les étapes enregistrées hors ligne';

  @override
  String navSwitchQuestion(String title) {
    return 'Tu enregistres « $title ». Terminer cette randonnée et en commencer une nouvelle ici ? L\'enregistrement fait jusqu\'ici est conservé.';
  }

  @override
  String get navSwitch => 'Terminer et commencer ici';

  @override
  String get cancel => 'Annuler';

  @override
  String labelled(String label, String value) {
    return '$label : $value';
  }

  @override
  String elevationSummary(String length, String low, String high) {
    return 'Profil altimétrique : $length, de $low à $high';
  }

  @override
  String get stageMarkDone => 'Marquer comme faite';

  @override
  String get stageMarkPlanned => 'Marquer de nouveau comme prévue';

  @override
  String get navMarkStageDone => 'Marquer l\'étape comme faite';

  @override
  String get stageConflict => 'Quelqu\'un a modifié l\'étape entre-temps. Voici le nouvel état.';

  @override
  String get stageMarkedDone => 'Étape marquée comme faite';

  @override
  String get areasTitle => 'Zones protégées sur le chemin';

  @override
  String get areasWildlifeRest => 'zone de tranquillité';

  @override
  String get areasHuntingReserve => 'district franc fédéral';

  @override
  String get areasBinding => 'contraignant';

  @override
  String get areasRecommended => 'recommandé';

  @override
  String areasPeriod(String from, String to) {
    return 'du $from au $to';
  }

  @override
  String areasStages(String list) {
    return 'Étape $list';
  }

  @override
  String liveSharedUntil(String time) {
    return 'Position partagée · fin prévue à $time';
  }

  @override
  String get liveLater => 'Plus tard';

  @override
  String get liveLaterFailed => 'Il faut une connexion. Réessaie dans un instant.';

  @override
  String get liveShareTitle => 'Partager ta position';

  @override
  String get liveShareIntro =>
      'Les contacts choisis reçoivent un lien avec ta position. Si la randonnée n\'est pas terminée 30 minutes après la fin prévue, ils reçoivent un e-mail avec la dernière position.';

  @override
  String get liveShareEnd => 'Fin prévue';

  @override
  String get liveShareStart => 'Partager et partir';

  @override
  String get liveShareSkip => 'Sans partager';

  @override
  String get liveShareFailed => 'Le partage n\'a pas fonctionné ; la randonnée est tout de même enregistrée.';

  @override
  String get liveNoContacts => 'Ajoute des contacts sur le site web sous « Compte ».';

  @override
  String get navRecord => 'Enregistrer';

  @override
  String get navProfile => 'Profil';

  @override
  String get mapLayers => 'Cartes';

  @override
  String get mapMyLocation => 'Ma position';

  @override
  String get mapHuts => 'Cabanes';

  @override
  String get mapLodging => 'Hôtels et campings';

  @override
  String get placeHut => 'Cabane';

  @override
  String get placeHotel => 'Hébergement';

  @override
  String get placeCampsite => 'Camping';

  @override
  String get placeWildernessHut => 'Cabane non gardée';

  @override
  String get placePtStop => 'Arrêt TP';

  @override
  String get placeAddress => 'Adresse';

  @override
  String get placeWebsite => 'Site web';

  @override
  String get placeSearch => 'Chercher un lieu …';

  @override
  String get placeNothingFound => 'Rien trouvé.';

  @override
  String get plannerTitle => 'Planifier un itinéraire';

  @override
  String get plannerHint => 'Cherche le départ et l\'arrivée ou touche la carte.';

  @override
  String get plannerProfileHike => 'Randonnée (jusqu\'à T3)';

  @override
  String get plannerProfileAlpine => 'Randonnée alpine (jusqu\'à T6)';

  @override
  String get plannerPointMap => 'Point sur la carte';

  @override
  String get plannerUp => 'Vers le haut';

  @override
  String get plannerDown => 'Vers le bas';

  @override
  String get plannerRemove => 'Supprimer';

  @override
  String get plannerSearchStart => 'Chercher le départ …';

  @override
  String get plannerSearchEnd => 'Chercher l\'arrivée …';

  @override
  String get plannerSearchMore => 'Chercher une autre destination …';

  @override
  String get plannerLegNoPath => 'Pas de chemin à proximité. Supprime le point ou places-en un autre.';

  @override
  String get plannerLegFailed => 'Ce tronçon n\'a pas pu être calculé.';

  @override
  String get plannerRetry => 'Réessayer';

  @override
  String get plannerAddPlace => 'Ajouter comme point de l\'itinéraire';

  @override
  String get plannerSave => 'Enregistrer l\'itinéraire';

  @override
  String get plannerRouteTitle => 'Titre';

  @override
  String get plannerSaveConfirm => 'Enregistrer';

  @override
  String get plannerSaveFailed => 'L\'enregistrement a échoué.';

  @override
  String get discoverAction => 'Découvrir';

  @override
  String get discoverTitle => 'Découvrir des randonnées';

  @override
  String get discoverKindAll => 'Itinéraires et randonnées par étapes';

  @override
  String get discoverKindRoute => 'Itinéraires seulement';

  @override
  String get discoverKindJourney => 'Randonnées par étapes seulement';

  @override
  String get discoverSacAny => 'Toute difficulté';

  @override
  String discoverSacMax(String grade) {
    return 'jusqu\'à $grade';
  }

  @override
  String get discoverDurationAny => 'Tout temps de marche';

  @override
  String get discoverDurationShort => 'jusqu\'à 2 h';

  @override
  String get discoverDurationMedium => '2–4 h';

  @override
  String get discoverDurationLong => '4–6 h';

  @override
  String get discoverDurationXlong => 'plus de 6 h';

  @override
  String get discoverDurationHint => 'Pour les randonnées par étapes, c\'est l\'étape la plus longue qui compte.';

  @override
  String get discoverRoute => 'Itinéraire';

  @override
  String get discoverJourney => 'Randonnée par étapes';

  @override
  String discoverBy(String user) {
    return 'de $user';
  }

  @override
  String discoverStages(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n étapes', one: '1 étape');
    return '$_temp0';
  }

  @override
  String discoverLongest(String time) {
    return 'la plus longue $time';
  }

  @override
  String get discoverEmpty => 'Pas encore de randonnées publiques ici. Déplace la carte ou assouplis les filtres.';

  @override
  String get discoverMore => 'Il y a d\'autres randonnées – zoome ou affine les filtres.';

  @override
  String get discoverFailed => 'La recherche n\'a pas fonctionné. Réessaie dans un instant.';

  @override
  String get discoverOffline => 'Tu es hors ligne. Pour découvrir des randonnées, il faut une connexion.';

  @override
  String get discoverRetry => 'Réessayer';

  @override
  String get jplanTitle => 'Planifier une randonnée par étapes';

  @override
  String get jplanIntro =>
      'Choisis le départ et l\'arrivée – Alvyo découpe le chemin en jours qui se terminent à une cabane, un hôtel, un camping ou un arrêt pour rentrer.';

  @override
  String get jplanMapHint => 'Touche la carte pour placer un point, ou cherche un lieu.';

  @override
  String get jplanPointMap => 'Point sur la carte';

  @override
  String get jplanPointRemove => 'Supprimer';

  @override
  String get jplanSearchStart => 'Chercher le départ …';

  @override
  String get jplanSearchEnd => 'Chercher l\'arrivée …';

  @override
  String get jplanSearchMore => 'Chercher une autre destination …';

  @override
  String get jplanBy => 'Découper selon';

  @override
  String get jplanByDays => 'Nombre de jours';

  @override
  String get jplanByHours => 'Heures par jour';

  @override
  String get jplanDays => 'Jours';

  @override
  String get jplanHoursMin => 'Au moins heures par jour';

  @override
  String get jplanHoursMax => 'Au plus heures par jour';

  @override
  String get jplanMax => 'Au plus (h par jour, vide : un peu plus)';

  @override
  String get jplanKinds => 'Passer les nuits de préférence';

  @override
  String get jplanKindHut => 'en cabane';

  @override
  String get jplanKindHotel => 'à l\'hôtel ou en auberge';

  @override
  String get jplanKindCampsite => 'au camping';

  @override
  String get jplanKindPtStop => 'à un arrêt (retour à la maison)';

  @override
  String get jplanProfile => 'Profil';

  @override
  String get jplanProfileHike => 'Randonnée (jusqu\'à T3)';

  @override
  String get jplanProfileAlpine => 'Randonnée alpine (jusqu\'à T6)';

  @override
  String get jplanSubmit => 'Proposer des étapes';

  @override
  String get jplanSuggest => 'Proposer plusieurs itinéraires';

  @override
  String get jplanRunning => 'Planification …';

  @override
  String jplanDay(int n) {
    return 'Jour $n';
  }

  @override
  String get jplanToEnd => 'jusqu\'à l\'arrivée';

  @override
  String jplanEarlier(String place) {
    return 'Plus tôt : $place';
  }

  @override
  String jplanLater(String place) {
    return 'Plus tard : $place';
  }

  @override
  String get jplanOverMax => 'Plus long que souhaité : il n\'y a pas d\'hébergement avant.';

  @override
  String get jplanUnderMin =>
      'Plus court que souhaité : les lieux où passer la nuit ne permettent pas de mieux répartir les jours.';

  @override
  String get jplanHutHint =>
      'OpenStreetMap sait rarement si la cabane est ouverte et s\'il faut réserver – vérifie-le avant.';

  @override
  String get jplanWebsite => 'Site web';

  @override
  String get jplanFailed => 'La planification n\'a pas fonctionné. Réessaie dans un instant.';

  @override
  String get jplanNoPath => 'Il n\'y a pas de chemin entre ces points avec ce profil.';

  @override
  String jplanSummary(int days, String distance) {
    String _temp0 = intl.Intl.pluralLogic(days, locale: localeName, other: '$days jours', one: '1 jour');
    return '$_temp0 · $distance';
  }

  @override
  String get jplanWays => 'Itinéraires';

  @override
  String jplanWay(int n) {
    return 'Itinéraire $n';
  }

  @override
  String jplanWayDirect(int n) {
    return 'Itinéraire $n : direct';
  }

  @override
  String jplanWayVia(int n, String place) {
    return 'Itinéraire $n : par $place';
  }

  @override
  String get jplanWaysHint =>
      'Là où deux itinéraires passent la nuit au même endroit, tu peux passer de l’un à l’autre.';

  @override
  String jplanSwitch(int n) {
    return 'À partir d’ici, continuer sur l’itinéraire $n';
  }

  @override
  String get jplanTitleField => 'Titre';

  @override
  String get jplanCreate => 'Créer la randonnée par étapes';

  @override
  String get delete => 'Supprimer';

  @override
  String get routeDeleteConfirm => 'Supprimer l\'itinéraire ? C\'est irréversible.';

  @override
  String get journeyDeleteConfirm =>
      'Supprimer la randonnée par étapes avec toutes ses étapes et itinéraires ? C\'est irréversible.';

  @override
  String jplanTooLong(String hours, int days) {
    return 'Impossible avec au plus $hours h par jour : il faut au moins $days jours.';
  }

  @override
  String jplanTooLongNone(String hours) {
    return 'Impossible avec au plus $hours h par jour : il y a trop peu d\'hébergements en chemin.';
  }

  @override
  String jplanPlanIn(int days) {
    return 'Planifier en $days jours';
  }

  @override
  String get navFeed => 'Actualités';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get themeTitle => 'Apparence';

  @override
  String get themeSystem => 'Automatique';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get languageTitle => 'Langue';

  @override
  String get profileMine => 'Mon profil';

  @override
  String get accountNotifications => 'Notifications par e-mail';

  @override
  String get accountNotifyComments => 'Quand quelqu\'un commente mes itinéraires et randonnées par étapes';

  @override
  String get accountNotifyFollows => 'Quand quelqu\'un me suit';

  @override
  String get accountPace => 'Ton rythme';

  @override
  String get accountPaceHint =>
      'Les temps de marche en pourcentage des temps des indicateurs jaunes : en dessous de 100 % tu es plus rapide, au-dessus plus lent.';

  @override
  String get accountPaceSignposts => '100 % – comme les indicateurs';

  @override
  String get contactsTitle => 'Contacts pour les randonnées partagées';

  @override
  String get contactsIntro =>
      'Quand tu commences une randonnée dans l\'app, tu peux montrer ta position aux contacts choisis. Si la randonnée n\'est pas terminée 30 minutes après la fin prévue, ils reçoivent un e-mail avec la dernière position.';

  @override
  String get contactsName => 'Nom';

  @override
  String get contactsEmail => 'E-mail';

  @override
  String get contactsAdd => 'Ajouter';

  @override
  String get contactsRemove => 'Retirer';

  @override
  String get contactsDuplicate => 'Cette adresse est déjà un contact.';

  @override
  String get contactsFull => 'Au plus 10 contacts.';

  @override
  String get blockedTitle => 'Personnes bloquées';

  @override
  String get blockedEmpty => 'Tu n’as bloqué personne.';

  @override
  String get accountDeleteTitle => 'Supprimer le compte';

  @override
  String get accountDeleteText =>
      'Supprime définitivement ton compte et tous tes itinéraires. Les liens partagés ne fonctionneront plus.';

  @override
  String get accountDeleteSubmit => 'Supprimer définitivement le compte';

  @override
  String get accountDeleteWrong => 'Le mot de passe est incorrect.';

  @override
  String get accountDeleteRecent =>
      'Ton compte n\'a pas de mot de passe : pour confirmer, tu dois t\'être connecté·e au cours des 15 dernières minutes.';

  @override
  String get accountDeleteLoginAgain => 'Reconnecte-toi, puis réessaie tout de suite.';

  @override
  String get loginForgot => 'Mot de passe oublié ?';

  @override
  String get loginSignup => 'Créer un compte';

  @override
  String get myMapTitle => 'Carte de mes randonnées';

  @override
  String get myMapEmpty => 'Rien dans cette vue ne correspond aux filtres.';

  @override
  String get feedIntro =>
      'Ce que tes ami·e·s randonnent et publient, les nouvelles randonnées des personnes que tu suis et les commentaires sur tes randonnées.';

  @override
  String get feedEmpty =>
      'Rien pour l\'instant. Ajoute des ami·e·s ou suis des personnes dont les randonnées t\'intéressent.';

  @override
  String get feedMore => 'Charger les plus anciennes';

  @override
  String get feedHiked => 'a fait une randonnée';

  @override
  String get feedPublishedRoute => 'a publié un itinéraire';

  @override
  String get feedPublishedJourney => 'a publié une randonnée par étapes';

  @override
  String get feedCommented => 'a commenté';

  @override
  String get feedHikePrivate => 'Un itinéraire personnel';

  @override
  String profileSince(String date) {
    return 'membre depuis $date';
  }

  @override
  String get profileStatFollowers => 'Abonnés';

  @override
  String get profileStatFollowing => 'Abonnements';

  @override
  String get profileFollow => 'Suivre';

  @override
  String get profileUnfollow => 'Ne plus suivre';

  @override
  String get profileBlock => 'Bloquer';

  @override
  String get profileUnblock => 'Débloquer';

  @override
  String get profileBlockedNote =>
      'Bloqué·e : cette personne ne peut pas commenter tes randonnées ni te suivre, et tu ne vois pas ses commentaires.';

  @override
  String get profileRoutes => 'Itinéraires';

  @override
  String get profileJourneys => 'Randonnées par étapes';

  @override
  String get reportAction => 'Signaler';

  @override
  String get reportReason => 'Motif';

  @override
  String get reportReasonSpam => 'Spam ou publicité';

  @override
  String get reportReasonOffensive => 'Offensant ou inapproprié';

  @override
  String get reportReasonDangerous => 'Dangereux ou faux';

  @override
  String get reportReasonOther => 'Autre';

  @override
  String get reportNote => 'Que se passe-t-il ? (facultatif)';

  @override
  String get reportThanks => 'Merci, nous allons regarder.';

  @override
  String get editAction => 'Modifier';

  @override
  String get save => 'Enregistrer';

  @override
  String get saveConflict =>
      'Quelqu’un a modifié ceci entre-temps. Voici la nouvelle version – ta modification n’est pas enregistrée.';

  @override
  String get fieldTitle => 'Titre';

  @override
  String get fieldDescription => 'Description';

  @override
  String get fieldVisibility => 'Visibilité';

  @override
  String get visibilityPrivate => 'Privé';

  @override
  String get visibilityUnlisted => 'Partager par lien';

  @override
  String get visibilityPublic => 'Public';

  @override
  String get visibilityNeedsVerify => 'Confirme ton adresse e-mail pour publier des itinéraires.';

  @override
  String get tagsLabel => 'Étiquettes';

  @override
  String get tagsHint => 'Séparés par des virgules';

  @override
  String ownerBy(String user) {
    return 'de $user';
  }

  @override
  String get shareAction => 'Partager';

  @override
  String get shareLink => 'Lien de partage';

  @override
  String get shareSend => 'Envoyer le lien …';

  @override
  String get shareCopied => 'Copié';

  @override
  String get shareLinkHint => 'Choisis «Partager par lien» ou «Public» pour envoyer un lien.';

  @override
  String get shareRotate => 'Créer un nouveau lien';

  @override
  String get shareRotateHint => 'L\'ancien lien ne fonctionnera plus.';

  @override
  String get sharePeople => 'Partager avec des personnes';

  @override
  String get sharePending => 'invité·e';

  @override
  String get shareRemove => 'Retirer l\'accès';

  @override
  String get shareWho => 'Nom d\'utilisateur ou adresse e-mail';

  @override
  String get shareInvite => 'Inviter';

  @override
  String get shareHint =>
      'Les personnes invitées reçoivent un e-mail. Qui n\'a pas encore de compte s\'inscrit avec cette adresse.';

  @override
  String get shareNeedsVerify => 'Confirme ton adresse e-mail pour partager avec d\'autres.';

  @override
  String get shareRate => 'Trop d\'invitations – réessaie plus tard.';

  @override
  String get shareNoUser => 'Ce nom d\'utilisateur n\'existe pas.';

  @override
  String get shareSelf => 'Tu ne peux pas t\'inviter toi-même.';

  @override
  String get shareTooMany => 'Trop de personnes y ont déjà accès.';

  @override
  String get shareBadEmail => 'Adresse e-mail non valable.';

  @override
  String get roleViewer => 'Peut consulter';

  @override
  String get roleEditor => 'Peut planifier';

  @override
  String get sharedTitle => 'Partagé avec moi';

  @override
  String get gpxRoute => 'Partager le GPX …';

  @override
  String get gpxJourney => 'Partager toutes les étapes en GPX (ZIP) …';

  @override
  String get photosTitle => 'Photos';

  @override
  String get commentsTab => 'Commentaires';

  @override
  String get photosAdd => 'Ajouter des photos';

  @override
  String get photosCamera => 'Prendre une photo';

  @override
  String get photosLibrary => 'Depuis la photothèque';

  @override
  String photosUploading(int done, int total) {
    return '$done sur $total téléversées …';
  }

  @override
  String get photosHint =>
      'JPEG, PNG, WebP ou HEIC jusqu\'à 20 Mo. Nous supprimons toutes les métadonnées ; les photos prises le long de l\'itinéraire apparaissent sur la carte.';

  @override
  String get photosProblemFormat => 'pas une image JPEG, PNG, WebP ou HEIC';

  @override
  String get photosProblemSize => 'trop grande (20 Mo au maximum)';

  @override
  String get photosProblemLimit => 'trop de photos (au maximum 100 par randonnée et 1000 par personne)';

  @override
  String get photosProblemRate => 'trop de téléversements – réessaie dans un instant';

  @override
  String get photosProblemOther => 'le téléversement a échoué';

  @override
  String get photosCaption => 'Légende';

  @override
  String photosBy(String user) {
    return 'de $user';
  }

  @override
  String get photosDelete => 'Supprimer';

  @override
  String get photosDeleteConfirm => 'Vraiment supprimer ?';

  @override
  String get communityLike => 'J’aime';

  @override
  String communityLikes(int n) {
    return '$n j\'aime';
  }

  @override
  String communityComments(int n) {
    return '$n commentaires';
  }

  @override
  String get communityCommentsAllowed => 'Autoriser les commentaires';

  @override
  String get communityCommentsOff => 'Les commentaires sont désactivés.';

  @override
  String get communityCommentPlaceholder => 'Écrire un commentaire …';

  @override
  String get communityCommentSend => 'Commenter';

  @override
  String get communityReply => 'Répondre';

  @override
  String get communityReplyPlaceholder => 'Ta réponse …';

  @override
  String get communityEdited => 'modifié';

  @override
  String get communityRate => 'C\'était trop rapide – réessaie dans un instant.';

  @override
  String get communityVerifyToComment => 'Confirme ton adresse e-mail pour commenter.';

  @override
  String get stageEdit => 'Modifier l’étape';

  @override
  String get stageDate => 'Date';

  @override
  String get stageDateNone => 'Pas de date';

  @override
  String get stageStatus => 'Statut';

  @override
  String get statusPlanned => 'Prévue';

  @override
  String get stageAccommodationLabel => 'Hébergement';

  @override
  String get stageAccommodationPlaceholder => 'p. ex. Auberge du Col';

  @override
  String get stageBookedLabel => 'Réservé';

  @override
  String get stageNotes => 'Notes';

  @override
  String get stageTransfer => 'Reliée par';

  @override
  String get transferNone => '–';

  @override
  String get sbbToStart => 'Horaire CFF : aller';

  @override
  String get sbbFromEnd => 'Horaire CFF : retour';

  @override
  String get sbbTransfer => 'Horaire CFF';

  @override
  String get connectionsShow => 'Afficher les correspondances';

  @override
  String get connectionsDepart => 'Départ';

  @override
  String get connectionsArrive => 'Arrivée';

  @override
  String get connectionsSearch => 'Chercher';

  @override
  String get connectionsNone => 'Aucune correspondance trouvée.';

  @override
  String get connectionsUnavailable => 'L\'horaire n\'est pas disponible pour l\'instant – utilise l\'horaire CFF.';

  @override
  String connectionsTransfers(int n) {
    return '$n chang.';
  }

  @override
  String connectionsWalk(int min) {
    return '$min min à pied';
  }

  @override
  String connectionsPlatform(String p) {
    return 'Voie/quai $p';
  }

  @override
  String get connectionsSource => 'Données d\'horaire : opentransportdata.swiss';

  @override
  String get collectionsTitle => 'Collections';

  @override
  String get collectionsIntro =>
      'Réunir des itinéraires et des randonnées par étapes – comme liste d\'envies, recueil d\'idées ou pour les partager. Une collection ne donne aucun accès : chacun ne voit que ce qu\'il peut déjà ouvrir.';

  @override
  String get collectionsEmpty => 'Pas encore de collections.';

  @override
  String get collectionNew => 'Nouvelle collection';

  @override
  String collectionItemsCount(int n) {
    return '$n éléments';
  }

  @override
  String get collectionEmpty =>
      'Encore vide. Ajoute des itinéraires et des randonnées par étapes depuis leur menu : «Ajouter à une collection …».';

  @override
  String collectionHidden(int n) {
    return 'Éléments privés que tu ne peux pas voir : $n';
  }

  @override
  String get collectionAddTo => 'Ajouter à une collection …';

  @override
  String collectionAdded(String title) {
    return 'Ajouté à « $title »';
  }

  @override
  String collectionAlready(String title) {
    return 'Déjà dans « $title »';
  }

  @override
  String get collectionRemoveItem => 'Retirer';

  @override
  String collectionRemoveConfirm(String title) {
    return 'Retirer « $title » de la collection ? L’itinéraire ou la randonnée par étapes reste.';
  }

  @override
  String get collectionDelete => 'Supprimer la collection';

  @override
  String get collectionDeleteConfirm => 'Supprimer la collection ? Les itinéraires et randonnées restent.';

  @override
  String get collectionMap => 'Carte de la collection';

  @override
  String collectionStages(int n) {
    return '$n étapes';
  }

  @override
  String get myMapKindHike => 'Randonnées faites';

  @override
  String get connectionsFromHere => 'Correspondances d’ici au départ';

  @override
  String get connectionsNoPosition =>
      'Ta position n’est pas connue. Autorise Alvyo à l’utiliser dans les réglages du téléphone.';

  @override
  String get stageMore => 'Détails et accès';

  @override
  String get travelTitle => 'Aller et retour';

  @override
  String get travelTo => 'Aller';

  @override
  String get travelBack => 'Retour';

  @override
  String get travelFrom => 'De';

  @override
  String get travelToHome => 'À';

  @override
  String get travelNone => '– aucun –';

  @override
  String travelOn(String date) {
    return 'le $date';
  }

  @override
  String get travelNoDate => 'L’étape n’a pas de date : correspondances d’aujourd’hui.';

  @override
  String get travelNoHomes => 'Ajoute dans ton compte un domicile dont tu as souvent besoin.';

  @override
  String get travelPrivate => 'Toi seul vois ton aller et ton retour.';

  @override
  String get travelNoRoute => 'Dès qu’une étape a un itinéraire.';

  @override
  String get travelChoose => 'D’où et quand';

  @override
  String get homesTitle => 'Domiciles';

  @override
  String get homesIntro =>
      'D’ici tu planifies l’aller vers tes randonnées par étapes et le retour en transports publics. 5 au plus ; toi seul les vois.';

  @override
  String get homesName => 'Nom';

  @override
  String get homesNamePlaceholder => 'p. ex. Maison, Bureau';

  @override
  String get homesAddress => 'Chercher une adresse …';

  @override
  String get homesAdd => 'Ajouter';

  @override
  String get homesRemove => 'Retirer';

  @override
  String get homesFull => '5 domiciles au plus.';

  @override
  String get travelStart => 'Départ de la randonnée';

  @override
  String get travelEnd => 'Arrivée de la randonnée';

  @override
  String get recordTitle => 'Randonnée';

  @override
  String get recordStart => 'Commencer l\'enregistrement';

  @override
  String get recordRefused =>
      'Non enregistrée : la randonnée est trop courte ou va à plus de 15 km au-delà de la Suisse et du Liechtenstein.';

  @override
  String get barRoutes => 'Itinéraires';

  @override
  String get barJourneys => 'Étapes';

  @override
  String get planAction => 'Planifier';

  @override
  String get routePrivacyOwner => 'Les autres voient cette randonnée sans ses 500 premiers et derniers mètres.';

  @override
  String get routePrivacyOthers => 'Le départ et l\'arrivée de la randonnée sont masqués.';

  @override
  String get routePrivacyAll =>
      'Cette randonnée est trop courte pour être montrée aux autres : le départ et l\'arrivée sont masqués.';

  @override
  String plannerAlpineShorter(String alpine, String hike) {
    return 'Avec « Randonnée alpine » seulement $alpine au lieu de $hike.';
  }

  @override
  String plannerAlpineGrade(String grade) {
    return 'Le chemin plus court passe par du $grade.';
  }

  @override
  String get plannerAlpineUse => 'Planifier ce tronçon en alpin';

  @override
  String get plannerAlpineUsed => 'Planifié avec « Randonnée alpine ».';

  @override
  String get plannerAlpineUndo => 'Revenir à la randonnée';

  @override
  String get noticesTitle => 'Fermetures et tirs';

  @override
  String get noticesClosure => 'chemin fermé';

  @override
  String get noticesShooting => 'tirs de l\'armée';

  @override
  String get mapPois => 'En chemin';

  @override
  String get poiPeak => 'Sommet';

  @override
  String get poiViewpoint => 'Point de vue';

  @override
  String get poiWaterfall => 'Cascade';

  @override
  String get poiWater => 'Eau potable';

  @override
  String get poiShelter => 'Abri';

  @override
  String get mapBase => 'Fond de carte';

  @override
  String get mapOverlays => 'Superpositions';

  @override
  String get mapBaseNational => 'Carte nationale';

  @override
  String get mapBaseGrey => 'Carte nationale grise';

  @override
  String get mapBaseAerial => 'Image aérienne';

  @override
  String get mapOverlayTrails => 'Chemins de randonnée';

  @override
  String get mapOverlayWanderland => 'Itinéraires de randonnée SuisseMobile';

  @override
  String get mapOverlaySlope => 'Pentes de plus de 30°';

  @override
  String get mapOverlayRestAreas => 'Zones de tranquillité';

  @override
  String get mapOverlayHuntingReserves => 'Districts francs fédéraux';

  @override
  String get mapOverlayRelief => 'Relief';

  @override
  String get mapOverlayPrecip => 'Pluie (radar et prévision)';

  @override
  String get precipRadar => 'Radar, mesuré';

  @override
  String get precipForecast => 'Prévision du modèle';

  @override
  String get precipPlay => 'Lire';

  @override
  String get precipPause => 'Pause';

  @override
  String get precipNone => 'Pas de données de pluie pour le moment.';

  @override
  String get precipLight => 'faible';

  @override
  String get precipHeavy => 'fort';

  @override
  String get mapOverlaySnow => 'Neige (satellite)';

  @override
  String snowDate(String date) {
    return 'Enneigement le $date';
  }

  @override
  String get snowNone => 'Pas encore de données d’enneigement.';

  @override
  String get snowNote => 'Satellite, 60 m ; jusqu’à 7 jours sous les nuages';

  @override
  String get snowPatchy => 'plaques';

  @override
  String get snowMostly => 'en majorité';

  @override
  String get snowFull => 'continue';

  @override
  String get snowHint =>
      'Montre où il y a de la neige, pas son épaisseur ni si le chemin est praticable. Le BPA conseille de planifier ses randonnées de manière à éviter les névés et de faire demi-tour en cas de doute.';

  @override
  String get snowMore => 'En savoir plus';

  @override
  String get snowLess => 'Moins';

  @override
  String get showOnMap => 'Afficher sur la carte';

  @override
  String get snowAlongTitle => 'Neige en chemin';

  @override
  String snowAlongNote(String snow) {
    return '$snow de neige';
  }

  @override
  String snowAlongNoteSteep(String snow, String steep) {
    return '$snow de neige, dont $steep raide';
  }

  @override
  String snowAlongSummary(String snow) {
    return 'Passe par $snow de neige.';
  }

  @override
  String snowAlongSummarySteep(String snow, String steep) {
    return 'Passe par $snow de neige, dont $steep sur un terrain de plus de 30°.';
  }

  @override
  String snowAlongPatches(String distance) {
    return 'En plus, des plaques de neige sur $distance.';
  }

  @override
  String snowAlongPatchesOnly(String distance, String date) {
    return 'Plaques de neige sur $distance, état au $date.';
  }

  @override
  String snowAlongStretch(String at, String length) {
    return 'Après $at : $length de neige';
  }

  @override
  String snowAlongStretchSteep(String steep) {
    return 'dont $steep sur plus de 30°';
  }

  @override
  String get snowAlongLimits =>
      'Satellite, 60 m ; jusqu’à 7 jours sous les nuages. Un court névé peut manquer ; ni l’épaisseur ni la dureté ne sont indiquées. Raide : terrain de plus de 30° (swissALTI3D, en Suisse seulement).';

  @override
  String get poiFirepit => 'Place de feu';

  @override
  String get poiPicnic => 'Aire de pique-nique';

  @override
  String get poiRestaurant => 'Restaurant, café';

  @override
  String get poiToilets => 'Toilettes';

  @override
  String get poiCablecar => 'Station de téléphérique';

  @override
  String get poisTitle => 'En chemin';

  @override
  String get routeTabOverview => 'Aperçu';

  @override
  String get routeTabTravel => 'Accès';

  @override
  String get journeyTabStages => 'Étapes';

  @override
  String get statTime => 'Temps de marche';

  @override
  String get statDistance => 'Distance';

  @override
  String get statHeights => 'Dénivelé';

  @override
  String get statSac => 'Difficulté';

  @override
  String poisFilterAll(int count) {
    return 'Tous $count';
  }

  @override
  String get weatherTitle => 'Météo';

  @override
  String get weatherStart => 'Départ';

  @override
  String get weatherTop => 'Point culminant';

  @override
  String get weatherEnd => 'Arrivée';

  @override
  String get weatherToday => 'Aujourd\'hui';

  @override
  String get weatherTomorrow => 'Demain';

  @override
  String get weatherDry => 'sec';

  @override
  String weatherRain(String mm, String lo, String hi) {
    return '$mm mm de précipitations ($lo–$hi mm)';
  }

  @override
  String weatherSource(String time) {
    return 'Prévision de MétéoSuisse pour le lieu proche d\'altitude la plus semblable, de $time.';
  }

  @override
  String weatherStage(int n, String date) {
    return 'Étape $n, $date';
  }

  @override
  String get travelElsewhere => 'Autre lieu …';

  @override
  String get travelPlaceSearch => 'Lieu, arrêt ou adresse';

  @override
  String get travelDay => 'Le';

  @override
  String get travelRouteStart => 'Départ';

  @override
  String get travelRouteEnd => 'Arrivée';

  @override
  String get areasNow => 'en vigueur maintenant';

  @override
  String get areasOnDate => 'en vigueur un jour prévu';

  @override
  String hintsOpen(int count) {
    return 'Afficher ($count)';
  }

  @override
  String get weatherOtherDay => 'Autre date';

  @override
  String weatherClimate(String month, String min, String max, String days, String total, String mm) {
    return 'Habituel en $month : $min–$max °C, pluie $days jours sur $total, $mm mm dans le mois';
  }

  @override
  String weatherClimateSource(String station, String rain) {
    return 'Pas encore de prévision pour ce jour : normes climatologiques 1991–2020 de MétéoSuisse (température : $station, ramenée à l’altitude ; précipitations : $rain). La prévision couvre les 9 prochains jours.';
  }

  @override
  String get journeyMap => 'Carte de la randonnée par étapes';

  @override
  String get journeyAddStage => 'Ajouter une étape';

  @override
  String get routeEditLine => 'Modifier sur la carte';

  @override
  String get bugOpen => 'Signaler un bug';

  @override
  String get bugWhat => 'Que s’est-il passé ? À quoi t’attendais-tu ?';

  @override
  String get bugWithScreenshot => 'Joindre une capture d’écran';

  @override
  String get bugScreenshotAlt => 'Capture d’écran de cette page';

  @override
  String bugPrivacy(String place) {
    return 'Le rapport devient une issue dans un dépôt GitHub privé que seule l\'équipe Alvyo voit : ton texte, l\'adresse ($place), la version, ton nom d\'utilisateur et la capture d\'écran.';
  }

  @override
  String get bugSend => 'Envoyer';

  @override
  String get bugSent => 'Merci ! Le bug est signalé.';

  @override
  String get bugFailed => 'Cela n’a pas fonctionné. Réessaie plus tard.';

  @override
  String get bugBusy => 'Tu as déjà signalé plusieurs bugs aujourd’hui. Réessaie plus tard.';

  @override
  String get close => 'Fermer';

  @override
  String get peopleTitle => 'Qui vient';

  @override
  String get peopleTab => 'Personnes';

  @override
  String peopleWith(String names) {
    return 'avec $names';
  }

  @override
  String get peopleInvite => 'Inviter des personnes';

  @override
  String get peopleNone =>
      'Personne pour l’instant. Qui vient voit le trek et les étapes auxquelles il ou elle participe.';

  @override
  String get peopleInvited => 'Invité·e';

  @override
  String get peopleRemove => 'Ne vient pas';

  @override
  String get peopleWho => 'Nom d’utilisateur ou adresse e-mail';

  @override
  String get peopleAdd => 'Ajouter';

  @override
  String get peopleHint =>
      'Qui n’a pas encore accès est invité·e et peut voir le trek. Les chiffres sont les étapes : touche qui participe à laquelle.';

  @override
  String get peopleUnknown => 'Cette personne n’existe pas, ou c’est toi.';

  @override
  String get peopleVerify => 'Confirme d’abord ton adresse e-mail.';

  @override
  String get peopleFailed => 'Cela n’a pas fonctionné. Réessaie.';

  @override
  String peopleOnStage(String names) {
    return 'Avec $names';
  }

  @override
  String peopleStages(String name) {
    return 'Étapes de $name';
  }

  @override
  String get remindersTitle => 'Rappels';

  @override
  String get remindersOn => 'Rappels par e-mail avant le départ';

  @override
  String get remindersHint => 'Pour toi et tous ceux qui viennent ; dans l’app aussi sur le téléphone.';

  @override
  String get reminderBook => 'Départ dans trois semaines : toutes les nuits sont-elles réservées ?';

  @override
  String get reminderWeather => 'Départ après-demain : jette un œil à la météo.';

  @override
  String get reminderStart => 'Départ demain. Bonne route !';

  @override
  String get friendsTitle => 'Ami·e·s';

  @override
  String get friendsIntro =>
      'Les ami·e·s voient mutuellement leurs profils, même privés, et leurs randonnées dans les actualités. Des personnes que tu suis, tu ne vois que les randonnées publiques.';

  @override
  String get friendsInvite => 'Inviter des ami·e·s';

  @override
  String get friendsSuggestions => 'Personnes que tu connais peut-être';

  @override
  String get friendsDismiss => 'Ne pas suggérer';

  @override
  String get friendsDiscover => 'Découvrir des profils';

  @override
  String friendsMutual(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n ami·e·s en commun',
      one: '$n ami·e en commun',
    );
    return '$_temp0';
  }

  @override
  String friendsTours(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n randonnées', one: '$n randonnée');
    return '$_temp0';
  }

  @override
  String get friendsSearch => 'Chercher des personnes';

  @override
  String get friendsSearchHint =>
      'Nom d\'utilisateur ou nom. Sans recherche : qui a publié des randonnées en dernier. Profils publics uniquement.';

  @override
  String get friendsNoneFound => 'Personne trouvé.';

  @override
  String get friendsIncoming => 'Demandes reçues';

  @override
  String get friendsOutgoing => 'Tes demandes';

  @override
  String get friendsList => 'Tes ami·e·s';

  @override
  String get friendsEmpty =>
      'Pas encore d\'ami·e·s. Invite les personnes avec qui tu randonnes : le lien fait de vous des ami·e·s, même avec un profil privé.';

  @override
  String get friendAdd => 'Ajouter comme ami·e';

  @override
  String get friendRequested => 'Demande envoyée';

  @override
  String get friendWithdraw => 'Retirer';

  @override
  String get friendAccept => 'Accepter';

  @override
  String get friendDecline => 'Refuser';

  @override
  String get friendFriends => 'Ami·e·s';

  @override
  String get friendRemove => 'Retirer des ami·e·s';

  @override
  String get friendsLinkHint =>
      'Qui ouvre le lien et accepte devient ton ami·e – même si ton profil est privé. Aucune demande n\'arrive dans Alvyo : envoie le lien toi-même, seulement à des personnes que tu connais.';

  @override
  String get friendsInviteShare => 'Soyons ami·e·s sur Alvyo. Ouvre le lien et touche « Accepter » :';

  @override
  String get friendsLinkRenew => 'Créer un nouveau lien';

  @override
  String get profilePublic => 'Profil public';

  @override
  String get profilePublicHint =>
      'Les autres te trouvent dans la recherche. Un profil privé n\'est visible que par tes ami·e·s.';

  @override
  String get shareHikes => 'Partager mes randonnées avec mes ami·e·s';

  @override
  String get shareHikesHint =>
      'Tes ami·e·s voient dans leurs actualités quand tu as fait une randonnée, avec la distance et la durée.';

  @override
  String get doneMark => 'Marquer comme faite';

  @override
  String get doneRemove => 'Pas faite';

  @override
  String get doneByHike => 'enregistrée';

  @override
  String get doneByStages => 'toutes les étapes faites';

  @override
  String get doneFilterAll => 'Toutes';

  @override
  String get doneFilterPlanned => 'Prévues';

  @override
  String get doneFilterDone => 'Faites';

  @override
  String get doneFilterNone => 'Rien dans cette sélection.';

  @override
  String doneOn(String date) {
    return 'Faite le $date';
  }

  @override
  String get breakdownTitle => 'Nature du chemin';

  @override
  String get breakdownTrail => 'Réseau de randonnée';

  @override
  String get breakdownSurface => 'Revêtement';

  @override
  String get breakdownWay => 'Type de chemin';

  @override
  String get breakdownOther => 'Autres';

  @override
  String get breakdownDetails => 'Détails en km';

  @override
  String get trailWanderweg => 'Chemin de randonnée';

  @override
  String get trailBergwanderweg => 'Chemin de randonnée de montagne';

  @override
  String get trailAlpinwanderweg => 'Chemin de randonnée alpine';

  @override
  String get trailNone => 'Pas un chemin de randonnée';

  @override
  String get surfacePaved => 'Asphalte, pavés';

  @override
  String get surfaceGravel => 'Gravier';

  @override
  String get surfaceNatural => 'Terrain naturel';

  @override
  String get surfaceUnknown => 'Inconnu';

  @override
  String get wayRoad => 'Route';

  @override
  String get wayTrack => 'Chemin carrossable';

  @override
  String get wayPath => 'Sentier';

  @override
  String get waySteps => 'Escalier';

  @override
  String get wayUnknown => 'Inconnu';

  @override
  String get offTrailTitle => 'Pas un chemin de randonnée officiel';

  @override
  String offTrailAll(String distance) {
    return 'Tout l\'itinéraire ($distance) passe hors des chemins de randonnée balisés.';
  }

  @override
  String inviteTitle(String name) {
    return '$name aimerait être ton ami·e';
  }

  @override
  String get inviteText => 'Devenez ami·e·s sur Alvyo : vous voyez vos profils, même privés.';

  @override
  String get inviteAccept => 'Accepter';

  @override
  String get inviteDone => 'Vous êtes maintenant ami·e·s.';

  @override
  String get inviteInvalid => 'Ce lien d\'invitation n\'est plus valable.';

  @override
  String get inviteSelf => 'C\'est ton propre lien.';

  @override
  String get reachTitle => 'Jusqu’où puis-je aller ?';

  @override
  String get reachBackHint => 'Aller-retour, montée et descente chacune avec son temps';

  @override
  String get importFile => 'Fichier (GPX, KML, TCX, FIT)';

  @override
  String get importFileHint => 'Devient un itinéraire privé';

  @override
  String get importNotTrack => 'Ce fichier ne contient aucune trace qu’Alvyo sait lire (GPX, KML, TCX ou FIT).';

  @override
  String reachWithinBack(int hours) {
    return 'jusqu’à $hours heures, aller-retour';
  }

  @override
  String get plannerVia => 'Étape intermédiaire';

  @override
  String get plannerSearchVia => 'Chercher une étape …';

  @override
  String get plannerRoundTrip => 'Boucle';

  @override
  String get plannerReturn => 'Retour au départ';

  @override
  String get recordFollow => 'Suivre une randonnée (facultatif)';

  @override
  String get recordChooseTour => 'Choisir une randonnée';

  @override
  String get recordWithoutTour => 'Sans randonnée';

  @override
  String get recordNoTours => 'Pas encore de randonnée prévue. Planifie-en une sous « Planifier ».';

  @override
  String get devicesTitle => 'Appareils connectés';

  @override
  String get devicesSubtitle => 'Apple Watch · importer les randonnées automatiquement';

  @override
  String get devicesWatch => 'Apple Watch';

  @override
  String get devicesWatchHint => 'Randonnées de l’app Exercice, via Apple Santé';

  @override
  String get devicesWatchAuto => 'Importer automatiquement les nouvelles randonnées';

  @override
  String get devicesWatchAutoHint => 'À l’ouverture de l’app – les randonnées à partir de maintenant';

  @override
  String get devicesWatchPick => 'Choisir des randonnées et les importer';

  @override
  String get profileAccount => 'Compte';

  @override
  String get accountPaceShort => 'Temps de marche par rapport aux indicateurs';

  @override
  String devicesWatchImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count randonnées importées de l’Apple Watch',
      one: '1 randonnée importée de l’Apple Watch',
    );
    return '$_temp0';
  }

  @override
  String get importTitle => 'Importer';

  @override
  String get importAction => 'Importer';

  @override
  String get importWatchHint => 'Randonnées enregistrées avec ta montre';

  @override
  String get planDay => 'Journée';

  @override
  String get planMulti => 'Plusieurs jours';

  @override
  String get planReach => 'Portée';

  @override
  String get discoverSearchHint => 'Chercher un lieu ou un sommet';

  @override
  String get discoverSearchNone => 'Rien trouvé. Essaie un autre nom.';

  @override
  String get discoverReachHint => 'Portée depuis ta position';

  @override
  String get discoverPeaks => 'Regarder les sommets';

  @override
  String get discoverPeaksHint => 'Caméra vers l’horizon';

  @override
  String get discoverFollowing => 'Actualités';

  @override
  String get discoverAll => 'Tout';

  @override
  String get discoverFollowingEmpty =>
      'Rien pour l\'instant. Ajoute des ami·e·s ou suis des personnes dont les randonnées t\'intéressent.';

  @override
  String get discoverNearby => 'Près de toi';

  @override
  String get discoverNearbyNoPosition => 'Autorise la localisation pour voir les randonnées près de toi.';

  @override
  String get discoverNearbyAllow => 'Autoriser la localisation';

  @override
  String get discoverNearbyUnknown =>
      'Ta position n’est pas connue pour l’instant. Dehors ou avec le Wi-Fi, le téléphone la trouve en général plus vite.';

  @override
  String get openSettings => 'Ouvrir les réglages';

  @override
  String get discoverNearbyEmpty =>
      'Aucune randonnée publiée autour de toi pour l’instant. Tu en trouves d’autres sur la carte.';

  @override
  String get toursTitle => 'Randonnées';

  @override
  String get toursMap => 'Carte';

  @override
  String get toursList => 'Liste';

  @override
  String get toursJourneys => 'Par étapes';

  @override
  String get toursShared => 'Partagées';

  @override
  String get toursEmptyPlanned =>
      'Pas encore de randonnées prévues. Planifie un itinéraire ou une randonnée par étapes – elle apparaîtra ici.';

  @override
  String get toursEmptyHiked => 'Encore rien randonné. Enregistre ta prochaine randonnée – elle apparaîtra ici.';

  @override
  String get toursPlanAction => 'Planifier une randonnée';

  @override
  String get barDiscover => 'Découvrir';

  @override
  String get barPlan => 'Planifier';

  @override
  String get barTours => 'Randonnées';

  @override
  String get tourRoute => 'Itinéraire';

  @override
  String get tourJourney => 'Randonnée par étapes';

  @override
  String get tourSharedBy => 'partagé par';

  @override
  String get tourBy => 'de';

  @override
  String get peaksTitle => 'Reconnaître les sommets';

  @override
  String get peaksDownloadText =>
      'Pour nommer les sommets dans l’image de la caméra, l’app a besoin une fois des altitudes de la Suisse et des alentours avec tous les sommets (environ 9 Mo). Ensuite, cela fonctionne aussi sans réseau.';

  @override
  String get peaksDownload => 'Télécharger';

  @override
  String get peaksDownloadFailed => 'Le téléchargement a échoué. Réessaie.';

  @override
  String get peaksPreparing => 'En préparation …';

  @override
  String get peaksComputing => 'Calcul de ce que tu vois d’ici …';

  @override
  String get peaksNoPosition => 'Ta position est inconnue : autorise la localisation.';

  @override
  String get peaksNoCamera => 'Alvyo n’a pas accès à l’appareil photo : autorise-le dans les réglages.';

  @override
  String get peaksNoCompass => 'Cet appareil n’a pas de boussole.';

  @override
  String get peaksCompass => 'Boussole imprécise : décris quelques huit avec le téléphone.';

  @override
  String get peaksAlign => 'Si la ligne ne suit pas l’horizon, fais-la glisser du doigt.';

  @override
  String get peaksReset => 'Réinitialiser';

  @override
  String peaksDirection(int azimuth, int elevation) {
    return 'Direction $azimuth° · inclinaison $elevation°';
  }

  @override
  String get reachAction => 'Portée';

  @override
  String get reachIntro =>
      'Touche la carte, cherche un lieu ou prends ta position : les surfaces montrent jusqu’où tu vas depuis là en 2, 4 et 8 heures, à ton rythme et avec toutes les montées et descentes.';

  @override
  String get reachSearch => 'Chercher un départ';

  @override
  String get reachHere => 'Ma position';

  @override
  String get reachNoPosition =>
      'Ta position est inconnue. Autorise la localisation dans les réglages ou touche la carte.';

  @override
  String reachStart(String place) {
    return 'Départ : $place';
  }

  @override
  String get reachMapPoint => 'Point sur la carte';

  @override
  String get reachBusy => 'Calcul de la distance que tu peux parcourir …';

  @override
  String reachWithin(int hours) {
    return 'jusqu’à $hours heures';
  }

  @override
  String get reachNote =>
      'Approximatif : une surface englobe tout ce qui est atteint, y compris les lacs et les pentes sans chemin entre eux. Les temps suivent le temps de marche suisse selon la pente, sans pauses.';

  @override
  String reachPace(String pace) {
    return 'À ton rythme : $pace fois le temps des panneaux.';
  }

  @override
  String get reachErrorNoPath => 'Aucun chemin près de ce point. Choisis un point sur un chemin ou à proximité.';

  @override
  String get reachErrorBusy => 'Trop de requêtes. Attends un instant.';

  @override
  String get reachErrorOther => 'Le calcul a échoué. Réessaie.';

  @override
  String get reachPlanHere => 'Planifier jusqu’ici';

  @override
  String get reachStartHere => 'Partir d’ici';

  @override
  String get reachPlanHint => 'Touche une zone pour planifier un itinéraire jusque-là.';

  @override
  String officialNational(String number) {
    return 'Itinéraire national $number';
  }

  @override
  String officialRegional(String number) {
    return 'Itinéraire régional $number';
  }

  @override
  String officialLocal(String number) {
    return 'Itinéraire local $number';
  }

  @override
  String officialHandicap(String number) {
    return 'Itinéraire sans obstacles $number';
  }

  @override
  String get officialLink => 'sur SuisseMobile';

  @override
  String get officialSource => 'Itinéraire officiel de La Suisse à pied – données : OFROU et SuisseMobile';

  @override
  String get discoverOriginAll => 'Itinéraires officiels et des gens';

  @override
  String get discoverOriginOnly => 'Itinéraires officiels seulement';

  @override
  String get discoverOriginNone => 'Des gens seulement';

  @override
  String get routeCopy => 'Modifier comme ton itinéraire';

  @override
  String get journeyCopy => 'Modifier comme ta randonnée par étapes';

  @override
  String get copyFailed => 'La copie n\'a pas fonctionné. Réessaie.';

  @override
  String get tokensOnWebsite => 'Tu gères les jetons d’accès pour les assistants IA sur alvyo.tellbow.ch.';

  @override
  String get aboutTitle => 'À propos d\'Alvyo';

  @override
  String get aboutIntro => 'Alvyo est une plateforme ouverte pour planifier et partager des randonnées en Suisse.';

  @override
  String get aboutDataTitle => 'Données';

  @override
  String get aboutDataIntro =>
      'Alvyo affiche des données de ces sources ; merci à toutes celles et ceux qui les mettent librement à disposition :';

  @override
  String get aboutSrcSwisstopo =>
      'Office fédéral de topographie swisstopo : cartes nationales, images aériennes, carte de base, modèle altimétrique swissALTI3D, relief, pentes et chemins de randonnée (swissTLM3D)';

  @override
  String get aboutSrcAstra =>
      'Office fédéral des routes OFROU (ASTRA) et SuisseMobile : les itinéraires officiels de La Suisse à pied, fermetures et déviations de chemins de randonnée';

  @override
  String get aboutSrcBafu =>
      'Office fédéral de l\'environnement OFEV (BAFU) et cantons : zones de tranquillité pour la faune et districts francs fédéraux';

  @override
  String get aboutSrcVbs =>
      'Département fédéral de la défense, de la protection de la population et des sports DDPS (VBS) : avis de tir';

  @override
  String get aboutSrcMeteo =>
      'Source : MétéoSuisse – prévisions météo, radar des précipitations, prévision des précipitations (ICON-CH1) et normes climatologiques';

  @override
  String get aboutSrcCopernicus =>
      'Réalisé à partir d’informations du service Copernicus de surveillance des terres de l’Union européenne : enneigement (HR-WSI, quotidien, 60 m), coloré et découpé sur la Suisse par nos soins';

  @override
  String get aboutSrcTransport => 'opentransportdata.swiss : horaire et correspondances (Open Journey Planner)';

  @override
  String get aboutSrcBav => 'Office fédéral des transports OFT (BAV) : arrêts des transports publics';

  @override
  String get aboutSrcOsm =>
      '© les contributeurs d\'OpenStreetMap : le réseau de chemins pour le calcul des itinéraires, cabanes, hébergements, lieux et sommets';

  @override
  String get aboutSrcMapterhorn =>
      'Mapterhorn (à partir de Copernicus GLO-30, swissALTI3D et des modèles altimétriques des pays voisins) : le relief de la carte 3D et « Reconnaître les sommets » dans l\'app';

  @override
  String get aboutSrcTerrain =>
      'Terrain Tiles de Mapzen (EU-DEM : produit à partir de données Copernicus financées par l\'Union européenne ; SRTM : U.S. Geological Survey) : pentes pour « Jusqu’où puis-je aller ? »';

  @override
  String get aboutSrcHikingtime => 'Temps de marche selon la formule de SuisseMobile / Suisse Rando';

  @override
  String get aboutSafety =>
      'Les temps de marche et difficultés sont des valeurs indicatives calculées. Vérifie la météo, les conditions et la signalisation sur place.';

  @override
  String get aboutCodeTitle => 'Code source et licences';

  @override
  String get aboutCode => 'Alvyo est un logiciel libre sous AGPL-3.0.';

  @override
  String get aboutSourceLink => 'Code source sur GitHub';

  @override
  String get aboutNoticeLink => 'Sources et licences du code et des données de tiers (NOTICE)';

  @override
  String get aboutLicenses => 'Licences des composants de cette app';

  @override
  String get aboutPrivacy => 'Protection des données';

  @override
  String get aboutPrivacyHint => 'Ce que nous enregistrons et où vont les données – sur le site';

  @override
  String get aboutOperator => 'Exploitant et contact';

  @override
  String get mapCreditLabel => 'Sources de la carte';

  @override
  String get peaksCredit => 'Relief : Mapterhorn · Sommets : © les contributeurs d\'OpenStreetMap';

  @override
  String get gpsServiceTitle => 'Randonnée en cours';

  @override
  String get gpsServiceText => 'Alvyo suit ta position, même écran verrouillé.';

  @override
  String get channelReminders => 'Rappels des randonnées par étapes';

  @override
  String get signupUsername => 'Nom d\'utilisateur';

  @override
  String get signupUsernameHint => '3 à 30 caractères : minuscules, chiffres et _';

  @override
  String get signupUsernameTaken => 'Ce nom d\'utilisateur est déjà pris.';

  @override
  String get signupDisplayName => 'Nom affiché';

  @override
  String get signupDisplayNameMissing => 'Indique un nom.';

  @override
  String get signupPasswordHint => 'Au moins 10 caractères';

  @override
  String signupSent(String email) {
    return 'Presque fini : nous t’avons envoyé un e-mail à $email. Confirme ton adresse dans cet e-mail, puis tu pourras te connecter ici. Si tu as déjà un compte, l’e-mail t’explique comment y accéder.';
  }

  @override
  String get errorTooMany => 'Trop de tentatives. Merci de patienter un instant.';

  @override
  String get statisticsTitle => 'Statistiques';

  @override
  String get statisticsAsk =>
      'Pouvons-nous mesurer avec Google Analytics quelles parties de l’app sont utilisées ? Google n’apprend que le type d’écran (par exemple « Itinéraire »), sans titres, lieux ni liens, et sans identifiant publicitaire. Sans ton accord, Google ne reçoit rien.';

  @override
  String get statisticsAccept => 'Accepter';

  @override
  String get statisticsDecline => 'Refuser';

  @override
  String get statisticsGranted => 'Accepté';

  @override
  String get statisticsDenied => 'Refusé';
}
