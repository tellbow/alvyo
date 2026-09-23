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
}
