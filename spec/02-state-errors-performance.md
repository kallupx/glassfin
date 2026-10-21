# M02 – Tilanhallinta, virheenkäsittely, välimuisti ja suorituskyky (P0, poikkileikkaava)

**Riippuvuudet:** M01. Moduulin sisältö (AppState, välimuisti, virhemalli ja mittaus) toteutetaan ennen UI-moduuleja. Suorituskykyvaatimukset koskevat kaikkia moduuleja.

## 1. Tilanhallinta
- Käytetään **Observation-frameworkia (`@Observable`)** ja `@MainActor`-ViewModeleja. ViewModelit ovat `CoreState`-targetissa, joten iOS käyttää samoja.
- Kerrokset:
  - `AppState` (globaali, `@MainActor @Observable`) sisältää: `phase: .launching | .needsServer | .needsLogin(ServerInfo) | .signedIn(UserSession)`, `connectivity: .online | .offline | .serverUnreachable | .degraded`, `activeServer`.
  - Näkymäkohtaiset ViewModelit (`HomeViewModel`, `LibraryViewModel`, `SeriesViewModel`, `PlayerViewModel`, `SearchViewModel`) julkaisevat `LoadState<T>`-arvon:
    ```swift
    public enum LoadState<T: Sendable>: Sendable { case idle, loading(previous: T?), loaded(T), failed(AppError, previous: T?) }
    ```
    `previous` mahdollistaa vanhan sisällön näyttämisen päivityksen tai virheen aikana. Käyttäjä ei näe tyhjää ruutua, jos dataa on jo olemassa.
  - `UserDataStore` (actor) on katsottu-, sijainti- ja suosikkitilan **ainoa totuuden lähde** muistissa. Kaikki näkymät lukevat tilan siitä. Päivityslähteet: (1) oma toisto ja toiminnot optimistisesti, (2) WebSocketin `UserDataChanged`, (3) uudelleenhaku. Tämä korjaa kipupisteen "katsottu-tila ei päivity".
- Navigointi: `NavigationStack` ja tyypitetty `Route`-enum per välilehti. Tila (fokus ja scroll) palautetaan takaisin-navigoinnissa.
- Rinnakkaisuus: structured concurrency. Näkymän poistuessa sen taskit perutaan (`.task`-modifier). Haun vanhentuneet pyynnöt perutaan.

## 2. Välimuisti ja tallennus (tvOS-rajoitteet)
- tvOS:llä on pysyvää tallennustilaa vain noin **500 KB** (UserDefaults, Tutkijan raportti osa 3), ja Caches-hakemisto voidaan tyhjentää, kun appi ei ole käynnissä. Siksi:
  - **Keychain:** token ja DeviceId (ks. 03-security.md).
  - **UserDefaults** (< 50 KB budjetti): palvelinlista (URL, nimi, id, sertifikaatin pin-fingerprint), aktiivinen käyttäjä-id ja käyttäjän asetukset.
  - **Caches** (purgeable): kuvat (levy-LRU max 300 MB) ja viimeisin kotinäkymän JSON-snapshot nopeaa kylmäkäynnistystä varten (stale-while-revalidate).
  - **Muisti:** NSCache-kuvat (max 150 MB, tyhjennetään memory warningissa) ja API-vastaukset TTL:llä (koti 60 s, kirjastolistat 5 min, invalidointi WebSocket-tapahtumasta).
- Sovellus toimii oikein, vaikka Caches olisi tyhjennetty: silloin sisältö vain latautuu hitaammin.

## 3. Virheenkäsittely
Yhtenäinen virhemalli:
```swift
public enum AppError: Error, Sendable, Equatable {
  case offline                    // laitteella ei verkkoa (NWPathMonitor)
  case serverUnreachable          // DNS, yhteys evätty tai aikakatkaisu
  case tlsUntrusted(CertificateInfo) // itse allekirjoitettu tai vaihtunut sertifikaatti → 03-security
  case unauthorized               // 401: token vanhentunut tai mitätöity
  case forbidden                  // 403: ei oikeuksia (esim. admin-toiminto)
  case notFound
  case serverError(status: Int)
  case unsupportedServer(version: String) // alle minimiversion
  case playback(PlaybackError)
  case decoding                   // odottamaton JSON
  case cancelled                  // ei näytetä käyttäjälle
}
```

| Tilanne | Tunnistus | Käyttäytyminen | Hyväksymiskriteeri |
|---|---|---|---|
| Offline | `NWPathMonitor` ja URLError `.notConnectedToInternet` | Ylälaitaan hienovarainen banneri "Ei verkkoyhteyttä". Välimuistissa oleva sisältö pysyy selattavana, ja toisto estetään selkeällä viestillä. Kun yhteys palaa, sisältö päivittyy automaattisesti. | Verkon katkaisu ja palautus simulaattorissa: banneri ilmestyy ≤ 2 s ja poistuu ≤ 2 s yhteyden palattua, ja koti päivittyy ilman käyttäjän toimia. |
| Huono verkko | Pyynnön kesto > 3 s, toiston stallit | Skeleton- ja shimmer-tilat. API-pyyntöjen aikakatkaisu on 15 s, ja idempotentit GETit uusitaan 2 kertaa backoffilla (0,5 s, 1,5 s). Toistossa laskettu bitrate (transkoodaus) ja viesti, jos puskurointi kestää > 5 s. | Network Link Conditionerin "3G"-profiililla koti latautuu ilman kaatumista, ja jokaisella osiolla on skeleton- tai virhetila. |
| Palvelin alhaalla | Yhteysvirhe tai 502/503/504, WebSocketin `ServerShuttingDown`/`ServerRestarting` | Koko ruudun tila "Palvelimeen ei saada yhteyttä" sekä toiminnot "Yritä uudelleen" ja "Vaihda palvelinta". Taustalla ping 10 s välein, ja kun palvelin palaa, tila palautuu automaattisesti. | Palvelimen pysäytys kesken selailun → virhetila ≤ 15 s. Palvelimen käynnistys → palautuminen ≤ 15 s ilman uudelleenkirjautumista. |
| Token vanhentunut tai mitätöity | HTTP 401 mistä tahansa pyynnöstä | Kaikki käynnissä olevat pyynnöt keskeytetään. Token poistetaan Keychainista, ja käyttäjä ohjataan kirjautumiseen saman palvelimen kanssa viestillä "Istunto päättyi, kirjaudu uudelleen". **Uudelleenyrityssilmukkaa ei tehdä.** | Mock 401 → kirjautumisnäkymä yhden kerran (ei useita päällekkäisiä), ja token on poistettu Keychainista (yksikkötesti). |
| 403 | HTTP 403 | Inline-viesti "Ei oikeuksia tähän toimintoon". Istuntoa ei kirjata ulos. | Admin-toiminto ilman oikeuksia → viesti, istunto säilyy. |
| Vanha palvelin | `/System/Info/Public.Version` < minimi | Estävä näkymä, jossa kerrotaan vaadittu versio. | Mock-versio 10.9.11 → estonäkymä. |
| Toistovirhe | AVPlayerItem `.failed` tai `PlaybackInfoResponse.ErrorCode` | Ks. 08-playback.md: automaattinen fallback direct play → direct stream → transcode, ja vasta sen jälkeen virheviesti. | Ks. 08. |
| Odottamaton JSON | `DecodingError` | Kohde ohitetaan listasta ja virhe lokitetaan ilman tokenia. Koko näkymä ei kaadu. | Fixture, jossa yksi rikkinäinen item → muut näkyvät. |

- Virheviestit kirjoitetaan selkokielellä. Tekniset yksityiskohdat näytetään vain Asetukset → Diagnostiikka -näkymässä.
- Kaatumisraportointi: ❓ AVOIN, käytetäänkö MetricKitiä (oletus, ei kolmansia osapuolia) vai erillistä palvelua. Molemmissa tapauksissa tokenit ja URL:t suodatetaan (03-security.md).

## 4. Suorituskykyvaatimukset (mitattavat tavoitteet)
Mittauslaitteet (varmistettu 21.10.2026: tvOS 26 tukee kaikkia Apple TV HD- ja 4K-malleja; Liquid Glass on vain 4K 2. ja 3. sukupolvessa):
- Apple TV 4K (3. sukupolvi, A15)
- **Apple TV 4K (2. sukupolvi, A12)**: vanhin glass-laite, glass-budjetti M05 G-4
- **Apple TV HD (A8, 2015)**: vanhin tvOS 26 -laite, ei glassia (sarake "vanhin")
 Verkko: LAN gigabit ja Wi-Fi 5. Palvelin: Jellyfin 12.x, testikirjastossa 5 000 elokuvaa ja 500 sarjaa.

| # | Mittari | Tavoite (A15) | Tavoite (vanhin) | Mittaustapa |
|---|---|---|---|---|
| P1 | Kylmäkäynnistys → kotinäkymän ensimmäinen rivi näkyy (kirjautunut, LAN) | ≤ 1,5 s | ≤ 3,0 s | XCTApplicationLaunchMetric ja os_signpost |
| P2 | Kotinäkymän kaikki osiot ladattu (LAN, p95) | ≤ 1,0 s käynnistyksestä tai paluusta | ≤ 2,0 s | signpost |
| P3 | Fokuksen siirto ja vieritys (rivit, 2 000 kohteen grid) | 60 fps, hitch-ratio < 5 ms/s | < 10 ms/s | XCTOSSignpostMetric / Instruments Hitches |
| P4 | Juliste näkyy (välimuistista / LAN-verkosta) | ≤ 100 ms / ≤ 500 ms | ≤ 200 / ≤ 800 ms | signpost |
| P5 | Toiston aloitus (Play → ensimmäinen ruutu), direct play LAN | ≤ 1,5 s | ≤ 2,5 s | signpost `playback.firstFrame` |
| P6 | Toiston aloitus, transkoodaus | ≤ 4 s | ≤ 6 s | sama |
| P7 | Kelaus (scrub-vahvistus → toisto jatkuu), direct play LAN | ≤ 1,0 s | ≤ 2,0 s | sama |
| P8 | Trickplay-esikatselukuva näkyy scrubattaessa | ≤ 150 ms (tile välimuistissa) | ≤ 300 ms | signpost |
| P9 | Raidanvaihto (ääni/tekstitys) kesken toiston, direct play / HLS | ≤ 1,0 s, ei toiston uudelleenkäynnistystä | ≤ 2,0 s | manuaalinen ja UI-testi |
| P10 | Haku: ensimmäiset tulokset näppäilyn jälkeen (300 ms debouncen jälkeen, LAN) | ≤ 500 ms | ≤ 1 000 ms | signpost |
| P11 | Muistinkäyttö selailussa | ≤ 250 MB | ≤ 200 MB | XCTMemoryMetric |
| P12 | Muistinkäyttö toistossa (AVPlayer) / remux-polku | ≤ 400 MB / ≤ 500 MB | ≤ 300 / ≤ 400 MB | XCTMemoryMetric |
| P13 | Muistivuoto: 10 toisto–pysäytys-sykliä | kasvu < 20 MB | sama | XCTMemoryMetric |
| P14 | Katsottu-tilan päivitys toiston jälkeen kotinäkymässä | ≤ 2 s | ≤ 2 s | UI-testi |
| P15 | Muutos toiselta clientiltä (WebSocket) näkyy | ≤ 5 s | ≤ 5 s | integraatiotesti |

- P1, P3, P5, P11 ja P13 ajetaan `XCTMetric`-testeinä CI:ssä simulaattorilla regressioseurantaa varten. Simulaattorin luvut eivät vastaa laitetta, joten absoluuttiset tavoitteet vahvistetaan laitteella ennen jokaista julkaisua (Koodari tai käyttäjä, koska Testaajalla ei ole laitetta).
- Kuvat pyydetään aina näytettävän koon mukaan (`maxWidth` = näytettävä pikselileveys × näytön skaala). Täysikokoisia kuvia ei ladata.
- Listat ovat laiskoja (`LazyHGrid`/`LazyVGrid`) ja sivutettuja (`limit=50`, seuraava sivu, kun jäljellä on 10 kohdetta).

## Hyväksymiskriteerit (moduuli)
- [ ] `AppState`, `LoadState`, `AppError`, `UserDataStore` ja välimuistikerros on toteutettu ja yksikkötestattu.
- [ ] Jokaiselle taulukon virhetilanteelle on vähintään yksi automaattinen testi (mock).
- [ ] Signpost-instrumentointi P1–P15:lle on valmiina, ja `XCTMetric`-testit ajetaan CI:ssä.
- [ ] UserDefaultsin koko testataan (< 50 KB 10 palvelimella ja 10 käyttäjällä).
