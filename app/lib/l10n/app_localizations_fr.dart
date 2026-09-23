// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'odysgeh';

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
      'Aucune randonnée des 60 derniers jours dans Apple Health. Enregistre-les avec l\'app Exercice de l\'Apple Watch («Randonnée» ou «Marche en extérieur»). Si tu n\'as pas autorisé l\'accès : Réglages → Apps → Santé → Accès aux données et appareils → odysgeh.';

  @override
  String get watchUnavailable => 'Apple Santé n\'est pas disponible sur cet appareil.';

  @override
  String watchOutside(String reason) {
    return 'Non importé : $reason';
  }

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
}
