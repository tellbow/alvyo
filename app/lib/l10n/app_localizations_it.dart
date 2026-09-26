// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Alvyo';

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

  @override
  String get navStart => 'Inizia l\'escursione';

  @override
  String get navResume => 'Riprendi l\'escursione';

  @override
  String get navDone => 'Percorso';

  @override
  String get navRemaining => 'Mancano';

  @override
  String get navElapsed => 'In cammino';

  @override
  String navOffRoute(int metres) {
    return 'A $metres m dal percorso';
  }

  @override
  String get navOffRouteTitle => 'Fuori percorso';

  @override
  String get navArrived => 'Arrivo raggiunto';

  @override
  String get navWaiting => 'In attesa del GPS …';

  @override
  String get navFinish => 'Termina';

  @override
  String get navFinishQuestion => 'Terminare l\'escursione e salvare la registrazione?';

  @override
  String get navContinue => 'Continua';

  @override
  String get navNoPermission => 'L\'app ha bisogno della tua posizione. Consentila nelle impostazioni.';

  @override
  String navSaved(String distance, String duration) {
    return 'Registrata: $distance in $duration. Verrà caricata appena sei online.';
  }

  @override
  String get navFollow => 'Segui la mia posizione';

  @override
  String navUploaded(String distance, String duration) {
    return 'Salvata in I miei percorsi: $distance in $duration';
  }

  @override
  String routesHiked(String date) {
    return 'Percorsa il $date';
  }

  @override
  String get watchTitle => 'Da Apple Watch';

  @override
  String get watchHike => 'Escursione';

  @override
  String get watchWalk => 'Camminata';

  @override
  String get watchImport => 'Importa';

  @override
  String get watchImported => 'Importata – in I miei percorsi';

  @override
  String get watchNoTrack => 'Questo allenamento non ha una traccia GPS.';

  @override
  String get watchEmpty =>
      'Nessuna escursione degli ultimi 60 giorni in Apple Salute. Registrale con l\'app Allenamento su Apple Watch («Escursionismo» o «Camminata all\'aperto»). Se non hai consentito l\'accesso: Impostazioni → App → Salute → Accesso ai dati e dispositivi → Alvyo.';

  @override
  String get watchUnavailable => 'Apple Salute non è disponibile su questo dispositivo.';

  @override
  String watchOutside(String reason) {
    return 'Non importata: $reason';
  }

  @override
  String get watchReasonOutside => 'esce dalla Svizzera e dal Liechtenstein.';

  @override
  String get watchReasonShort => 'è troppo corta.';

  @override
  String get turnSharpLeft => 'Svolta decisamente a sinistra';

  @override
  String get turnLeft => 'Svolta a sinistra';

  @override
  String get turnSlightLeft => 'Svolta leggermente a sinistra';

  @override
  String get turnKeepLeft => 'Tieni la sinistra';

  @override
  String get turnUTurn => 'Torna indietro';

  @override
  String get turnSlightRight => 'Svolta leggermente a destra';

  @override
  String get turnRight => 'Svolta a destra';

  @override
  String get turnSharpRight => 'Svolta decisamente a destra';

  @override
  String get turnKeepRight => 'Tieni la destra';

  @override
  String turnIn(int metres, String turn) {
    return 'Tra $metres metri, $turn';
  }

  @override
  String get navVoiceOn => 'Attiva gli annunci vocali';

  @override
  String get navVoiceOff => 'Disattiva gli annunci vocali';

  @override
  String get journeysTitle => 'Trekking a tappe';

  @override
  String get journeysEmpty => 'Ancora nessun trekking a tappe. Pianificali sul sito.';

  @override
  String get journeysOffline => 'Offline – solo trekking a tappe salvati';

  @override
  String journeyStagesCount(int done, int total) {
    return '$done tappe su $total';
  }

  @override
  String journeyStage(int n) {
    return 'Tappa $n';
  }

  @override
  String get journeyNoRoute => 'Ancora nessun percorso';

  @override
  String get statusDone => 'Percorsa';

  @override
  String get statusSkipped => 'Saltata';

  @override
  String gapWarning(String distance) {
    return '$distance di distanza dalla fine della tappa precedente';
  }

  @override
  String gapTransfer(String how) {
    return 'Collegata con $how';
  }

  @override
  String get transferPt => 'trasporti pubblici';

  @override
  String get transferCablecar => 'funivia';

  @override
  String get transferOther => 'altro mezzo';

  @override
  String stageAccommodation(String name) {
    return 'Alloggio: $name';
  }

  @override
  String get stageBooked => 'prenotato';

  @override
  String get journeySaveAll => 'Salva tutte le tappe offline';

  @override
  String journeySaving(int n, int total) {
    return 'Salvataggio della tappa $n di $total …';
  }

  @override
  String get journeySaved => 'Tutte le tappe salvate offline';

  @override
  String navSwitchQuestion(String title) {
    return 'Stai registrando «$title». Terminare questa escursione e iniziarne una nuova qui? Quanto registrato finora viene conservato.';
  }

  @override
  String get navSwitch => 'Termina e inizia qui';

  @override
  String get cancel => 'Annulla';

  @override
  String get stageMarkDone => 'Segna come fatta';

  @override
  String get stageMarkPlanned => 'Segna di nuovo come pianificata';

  @override
  String get navMarkStageDone => 'Segna la tappa come fatta';

  @override
  String get stageConflict => 'Qualcuno ha modificato la tappa nel frattempo. Ecco lo stato attuale.';

  @override
  String get stageMarkedDone => 'Tappa segnata come fatta';

  @override
  String get areasTitle => 'Zone protette lungo il percorso';

  @override
  String get areasWildlifeRest => 'zona di tranquillità';

  @override
  String get areasHuntingReserve => 'bandita federale di caccia';

  @override
  String get areasBinding => 'vincolante';

  @override
  String get areasRecommended => 'raccomandato';

  @override
  String areasPeriod(String from, String to) {
    return 'dal $from al $to';
  }

  @override
  String areasStages(String list) {
    return 'Tappa $list';
  }

  @override
  String liveSharedUntil(String time) {
    return 'Posizione condivisa · fine prevista alle $time';
  }

  @override
  String get liveLater => 'Più tardi';

  @override
  String get liveLaterFailed => 'Serve una connessione. Riprova tra un momento.';

  @override
  String get liveShareTitle => 'Condividi la posizione';

  @override
  String get liveShareIntro =>
      'I contatti scelti ricevono un link con la tua posizione. Se l\'escursione non è terminata 30 minuti dopo la fine prevista, ricevono un\'e-mail con l\'ultima posizione.';

  @override
  String get liveShareEnd => 'Fine prevista';

  @override
  String get liveShareStart => 'Condividi e parti';

  @override
  String get liveShareSkip => 'Senza condividere';

  @override
  String get liveShareFailed => 'La condivisione non è riuscita; l\'escursione viene registrata comunque.';

  @override
  String get liveNoContacts => 'Aggiungi i contatti sul sito web in «Account».';

  @override
  String get navRecord => 'Registra';

  @override
  String get navProfile => 'Profilo';

  @override
  String recordHint(String start) {
    return 'Scegli un percorso e tocca «$start» per registrare l\'escursione.';
  }

  @override
  String get mapLayers => 'Carte';

  @override
  String get mapHuts => 'Capanne';

  @override
  String get mapLodging => 'Alberghi e campeggi';

  @override
  String get placeHut => 'Capanna';

  @override
  String get placeHotel => 'Alloggio';

  @override
  String get placeCampsite => 'Campeggio';

  @override
  String get placeWildernessHut => 'Capanna non custodita';

  @override
  String get placePtStop => 'Fermata TP';

  @override
  String get placeAddress => 'Indirizzo';

  @override
  String get placeWebsite => 'Sito web';

  @override
  String get placeSearch => 'Cerca un luogo …';

  @override
  String get placeNothingFound => 'Nessun risultato.';

  @override
  String get plannerTitle => 'Pianifica un percorso';

  @override
  String get plannerHint => 'Cerca partenza e arrivo o tocca la carta.';

  @override
  String get plannerProfileHike => 'Escursionismo (fino a T3)';

  @override
  String get plannerProfileAlpine => 'Escursionismo alpino (fino a T6)';

  @override
  String get plannerPointMap => 'Punto sulla carta';

  @override
  String get plannerUp => 'Sposta su';

  @override
  String get plannerDown => 'Sposta giù';

  @override
  String get plannerRemove => 'Rimuovi';

  @override
  String get plannerSearchStart => 'Cerca la partenza …';

  @override
  String get plannerSearchEnd => 'Cerca l\'arrivo …';

  @override
  String get plannerSearchMore => 'Cerca un\'altra destinazione …';

  @override
  String get plannerLegNoPath => 'Nessun sentiero nelle vicinanze. Rimuovi il punto o scegline un altro.';

  @override
  String get plannerLegFailed => 'Questo tratto non ha potuto essere calcolato.';

  @override
  String get plannerRetry => 'Riprova';

  @override
  String get plannerAddPlace => 'Aggiungi come punto del percorso';

  @override
  String get plannerSave => 'Salva il percorso';

  @override
  String get plannerRouteTitle => 'Titolo';

  @override
  String get plannerSaveConfirm => 'Salva';

  @override
  String get plannerSaveFailed => 'Salvataggio non riuscito.';

  @override
  String get discoverAction => 'Scopri';

  @override
  String get discoverTitle => 'Scopri escursioni';

  @override
  String get discoverKindAll => 'Percorsi e trekking a tappe';

  @override
  String get discoverKindRoute => 'Solo percorsi';

  @override
  String get discoverKindJourney => 'Solo trekking a tappe';

  @override
  String get discoverSacAny => 'Qualsiasi difficoltà';

  @override
  String discoverSacMax(String grade) {
    return 'fino a $grade';
  }

  @override
  String get discoverDurationAny => 'Qualsiasi durata';

  @override
  String get discoverDurationShort => 'fino a 2 h';

  @override
  String get discoverDurationMedium => '2–4 h';

  @override
  String get discoverDurationLong => '4–6 h';

  @override
  String get discoverDurationXlong => 'oltre 6 h';

  @override
  String get discoverDurationHint => 'Per i trekking a tappe conta la tappa più lunga.';

  @override
  String get discoverRoute => 'Percorso';

  @override
  String get discoverJourney => 'Trekking a tappe';

  @override
  String discoverBy(String user) {
    return 'di $user';
  }

  @override
  String discoverStages(int n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n tappe', one: '1 tappa');
    return '$_temp0';
  }

  @override
  String discoverLongest(String time) {
    return 'la più lunga $time';
  }

  @override
  String get discoverEmpty => 'Qui non ci sono ancora escursioni pubbliche. Sposta la carta o allenta i filtri.';

  @override
  String get discoverMore => 'Ci sono altre escursioni – ingrandisci o affina i filtri.';

  @override
  String get discoverFailed => 'La ricerca non è riuscita. Riprova tra un attimo.';

  @override
  String get discoverOffline => 'Sei offline. Per scoprire escursioni serve una connessione.';

  @override
  String get discoverRetry => 'Riprova';
}
