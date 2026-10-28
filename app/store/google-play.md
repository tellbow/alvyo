# Google Play: the first release

What Play Console needs for Alvyo, in its order, with the texts to paste.
Play Console's labels are German here, as in the account; the left menu
has four sections (Testen und veröffentlichen, Beobachten und verbessern,
Nutzer gewinnen, Mit Play Geld verdienen), and the search field at the
top finds every page by name. The Dashboard's «App einrichten» list links
to most of them. After the first
production release, releases go through the API: the `play-store` skill.

The account is personal and opened after 2023-11-13, so Google lets the
app into production only after a closed test with at least 12 testers for
14 days in a row (step 6). Plan about three weeks: a day or two of review
for the closed test, the 14 days, up to a week for the production access
and the first review.

## 1. The first bundle, on «Interner Test»

Testen und veröffentlichen › Tests › Interner Test › «Neuen Release erstellen».

1. **App-Signatur** (decided on 2026-10-28): «App-Signaturschlüssel von
   Google verwalten und schützen lassen». Google signs what Play installs;
   the release key (`app/android/key.properties`, the GitHub APKs) is only
   the upload key, which Google can reset if it is lost or leaks. So the
   Play app and a GitHub APK cannot update each other: a phone with the
   APK uninstalls it first. The SHA-256 of Google's app signing key
   (Protected with Play › App-Signatur) is the second fingerprint in
   `web/static/.well-known/assetlinks.json`, for the app links.
2. **App Bundles:** the bundle from `.claude/skills/play-store/build.sh`
   (on a release tag).
3. **Release-Name:** the version, e.g. `1.13.0`.
4. **Versionshinweise:** the «Was ist neu» line of the version
   (`news_X_Y_Z` in `web/messages/*.json`), for 1.13.0:
   ```
   <de-DE>
   Jede Karte zeigt jetzt, wo du bist, in der App und auf der Website, sobald du den Standort erlaubst. Ein Tipp auf «Mein Standort» bringt die Karte dorthin. Und «Fehler melden» klappt wieder auch auf einer Karte.
   </de-DE>
   <en-US>
   Every map now shows where you are, in the app and on the website, once you allow the location. A tap on «My location» takes the map there. And «Report a bug» works again on a map too.
   </en-US>
   <fr-FR>
   Chaque carte montre maintenant où tu es, dans l’app et sur le site, dès que tu autorises la position. Un tap sur «Ma position» y amène la carte. Et «Signaler un bug» fonctionne de nouveau aussi sur une carte.
   </fr-FR>
   <it-IT>
   Ogni mappa ora mostra dove sei, nell’app e sul sito, appena consenti la posizione. Un tocco su «La mia posizione» porta lì la mappa. E «Segnala un errore» funziona di nuovo anche su una mappa.
   </it-IT>
   ```
5. «Weiter» › «Speichern und veröffentlichen». Under «Tester» an e-mail
   list with your own Google account; its link installs the app from Play.

The bundle must not ask for the advertising id (`build.sh` checks it):
then the declaration «Werbe-ID» (step 3) is «Nein».

## 2. The store listing

Nutzer gewinnen › Store-Präsenz › Store-Einträge › «Hauptversion des Store-Eintrags».
«Übersetzungen verwalten» › «Eigene Übersetzungen hinzufügen»: Deutsch
(de-DE, the default language), English (United States) en-US, Französisch
fr-FR, Italienisch it-IT; each language gets its own texts and pictures.

**Pictures** (made by `bun app/store/render.mjs de,en,fr,it play`, see
README.md; the icon by the command there):

| Field | File | Size |
|---|---|---|
| App-Symbol (one for all languages) | `app/store/work/play-icon.png` | 512 × 512, 32-bit PNG |
| Vorstellungsgrafik | `app/store/<language>/play/feature.jpg` | 1024 × 500 |
| Smartphone-Screenshots | `app/store/<language>/play/01-route.jpg` … `06-discover.jpg`, in that order | 1242 × 2208 |
| Tablet-Assets | none yet: Play takes 16:9 or 9:16 only, the iPad pictures are 3:4 | |

The phone screenshots are the iPhone captures without the iOS status bar:
the same Flutter screens. None shows what Android does not have yet
(«Berge erkennen», the watch).

### Deutsch (de-DE)

**App-Name** (30/30)
```
Alvyo – Wandern in der Schweiz
```
**Kurzbeschreibung** (76/80)
```
Wandern in der Schweiz: Landeskarte, Wanderzeit, offline navigieren, Etappen
```
**Vollständige Beschreibung** (1501/4000)
```
Alvyo ist eine Wander-App für die Schweiz: Touren planen, Wanderungen aufzeichnen und vieles mehr.

PLANEN
  • Routen auf der Landeskarte von swisstopo, entlang der Wanderwege
  • Wanderzeit wie auf den gelben Wegweisern, auf Wunsch in deinem eigenen Tempo
  • Schwierigkeit nach SAC-Skala (T1–T6), Höhenprofil, Wegbeläge
  • Wetter, Wegsperrungen und Schutzgebiete entlang der Route
  • Reichweite: wie weit du in 2, 4 oder 8 Stunden kommst

UNTERWEGS
  • Die Landeskarte offline – auch ohne Netz in den Bergen
  • Navigation mit gesprochenen Anweisungen, auch bei gesperrtem Bildschirm
  • Warnung, wenn du vom Weg abkommst
  • Wanderungen aufzeichnen, mit Strecke, Zeit und Höhenmetern
  • Live-Standort für Vertraute und eine Nachricht an sie, wenn du dich verspätest

ETAPPENTOUREN
  • Mehrtägige Touren aus Start, Ziel und Anzahl Tagen
  • Hütten für die Nächte und der öffentliche Verkehr zu Beginn und am Ende jeder Etappe
  • Alle Etappen auf einmal offline speichern

TEILEN UND ENTDECKEN
  • Touren öffentlich, per Link oder auf Einladung teilen
  • Sammlungen, Freunde, Kommentare und Fotos
  • Öffentliche Wanderungen anderer auf der Karte entdecken
  • Import aus GPX, KML, TCX und FIT, Export als GPX

Alvyo ist kostenlos und quelloffen, auf Deutsch, Englisch, Französisch und Italienisch. Für die App brauchst du ein kostenloses Konto, das du in der App oder auf alvyo.tellbow.ch erstellst. Planen geht in der App und im Browser.

Kartendaten: © swisstopo, © OpenStreetMap-Mitwirkende.
```

### English (en-US)

**App-Name** (29/30)
```
Alvyo – Hiking in Switzerland
```
**Kurzbeschreibung** (77/80)
```
Hiking in Switzerland: national map, hiking times, offline navigation, stages
```
**Vollständige Beschreibung** (1400/4000)
```
Alvyo is a hiking app for Switzerland: plan routes, record hikes and much more.

PLAN
  • Routes on swisstopo's national map, along the hiking trails
  • Hiking time as on the yellow signposts, or at your own pace
  • Difficulty on the SAC scale (T1–T6), elevation profile, trail surfaces
  • Weather, trail closures and protected areas along the route
  • Reach: how far you get in 2, 4 or 8 hours

ON THE WAY
  • The national map offline – even without a signal in the mountains
  • Navigation with spoken directions, also with the screen locked
  • A warning when you leave the trail
  • Record hikes, with distance, time and elevation gain
  • Live location for people you trust, and a message to them if you are running late

JOURNEYS
  • Multi-day hikes from a start, a destination and a number of days
  • Huts for the nights, and public transport at the start and end of each stage
  • Save all stages offline at once

SHARE AND DISCOVER
  • Share routes publicly, by link or by invitation
  • Collections, friends, comments and photos
  • Discover other people's public hikes on the map
  • Import from GPX, KML, TCX and FIT, export as GPX

Alvyo is free and open source, in German, English, French and Italian. The app needs a free account, which you create in the app or at alvyo.tellbow.ch. You can plan in the app and in the browser.

Map data: © swisstopo, © OpenStreetMap contributors.
```

### Français (fr-FR)

**App-Name** (27/30)
```
Alvyo – Randonnée en Suisse
```
**Kurzbeschreibung** (77/80)
```
Randonnée en Suisse : carte nationale, temps de marche, navigation hors ligne
```
**Vollständige Beschreibung** (1642/4000)
```
Alvyo est une app de randonnée pour la Suisse : planifier des itinéraires, enregistrer des randonnées et bien plus encore.

PLANIFIER
  • Itinéraires sur la carte nationale de swisstopo, le long des chemins de randonnée
  • Temps de marche comme sur les indicateurs jaunes, ou à ton propre rythme
  • Difficulté selon l'échelle CAS (T1–T6), profil altimétrique, nature du chemin
  • Météo, fermetures de chemins et zones protégées le long de l'itinéraire
  • Portée : jusqu'où tu vas en 2, 4 ou 8 heures

EN CHEMIN
  • La carte nationale hors ligne – même sans réseau en montagne
  • Navigation avec instructions vocales, même écran verrouillé
  • Un avertissement quand tu t'écartes du chemin
  • Enregistrer des randonnées, avec distance, temps et dénivelé
  • Position en direct pour tes proches, et un message pour eux si tu as du retard

RANDONNÉES PAR ÉTAPES
  • Randonnées de plusieurs jours à partir d'un départ, d'une arrivée et d'un nombre de jours
  • Cabanes pour les nuits et transports publics au début et à la fin de chaque étape
  • Enregistrer toutes les étapes hors ligne d'un coup

PARTAGER ET DÉCOUVRIR
  • Partager tes randonnées publiquement, par lien ou sur invitation
  • Collections, ami·e·s, commentaires et photos
  • Découvrir sur la carte les randonnées publiques des autres
  • Import depuis GPX, KML, TCX et FIT, export en GPX

Alvyo est gratuit et open source, en allemand, anglais, français et italien. L'app nécessite un compte gratuit, que tu crées dans l'app ou sur alvyo.tellbow.ch. Tu peux planifier dans l'app et dans le navigateur.

Données cartographiques : © swisstopo, © contributeurs OpenStreetMap.
```

### Italiano (it-IT)

**App-Name** (30/30)
```
Alvyo – Escursioni in Svizzera
```
**Kurzbeschreibung** (77/80)
```
Escursioni in Svizzera: carta nazionale, tempi di marcia, navigazione offline
```
**Vollständige Beschreibung** (1530/4000)
```
Alvyo è un'app per l'escursionismo in Svizzera: pianifica percorsi, registra escursioni e molto altro.

PIANIFICARE
  • Percorsi sulla carta nazionale di swisstopo, lungo i sentieri escursionistici
  • Tempi di marcia come sui cartelli gialli, o al tuo ritmo
  • Difficoltà secondo la scala CAS (T1–T6), profilo altimetrico, fondo del sentiero
  • Meteo, chiusure dei sentieri e zone protette lungo il percorso
  • Portata: fin dove arrivi in 2, 4 o 8 ore

IN CAMMINO
  • La carta nazionale offline – anche senza rete in montagna
  • Navigazione con indicazioni vocali, anche a schermo bloccato
  • Un avviso quando esci dal sentiero
  • Registrare escursioni, con distanza, tempo e dislivello
  • Posizione in tempo reale per le persone di fiducia, e un messaggio per loro se sei in ritardo

TREKKING A TAPPE
  • Escursioni di più giorni a partire da partenza, arrivo e numero di giorni
  • Capanne per la notte e trasporti pubblici all'inizio e alla fine di ogni tappa
  • Salvare tutte le tappe offline in una volta

CONDIVIDERE E SCOPRIRE
  • Condividere le escursioni pubblicamente, tramite link o su invito
  • Raccolte, amici, commenti e foto
  • Scoprire sulla carta le escursioni pubbliche degli altri
  • Importazione da GPX, KML, TCX e FIT, esportazione in GPX

Alvyo è gratuita e open source, in tedesco, inglese, francese e italiano. L'app richiede un account gratuito, che crei nell'app o su alvyo.tellbow.ch. Puoi pianificare nell'app e nel browser.

Dati cartografici: © swisstopo, © contributori di OpenStreetMap.
```

## 3. App content

Beobachten und verbessern › Richtlinien und Programme › App-Inhalte
(search «App-Inhalte»). Each one «Starten», then «Speichern».

- **Datenschutzerklärung:** `https://alvyo.tellbow.ch/about#privacy`
- **Anzeigen:** «Nein, meine App enthält keine Werbung».
- **App-Zugriff:** «Alle oder einige Funktionen sind eingeschränkt» ›
  «Anleitung hinzufügen»: name «Anmeldung», a username and password of an
  account on alvyo.tellbow.ch made for Google's review (e.g. `playreview`,
  with a route of its own), and «Keine weiteren Informationen erforderlich».
  Keep the account: every review uses it.
- **Altersfreigabe:** e-mail address, category «Alle anderen App-Typen».
  Violence, sexuality, language, controlled substances, gambling: all
  «Nein». «Können Nutzer miteinander interagieren oder Inhalte
  austauschen?» «Ja» (comments, shared routes, friends); «Teilt die App
  den aktuellen Standort mit anderen Nutzern?» «Ja» (live location);
  digital purchases «Nein». Expect PEGI 3 / USK 0 with the notes on
  interaction and location.
- **Zielgruppe und Inhalte:** «13–15», «16–17», «18 und älter» (no age
  under 13: the Families policy would apply); «Kann die App für Kinder
  ansprechend sein?» «Nein».
- **Nachrichten-Apps:** «Nein».
- **Werbe-ID:** «Nein» (the manifest removes `AD_ID`).
- **Behörden-Apps:** «Nein».
- **Finanzfunktionen:** «Meine App bietet keine Finanzfunktionen».
- **Gesundheit (Gesundheits-Apps):** «Aktivität und Fitness» (it records
  hikes with distance, time and ascent); no Health Connect data (the
  Android app does not read it yet, issue 8). When the watch import comes
  through Health Connect, this form and the data safety change.
- **Dienste im Vordergrund:** type «Standort», use case
  «Standortaktualisierungen im Hintergrund: Navigation», and also
  «Vom Nutzer initiierte Standortfreigabe» (live location).
  - Description: «Während einer Wanderung, die der Nutzer mit
    «Wanderung starten» oder «Aufzeichnen» selbst startet, zeichnet die
    App den GPS-Track auf, sagt Abbiegungen an und warnt, wenn der Nutzer
    den Weg verlässt, auch bei gesperrtem Bildschirm. Eine dauerhafte
    Benachrichtigung zeigt das an; mit «Beenden» hört es auf. Teilt der
    Nutzer seinen Live-Standort, geht die Position in dieser Zeit an die
    Personen, die er gewählt hat.»
  - Impact if deferred or interrupted: «Der Track hat Lücken, Ansagen und
    Warnungen fehlen: Der Nutzer kann sich im Gelände verlaufen, und
    Vertraute sehen seine Position nicht mehr.»
  - Video: a screen recording on the phone (Quick settings › Bildschirm
    aufnehmen), uploaded to YouTube as «Nicht gelistet»: open a route,
    «Wanderung starten», the notification, lock the screen, a spoken
    turn, unlock, «Beenden». 30–60 seconds.
- **Datensicherheit:** below.

### Datensicherheit

1. «Erhebt oder teilt deine App erforderliche Nutzerdatentypen?» «Ja».
   «Werden alle Daten bei der Übertragung verschlüsselt?» «Ja» (HTTPS
   only). Account: «Benutzername und Passwort» (on Android no Google or
   Apple login). Link to delete the account:
   `https://alvyo.tellbow.ch/account` («Konto löschen» after logging in;
   in the app Profil › Konto). «Können Nutzer das Löschen einiger oder
   aller Daten beantragen, ohne das Konto zu löschen?» «Ja» (routes,
   photos, comments one by one; or by e-mail, as the privacy text says).
2. Data types (step 3): the twelve below, nothing else. Then each with
   «Starten» (step 4): only «Erhoben», never «Geteilt» (Google Analytics
   processes for Alvyo as service provider, the bug reports' GitHub
   repository is Alvyo's own, live locations go where the user sends
   them).

| Data type | Sitzungsspezifisch verarbeitet? | Erforderlich? | Warum erhoben? |
|---|---|---|---|
| Personenbezogene Daten › Name | Nein | Die Datenerhebung ist erforderlich | Funktionen der App, Kontoverwaltung |
| Personenbezogene Daten › E-Mail-Adresse | Nein | Die Datenerhebung ist erforderlich | Funktionen der App, Kontoverwaltung |
| Personenbezogene Daten › Nutzer-IDs | Nein | Die Datenerhebung ist erforderlich | Funktionen der App, Kontoverwaltung |
| Standort › Ungefährer Standort | Nein | Nutzer können entscheiden | Analyse |
| Standort › Genauer Standort | Nein | Nutzer können entscheiden | Funktionen der App |
| Fotos und Videos › Fotos | Nein | Nutzer können entscheiden | Funktionen der App |
| Gesundheit und Fitness › Fitnessinformationen | Nein | Nutzer können entscheiden | Funktionen der App |
| App-Informationen und -Leistung › Diagnosedaten | Nein | Nutzer können entscheiden | Funktionen der App |
| App-Aktivitäten › App-Interaktionen | Nein | Nutzer können entscheiden | Analyse |
| App-Aktivitäten › Suchverlauf in der App | **Ja** | Nutzer können entscheiden | Funktionen der App |
| App-Aktivitäten › Sonstige nutzergenerierte Inhalte | Nein | Nutzer können entscheiden | Funktionen der App |
| Geräte- oder andere IDs | Nein | Nutzer können entscheiden | Analyse |

   Why: the name, e-mail address and username are needed for the account;
   the rest happens only when the user records, shares, uploads, searches
   or reports a bug, or agrees to Analytics. Only place searches are
   passed to swisstopo without being kept. No «Mitteilungen des
   Entwicklers» (account e-mails only, no newsletter), «Werbung oder
   Marketing», «Personalisierung» or «Betrugsprävention». Not chosen:
   Nachrichten (comments are public content), Kontakte (the phone's are
   not read), Absturzprotokolle (no crash reporting).

Check it against the privacy text (`about_privacy*` in `web/messages`)
whenever that changes.

## 4. Store settings

Nutzer gewinnen › Store-Präsenz › Store-Einstellungen:
- **Kategorie:** App, «Reisen & Lokales»; tags: Wandern, Outdoor,
  Navigation (as Play offers them).
- **Kontaktdaten:** the support e-mail (required, shown publicly), website
  `https://alvyo.tellbow.ch`.

Mit Play Geld verdienen › «Preisgestaltung» (or in the store settings): kostenlos (cannot become paid later).

## 5. Countries

Per track (Testen und veröffentlichen › Tests › the track › «Länder/Regionen»): Schweiz and Liechtenstein
at least; the neighbours (Deutschland, Österreich, Frankreich, Italien)
if people there should find it. The app works anywhere, its maps and
routes cover Switzerland.

## 6. The closed test (12 testers, 14 days)

Testen und veröffentlichen › Tests › Geschlossene Tests › «Alpha» (or «Track erstellen»):

1. **Tester:** an e-mail list (or a Google Group) with at least 12 Google
   accounts besides yours: the addresses they use on their Android phone.
   Feedback: the support e-mail.
2. **Release:** «Release aus anderem Track übernehmen» › the internal one
   (same bundle), the release notes as in step 1. «Länder/Regionen» as in
   step 5. «Zur Überprüfung senden»: Google reviews it (hours to days).
3. **Opt-in:** once approved, the track shows a link «Über das Web
   teilnehmen». Each tester opens it with that Google account, taps
   «Tester werden», then installs Alvyo from Play (a phone with the
   GitHub APK uninstalls it first: another signing key). Only who has opted in counts,
   and 12 must stay opted in for 14 days in a row: ask them to keep it
   installed and to open it now and then. Feedback they send helps the
   application.
4. New versions during the test: the `play-store` skill uploads to
   `internal` and promotes to `alpha` (`promote X.Y.Z --to alpha`).

## 7. Production access, then the first release

When Dashboard shows 12 testers for 14 days: «Zugriff auf Produktion
beantragen». Questions about the test (how testers were found, what they
said, what changed), the app (who it is for: hikers in Switzerland, what
it does differently: Swiss hiking times, the national map, SAC grades,
journeys with huts and public transport) and readiness. Google answers
within about 7 days; a refusal says what is missing and keeps the test
running.

Then Produktion › «Release aus anderem Track übernehmen» (or the
`play-store` skill: `promote X.Y.Z --from alpha --to production`),
countries as in step 5, «Zur Überprüfung senden». After that first
release Google publishes, the `play-store` skill does every later one
alone.

## Each later release

The `play-store` skill. Pictures and texts change in Play Console only
when the screens change: `render.mjs … play` again, and this file's texts.
