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
  String get watchReasonOutside => 'va oltre 15 km dalla Svizzera e dal Liechtenstein.';

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

  @override
  String get jplanTitle => 'Pianifica un\'escursione a tappe';

  @override
  String get jplanIntro =>
      'Scegli partenza e arrivo – Alvyo divide il percorso in giorni che terminano in una capanna, un albergo, un campeggio o una fermata per tornare a casa.';

  @override
  String get jplanMapHint => 'Tocca la carta per mettere un punto, o cerca un luogo.';

  @override
  String get jplanPointMap => 'Punto sulla carta';

  @override
  String get jplanPointRemove => 'Rimuovi';

  @override
  String get jplanSearchStart => 'Cerca la partenza …';

  @override
  String get jplanSearchEnd => 'Cerca l\'arrivo …';

  @override
  String get jplanSearchMore => 'Cerca un\'altra destinazione …';

  @override
  String get jplanBy => 'Dividi per';

  @override
  String get jplanByDays => 'Numero di giorni';

  @override
  String get jplanByHours => 'Ore al giorno';

  @override
  String get jplanDays => 'Giorni';

  @override
  String get jplanHoursMin => 'Almeno ore al giorno';

  @override
  String get jplanHoursMax => 'Al massimo ore al giorno';

  @override
  String get jplanMax => 'Al massimo (h al giorno, vuoto: un po\' di più)';

  @override
  String get jplanKinds => 'Pernottare preferibilmente';

  @override
  String get jplanKindHut => 'in capanna';

  @override
  String get jplanKindHotel => 'in albergo o locanda';

  @override
  String get jplanKindCampsite => 'in campeggio';

  @override
  String get jplanKindPtStop => 'a una fermata (ritorno a casa)';

  @override
  String get jplanProfile => 'Profilo';

  @override
  String get jplanProfileHike => 'Escursionismo (fino a T3)';

  @override
  String get jplanProfileAlpine => 'Escursionismo alpino (fino a T6)';

  @override
  String get jplanSubmit => 'Proponi tappe';

  @override
  String get jplanSuggest => 'Proponi più percorsi';

  @override
  String get jplanRunning => 'Pianificazione …';

  @override
  String jplanDay(int n) {
    return 'Giorno $n';
  }

  @override
  String get jplanToEnd => 'fino all\'arrivo';

  @override
  String jplanEarlier(String place) {
    return 'Prima: $place';
  }

  @override
  String jplanLater(String place) {
    return 'Dopo: $place';
  }

  @override
  String get jplanOverMax => 'Più lungo del desiderato: prima non c\'è un posto dove dormire.';

  @override
  String get jplanUnderMin =>
      'Più corta del previsto: i luoghi per pernottare non permettono di suddividere meglio i giorni.';

  @override
  String get jplanHutHint =>
      'OpenStreetMap sa raramente se la capanna è aperta e se bisogna prenotare – verificalo prima.';

  @override
  String get jplanWebsite => 'Sito web';

  @override
  String get jplanFailed => 'La pianificazione non è riuscita. Riprova tra un momento.';

  @override
  String get jplanNoPath => 'Non c\'è un sentiero tra questi punti con questo profilo.';

  @override
  String jplanSummary(int days, String distance) {
    String _temp0 = intl.Intl.pluralLogic(days, locale: localeName, other: '$days giorni', one: '1 giorno');
    return '$_temp0 · $distance';
  }

  @override
  String get jplanWays => 'Percorsi';

  @override
  String jplanWay(int n) {
    return 'Percorso $n';
  }

  @override
  String jplanWayDirect(int n) {
    return 'Percorso $n: diretto';
  }

  @override
  String jplanWayVia(int n, String place) {
    return 'Percorso $n: via $place';
  }

  @override
  String get jplanWaysHint => 'Dove due percorsi pernottano nello stesso luogo, lì puoi passare dall’uno all’altro.';

  @override
  String jplanSwitch(int n) {
    return 'Da qui, continua sul percorso $n';
  }

  @override
  String get jplanTitleField => 'Titolo';

  @override
  String get jplanCreate => 'Crea escursione a tappe';

  @override
  String get delete => 'Elimina';

  @override
  String get routeDeleteConfirm => 'Eliminare l\'itinerario? Non si può annullare.';

  @override
  String get journeyDeleteConfirm =>
      'Eliminare l\'escursione a tappe con tutte le tappe e gli itinerari? Non si può annullare.';

  @override
  String jplanTooLong(String hours, int days) {
    return 'Non è possibile con al massimo $hours h al giorno: servono almeno $days giorni.';
  }

  @override
  String jplanTooLongNone(String hours) {
    return 'Non è possibile con al massimo $hours h al giorno: lungo il percorso ci sono troppo pochi posti dove dormire.';
  }

  @override
  String jplanPlanIn(int days) {
    return 'Pianifica in $days giorni';
  }

  @override
  String get navFeed => 'Novità';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get themeTitle => 'Aspetto';

  @override
  String get themeSystem => 'Automatico';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get languageTitle => 'Lingua';

  @override
  String get profileMine => 'Il mio profilo';

  @override
  String get accountNotifications => 'Notifiche via e-mail';

  @override
  String get accountNotifyComments => 'Quando qualcuno commenta i miei percorsi e trekking a tappe';

  @override
  String get accountNotifyFollows => 'Quando qualcuno mi segue';

  @override
  String get contactsTitle => 'Contatti per le escursioni condivise';

  @override
  String get contactsIntro =>
      'Quando inizi un\'escursione nell\'app, puoi mostrare la tua posizione ai contatti scelti. Se l\'escursione non è terminata 30 minuti dopo la fine prevista, ricevono un\'e-mail con l\'ultima posizione.';

  @override
  String get contactsName => 'Nome';

  @override
  String get contactsEmail => 'E-mail';

  @override
  String get contactsAdd => 'Aggiungi';

  @override
  String get contactsRemove => 'Rimuovi';

  @override
  String get contactsDuplicate => 'Questo indirizzo è già un contatto.';

  @override
  String get contactsFull => 'Al massimo 10 contatti.';

  @override
  String get blockedTitle => 'Persone bloccate';

  @override
  String get blockedEmpty => 'Non hai bloccato nessuno.';

  @override
  String get accountDeleteTitle => 'Elimina account';

  @override
  String get accountDeleteText =>
      'Elimina definitivamente il tuo account e tutti i tuoi percorsi. I link condivisi non funzioneranno più.';

  @override
  String get accountDeleteSubmit => 'Elimina definitivamente l\'account';

  @override
  String get accountDeleteWrong => 'La password è errata.';

  @override
  String get accountDeleteRecent =>
      'Il tuo account non ha una password: per confermare devi aver effettuato l\'accesso negli ultimi 15 minuti.';

  @override
  String get accountDeleteLoginAgain => 'Accedi di nuovo e riprova subito dopo.';

  @override
  String get loginForgot => 'Password dimenticata?';

  @override
  String get loginSignup => 'Crea un account';

  @override
  String get myMapTitle => 'Mappa delle mie escursioni';

  @override
  String get myMapEmpty => 'In questa vista nulla corrisponde ai filtri.';

  @override
  String get feedIntro => 'Le nuove escursioni pubbliche delle persone che segui.';

  @override
  String get feedEmpty => 'Ancora niente – segui le persone le cui escursioni ti interessano. Le trovi in Scopri.';

  @override
  String get feedMore => 'Carica le precedenti';

  @override
  String profileSince(String date) {
    return 'iscritto/a da $date';
  }

  @override
  String profileFollowers(int n) {
    return '$n follower';
  }

  @override
  String profileFollowing(int n) {
    return 'segue $n';
  }

  @override
  String get profileFollow => 'Segui';

  @override
  String get profileUnfollow => 'Non seguire più';

  @override
  String get profileBlock => 'Blocca';

  @override
  String get profileUnblock => 'Sblocca';

  @override
  String get profileBlockedNote =>
      'Bloccato/a: questa persona non può commentare le tue escursioni né seguirti, e tu non vedi i suoi commenti.';

  @override
  String get profileRoutes => 'Percorsi';

  @override
  String get profileJourneys => 'Trekking a tappe';

  @override
  String get reportAction => 'Segnala';

  @override
  String get reportReason => 'Motivo';

  @override
  String get reportReasonSpam => 'Spam o pubblicità';

  @override
  String get reportReasonOffensive => 'Offensivo o inappropriato';

  @override
  String get reportReasonDangerous => 'Pericoloso o sbagliato';

  @override
  String get reportReasonOther => 'Altro';

  @override
  String get reportNote => 'Che cosa non va? (facoltativo)';

  @override
  String get reportThanks => 'Grazie, ce ne occuperemo.';

  @override
  String get editAction => 'Modifica';

  @override
  String get save => 'Salva';

  @override
  String get saveConflict =>
      'Nel frattempo qualcuno l’ha modificato. Ecco la nuova versione – la tua modifica non è salvata.';

  @override
  String get fieldTitle => 'Titolo';

  @override
  String get fieldDescription => 'Descrizione';

  @override
  String get fieldVisibility => 'Visibilità';

  @override
  String get visibilityPrivate => 'Privato';

  @override
  String get visibilityUnlisted => 'Condividi con link';

  @override
  String get visibilityPublic => 'Pubblico';

  @override
  String get visibilityNeedsVerify => 'Conferma il tuo indirizzo e-mail per pubblicare percorsi.';

  @override
  String get tagsLabel => 'Etichette';

  @override
  String get tagsHint => 'Separati da virgole';

  @override
  String ownerBy(String user) {
    return 'di $user';
  }

  @override
  String get shareAction => 'Condividi';

  @override
  String get shareLink => 'Link da condividere';

  @override
  String get shareSend => 'Invia il link …';

  @override
  String get shareCopied => 'Copiato';

  @override
  String get shareLinkHint => 'Scegli «Condividi con link» o «Pubblico» per inviare un link.';

  @override
  String get shareRotate => 'Crea un nuovo link';

  @override
  String get shareRotateHint => 'Il link precedente non funzionerà più.';

  @override
  String get sharePeople => 'Condividi con persone';

  @override
  String get sharePending => 'invitato/a';

  @override
  String get shareRemove => 'Rimuovi accesso';

  @override
  String get shareWho => 'Nome utente o indirizzo e-mail';

  @override
  String get shareInvite => 'Invita';

  @override
  String get shareHint =>
      'Le persone invitate ricevono un\'e-mail. Chi non ha ancora un account si registra con quell\'indirizzo.';

  @override
  String get shareNeedsVerify => 'Conferma il tuo indirizzo e-mail per condividere con altri.';

  @override
  String get shareRate => 'Troppi inviti – riprova più tardi.';

  @override
  String get shareNoUser => 'Questo nome utente non esiste.';

  @override
  String get shareSelf => 'Non puoi invitare te stesso.';

  @override
  String get shareTooMany => 'Troppe persone hanno già accesso.';

  @override
  String get shareBadEmail => 'Indirizzo e-mail non valido.';

  @override
  String get roleViewer => 'Può vedere';

  @override
  String get roleEditor => 'Può pianificare';

  @override
  String get sharedTitle => 'Condivisi con me';

  @override
  String get gpxRoute => 'Condividi GPX …';

  @override
  String get gpxJourney => 'Condividi tutte le tappe come GPX (ZIP) …';

  @override
  String get photosTitle => 'Foto';

  @override
  String get photosAdd => 'Aggiungi foto';

  @override
  String get photosCamera => 'Scatta una foto';

  @override
  String get photosLibrary => 'Dalla libreria';

  @override
  String photosUploading(int done, int total) {
    return '$done di $total caricate …';
  }

  @override
  String get photosHint =>
      'JPEG, PNG, WebP o HEIC fino a 20 MB. Rimuoviamo tutti i metadati; le foto scattate lungo il percorso appaiono sulla carta.';

  @override
  String get photosProblemFormat => 'non è un\'immagine JPEG, PNG, WebP o HEIC';

  @override
  String get photosProblemSize => 'troppo grande (al massimo 20 MB)';

  @override
  String get photosProblemLimit => 'troppe foto (al massimo 100 per escursione e 1000 per persona)';

  @override
  String get photosProblemRate => 'troppi caricamenti – riprova tra un attimo';

  @override
  String get photosProblemOther => 'caricamento non riuscito';

  @override
  String get photosCaption => 'Didascalia';

  @override
  String photosBy(String user) {
    return 'di $user';
  }

  @override
  String get photosDelete => 'Elimina';

  @override
  String get photosDeleteConfirm => 'Eliminare davvero?';

  @override
  String get communityLike => 'Mi piace';

  @override
  String communityLikes(int n) {
    return '$n mi piace';
  }

  @override
  String communityComments(int n) {
    return '$n commenti';
  }

  @override
  String get communityCommentsAllowed => 'Consenti commenti';

  @override
  String get communityCommentsOff => 'I commenti sono disattivati.';

  @override
  String get communityCommentPlaceholder => 'Scrivi un commento …';

  @override
  String get communityCommentSend => 'Commenta';

  @override
  String get communityReply => 'Rispondi';

  @override
  String get communityReplyPlaceholder => 'La tua risposta …';

  @override
  String get communityEdited => 'modificato';

  @override
  String get communityRate => 'Troppo veloce – riprova tra un attimo.';

  @override
  String get communityVerifyToComment => 'Conferma il tuo indirizzo e-mail per commentare.';

  @override
  String get stageEdit => 'Modifica la tappa';

  @override
  String get stageDate => 'Data';

  @override
  String get stageDateNone => 'Nessuna data';

  @override
  String get stageStatus => 'Stato';

  @override
  String get statusPlanned => 'Prevista';

  @override
  String get stageAccommodationLabel => 'Alloggio';

  @override
  String get stageAccommodationPlaceholder => 'p. es. Albergo Alpino';

  @override
  String get stageBookedLabel => 'Prenotato';

  @override
  String get stageNotes => 'Note';

  @override
  String get stageTransfer => 'Collegata con';

  @override
  String get transferNone => '–';

  @override
  String get sbbToStart => 'Orario FFS: andata';

  @override
  String get sbbFromEnd => 'Orario FFS: ritorno';

  @override
  String get sbbTransfer => 'Orario FFS';

  @override
  String get connectionsShow => 'Mostra collegamenti';

  @override
  String get connectionsDepart => 'Partenza';

  @override
  String get connectionsArrive => 'Arrivo';

  @override
  String get connectionsSearch => 'Cerca';

  @override
  String get connectionsNone => 'Nessun collegamento trovato.';

  @override
  String get connectionsUnavailable => 'L\'orario non è disponibile al momento – usa l\'orario FFS.';

  @override
  String connectionsTransfers(int n) {
    return '$n cambi';
  }

  @override
  String connectionsWalk(int min) {
    return '$min min a piedi';
  }

  @override
  String connectionsPlatform(String p) {
    return 'Bin./corsia $p';
  }

  @override
  String get connectionsSource => 'Dati d\'orario: opentransportdata.swiss';

  @override
  String get collectionsTitle => 'Raccolte';

  @override
  String get collectionsIntro =>
      'Raccogli percorsi e trekking a tappe – come lista dei desideri, raccolta di idee o per condividerli. Una raccolta non dà accesso: ognuno vede solo ciò che può già aprire.';

  @override
  String get collectionsEmpty => 'Ancora nessuna raccolta.';

  @override
  String get collectionNew => 'Nuova raccolta';

  @override
  String collectionItemsCount(int n) {
    return '$n elementi';
  }

  @override
  String get collectionEmpty =>
      'Ancora vuota. Aggiungi percorsi e trekking a tappe dal loro menu: «Aggiungi a una raccolta …».';

  @override
  String get collectionAddTo => 'Aggiungi a una raccolta …';

  @override
  String collectionAdded(String title) {
    return 'Aggiunto a «$title»';
  }

  @override
  String collectionAlready(String title) {
    return 'Già in «$title»';
  }

  @override
  String get collectionRemoveItem => 'Rimuovi';

  @override
  String get collectionDelete => 'Elimina raccolta';

  @override
  String get collectionDeleteConfirm => 'Eliminare la raccolta? Percorsi e trekking restano.';

  @override
  String collectionStages(int n) {
    return '$n tappe';
  }

  @override
  String get myMapKindHike => 'Escursioni fatte';

  @override
  String get connectionsFromHere => 'Collegamenti da qui alla partenza';

  @override
  String get connectionsNoPosition =>
      'La tua posizione non è nota. Consenti ad Alvyo di usarla nelle impostazioni dell’iPhone.';

  @override
  String get stageMore => 'Dettagli e come arrivare';

  @override
  String get travelTitle => 'Andata e ritorno';

  @override
  String get travelTo => 'Andata';

  @override
  String get travelBack => 'Ritorno';

  @override
  String get travelFrom => 'Da';

  @override
  String get travelToHome => 'A';

  @override
  String get travelNone => '– nessuno –';

  @override
  String travelOn(String date) {
    return 'il $date';
  }

  @override
  String get travelNoDate => 'La tappa non ha una data: collegamenti di oggi.';

  @override
  String get travelNoHomes => 'Aggiungi nel tuo account una casa che ti serve spesso.';

  @override
  String get travelPrivate => 'Solo tu vedi la tua andata e il tuo ritorno.';

  @override
  String get travelNoRoute => 'Appena una tappa ha un percorso.';

  @override
  String get travelChoose => 'Da dove e quando';

  @override
  String get homesTitle => 'Case';

  @override
  String get homesIntro =>
      'Da qui pianifichi l’andata verso i tuoi trekking a tappe e il ritorno con i mezzi pubblici. Al massimo 5; solo tu le vedi.';

  @override
  String get homesName => 'Nome';

  @override
  String get homesNamePlaceholder => 'p. es. Casa, Ufficio';

  @override
  String get homesAddress => 'Cerca un indirizzo …';

  @override
  String get homesAdd => 'Aggiungi';

  @override
  String get homesRemove => 'Rimuovi';

  @override
  String get homesFull => 'Al massimo 5 case.';

  @override
  String get travelStart => 'Partenza del trekking';

  @override
  String get travelEnd => 'Arrivo del trekking';

  @override
  String get recordTitle => 'Escursione';

  @override
  String get recordStart => 'Avvia la registrazione';

  @override
  String get recordRefused =>
      'Non salvata: l\'escursione è troppo corta o va oltre 15 km dalla Svizzera e dal Liechtenstein.';

  @override
  String get barRoutes => 'Percorsi';

  @override
  String get barJourneys => 'Tappe';

  @override
  String get planAction => 'Pianifica';

  @override
  String get routePrivacyOwner => 'Gli altri vedono questa escursione senza i primi e gli ultimi 500 m.';

  @override
  String get routePrivacyOthers => 'La partenza e l\'arrivo dell\'escursione sono nascosti.';

  @override
  String get routePrivacyAll =>
      'Questa escursione è troppo corta per mostrarla agli altri: partenza e arrivo sono nascosti.';

  @override
  String plannerAlpineShorter(String alpine, String hike) {
    return 'Con «Escursionismo alpino» solo $alpine invece di $hike.';
  }

  @override
  String plannerAlpineGrade(String grade) {
    return 'La via più corta passa su $grade.';
  }

  @override
  String get plannerAlpineUse => 'Pianifica questo tratto come alpino';

  @override
  String get plannerAlpineUsed => 'Pianificato con «Escursionismo alpino».';

  @override
  String get plannerAlpineUndo => 'Torna all\'escursione';

  @override
  String get noticesTitle => 'Chiusure e tiri';

  @override
  String get noticesClosure => 'sentiero chiuso';

  @override
  String get noticesShooting => 'tiri dell\'esercito';

  @override
  String get mapPois => 'Lungo il cammino';

  @override
  String get poiPeak => 'Cima';

  @override
  String get poiViewpoint => 'Punto panoramico';

  @override
  String get poiWaterfall => 'Cascata';

  @override
  String get poiWater => 'Acqua potabile';

  @override
  String get poiShelter => 'Riparo';

  @override
  String get mapBase => 'Sfondo';

  @override
  String get mapOverlays => 'Sovrapposizioni';

  @override
  String get mapBaseNational => 'Carta nazionale';

  @override
  String get mapBaseGrey => 'Carta nazionale grigia';

  @override
  String get mapBaseAerial => 'Immagine aerea';

  @override
  String get mapOverlayTrails => 'Sentieri escursionistici';

  @override
  String get mapOverlayWanderland => 'Percorsi escursionistici SvizzeraMobile';

  @override
  String get mapOverlaySlope => 'Pendenza oltre 30°';

  @override
  String get mapOverlayRestAreas => 'Zone di tranquillità';

  @override
  String get mapOverlayHuntingReserves => 'Bandite federali di caccia';

  @override
  String get mapOverlayRelief => 'Rilievo';

  @override
  String get poiFirepit => 'Focolare';

  @override
  String get poiPicnic => 'Area picnic';

  @override
  String get poiRestaurant => 'Ristorante, caffè';

  @override
  String get poiToilets => 'Servizi igienici';

  @override
  String get poiCablecar => 'Stazione della funivia';

  @override
  String get poisTitle => 'Lungo il cammino';

  @override
  String poisAll(int count) {
    return 'Mostra tutti i $count';
  }

  @override
  String get weatherTitle => 'Meteo';

  @override
  String get weatherStart => 'Partenza';

  @override
  String get weatherTop => 'Punto più alto';

  @override
  String get weatherEnd => 'Arrivo';

  @override
  String get weatherToday => 'Oggi';

  @override
  String get weatherDry => 'asciutto';

  @override
  String weatherRain(String mm, String lo, String hi) {
    return '$mm mm di precipitazioni ($lo–$hi mm)';
  }

  @override
  String weatherSource(String time) {
    return 'Previsione di MeteoSvizzera per il luogo vicino di quota più simile, delle $time.';
  }

  @override
  String weatherStage(int n, String date) {
    return 'Tappa $n, $date';
  }

  @override
  String get travelElsewhere => 'Altro luogo …';

  @override
  String get travelPlaceSearch => 'Luogo, fermata o indirizzo';

  @override
  String get travelDay => 'Il';

  @override
  String get travelRouteStart => 'Partenza';

  @override
  String get travelRouteEnd => 'Arrivo';

  @override
  String get areasNow => 'in vigore ora';

  @override
  String get areasOnDate => 'in vigore in un giorno pianificato';

  @override
  String hintsOpen(int count) {
    return 'Mostra ($count)';
  }

  @override
  String get weatherOtherDay => 'Altra data';

  @override
  String weatherClimate(String month, String min, String max, String days, String total, String mm) {
    return 'Di solito a $month: $min–$max °C, pioggia in $days giorni su $total, $mm mm nel mese';
  }

  @override
  String weatherClimateSource(String station, String rain) {
    return 'Ancora nessuna previsione per questo giorno: valori climatici normali 1991–2020 di MeteoSvizzera (temperatura: $station, riportata all’altitudine; precipitazioni: $rain). La previsione copre i prossimi 9 giorni.';
  }

  @override
  String get journeyMap => 'Mappa del trekking a tappe';

  @override
  String get journeyAddStage => 'Aggiungi tappa';

  @override
  String get routeEditLine => 'Modifica sulla mappa';

  @override
  String get bugOpen => 'Segnala un errore';

  @override
  String get bugWhat => 'Cos’è successo? Cosa ti aspettavi?';

  @override
  String get bugWithScreenshot => 'Invia uno screenshot';

  @override
  String get bugScreenshotAlt => 'Screenshot di questa pagina';

  @override
  String bugPrivacy(String place) {
    return 'La segnalazione invia l’indirizzo ($place), la versione, il tuo nome utente e lo screenshot agli sviluppatori (GitHub). Lo screenshot resta presso Alvyo e viene eliminato con il tuo account.';
  }

  @override
  String get bugSend => 'Invia';

  @override
  String get bugSent => 'Grazie! L’errore è segnalato.';

  @override
  String get bugFailed => 'Non ha funzionato. Riprova più tardi.';

  @override
  String get bugBusy => 'Oggi hai già segnalato diversi errori. Riprova più tardi.';

  @override
  String get close => 'Chiudi';

  @override
  String get peopleTitle => 'Chi viene';

  @override
  String get peopleNone => 'Ancora nessuno. Chi viene vede il trekking e le tappe a cui partecipa.';

  @override
  String get peopleInvited => 'Invitato/a';

  @override
  String get peopleRemove => 'Non viene';

  @override
  String get peopleWho => 'Nome utente o indirizzo e-mail';

  @override
  String get peopleAdd => 'Aggiungi';

  @override
  String get peopleHint =>
      'Chi non ha ancora accesso viene invitato e può vedere il trekking. I numeri sono le tappe: tocca chi partecipa a quale.';

  @override
  String get peopleUnknown => 'Questa persona non esiste, oppure sei tu.';

  @override
  String get peopleVerify => 'Conferma prima il tuo indirizzo e-mail.';

  @override
  String get peopleFailed => 'Non ha funzionato. Riprova.';

  @override
  String peopleOnStage(String names) {
    return 'Con $names';
  }

  @override
  String peopleStages(String name) {
    return 'Tappe di $name';
  }

  @override
  String get remindersTitle => 'Promemoria';

  @override
  String get remindersOn => 'Promemoria via e-mail prima della partenza';

  @override
  String get remindersHint => 'Per te e per chi viene; nell’app anche sul telefono.';

  @override
  String get reminderBook => 'Si parte tra tre settimane: tutte le notti sono prenotate?';

  @override
  String get reminderWeather => 'Si parte dopodomani: dai un’occhiata al meteo.';

  @override
  String get reminderStart => 'Si parte domani. Buon cammino!';
}
