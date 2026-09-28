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
  String get errorServer => 'Le serveur n\'est pas joignable.';

  @override
  String get routesTitle => 'Mes itinéraires';

  @override
  String get routesEmpty => 'Pas encore d\'itinéraires. Planifie-les sur le site.';

  @override
  String get logout => 'Se déconnecter';

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
  String get navNoPermission => 'L\'app a besoin de ta position. Autorise-la dans les réglages.';

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
  String get watchReasonOutside => 'il sort de la Suisse et du Liechtenstein.';

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
  String recordHint(String start) {
    return 'Choisis un itinéraire et touche « $start » pour enregistrer la randonnée.';
  }

  @override
  String get mapLayers => 'Cartes';

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
  String get feedIntro => 'Les nouvelles randonnées publiques des personnes que tu suis.';

  @override
  String get feedEmpty =>
      'Rien pour l’instant – suis les personnes dont les randonnées t’intéressent. Tu les trouves sous Découvrir.';

  @override
  String get feedMore => 'Charger les plus anciennes';

  @override
  String profileSince(String date) {
    return 'membre depuis $date';
  }

  @override
  String profileFollowers(int n) {
    return '$n abonnés';
  }

  @override
  String profileFollowing(int n) {
    return 'suit $n';
  }

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
  String get collectionDelete => 'Supprimer la collection';

  @override
  String get collectionDeleteConfirm => 'Supprimer la collection ? Les itinéraires et randonnées restent.';

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
      'Ta position n’est pas connue. Autorise Alvyo à l’utiliser dans les réglages de l’iPhone.';

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
  String get travelNoHomes =>
      'Ajoute un domicile dans ton compte pour planifier l’aller et le retour en transports publics.';

  @override
  String get travelPrivate => 'Toi seul vois ton aller et ton retour.';

  @override
  String get travelNoRoute => 'Dès qu’une étape a un itinéraire.';

  @override
  String get travelChoose => 'Choisis un domicile';

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
}
