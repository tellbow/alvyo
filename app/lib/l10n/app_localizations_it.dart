// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'odysgeh';

  @override
  String get loginTitle => 'Accedi';

  @override
  String get server => 'Server';

  @override
  String get login => 'E-mail o nome utente';

  @override
  String get password => 'Password';

  @override
  String get loginSubmit => 'Accedi';

  @override
  String get loginInvalid => 'E-mail/nome utente o password errati.';

  @override
  String get errorGeneric => 'Qualcosa è andato storto. Riprova.';

  @override
  String get errorServer => 'Il server non è raggiungibile.';

  @override
  String get routesTitle => 'I miei percorsi';

  @override
  String get routesEmpty => 'Ancora nessun percorso. Pianificali sul sito.';

  @override
  String get logout => 'Esci';

  @override
  String get offlineSave => 'Salva offline';

  @override
  String get offlineSaved => 'Salvato offline – rimuovi';

  @override
  String get offlinePreparing => 'Preparazione della mappa offline …';

  @override
  String get offlineDownloading => 'Download della mappa offline …';

  @override
  String get offlineOutdated => 'Percorso modificato – aggiorna la mappa offline';

  @override
  String get offlineFailed => 'Non è stato possibile salvare la mappa offline.';

  @override
  String get routesOffline => 'Offline – solo percorsi salvati';
}
