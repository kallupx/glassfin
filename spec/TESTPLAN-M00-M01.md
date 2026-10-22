# Testisuunnitelma – M00 (infra & CI) ja M01 (GlassfinCore)

**Laatija:** Testaaja · 21.10.2026 · Pohja: spec/SPEC.md, 00-infra-ci.md, 01-core.md
**Ympäristö:** Testaajalla Linux (ei Xcodea, ei Swiftiä, ei Dockeria tällä hetkellä). Kaikki ajo CI:ssä; Testaaja lukee artefaktit ja katselmoi testit/koodin repossa `kallupx/glassfin`.

## Avoimet kysymykset ennen testausta
| # | Kysymys | Kenelle | Miksi |
|---|---|---|---|
| Q1 | Paketin nimi: `GlassfinCore` (SPEC §1, M01) vai `GlassfinCore` (M00)? Targetit ja CI-grepit viittaavat nimeen. | Spesifikaatio | Yksi nimi kaikkialla, muuten grep-tarkistukset ja skeemat menevät ristiin. |
| Q2 | `.xcresult` ei aukea Linuxilla (`xcresulttool` on vain macOS:llä). CI:n pitää lisäksi viedä: JUnit XML, kuvakaappaukset PNG-tiedostoina, coverage tekstinä/JSONina (`xccov view --report --json`) ja failanneiden testien lokit. | Koodari | Muuten M00:n kriteeri "Testaaja saa artefaktit auki Linuxilla" ei täyty. |
| Q3 | Mitä negatiivinen ticks-arvo tuottaa: virhe, nolla vai negatiivinen Duration? | Spesifikaatio | M01-kriteeri vaatii testin, mutta odotettu tulos puuttuu. |
| Q4 | WebSocket-backoff: lisätäänkö jitter, ja nollautuuko viive onnistuneen yhteyden jälkeen? Testit vaativat injektoidun `Clock`-abstraktion. | Spesifikaatio / Koodari | Muuten testi on hidas tai epädeterministinen. |
| Q5 | Integraatiotestipalvelin (SPEC §6.10). Suosittelen vaihtoehtoa (b): Docker-kontit 10.10.7 / 10.11.x / 12.x Linux-runnerilla. Se on halvin, ja ajot ovat toistettavia. | Käyttäjä | Ilman tätä M01:n integraatiokriteeri ei ole testattavissa. |

## M00 – testitapaukset
| ID | Testi | Askeleet | Odotettu | Todennus |
|---|---|---|---|---|
| T00-01 | Puhdas build | PR, jossa on tyhjät tvOS- ja iOS-appit ja core | `ci.yml` vihreä, kaikki jobit ajettu | Actions-ajon tila |
| T00-02 | Path-filtteri | PR, joka muuttaa vain `spec/**`:ia tai `*.md`:tä | Vain `lint` ajetaan, macOS-jobit ohitetaan | Jobilista |
| T00-03 | Path-filtteri, positiivinen | PR, joka muuttaa `Packages/**`:ia | `test-tvos` ja `test-ios` ajetaan | Jobilista |
| T00-04 | iOS-ehto | PR, joka muuttaa vain `Apps/tvOS/**`:ia | `test-ios` ohitetaan PR:ssä, mutta ajetaan main-pushissa | Jobilista |
| T00-05 | Concurrency | Kaksi pushia samaan PR:ään peräkkäin | Ensimmäinen ajo perutaan (cancelled) | Ajohistoria |
| T00-06 | Cache | Sama PR ajetaan kahdesti | Toisessa ajossa cache hit (SPM ja DerivedData), kesto lyhenee | Lokit ja kesto |
| T00-07 | `needs: lint` | PR, jossa tahallinen SwiftLint-virhe | `lint` failaa, macOS-jobit eivät käynnisty (0 macOS-minuuttia) | Jobilista |
| T00-08 | Lint estää mergen | Sama PR | Branch protection estää mergen | PR-näkymä |
| T00-09 | CI-grepit | Testihaaroissa erikseen: `NSAllowsArbitraryLoads`, `X-Emby-Token`, `api_key=`, `print(` | Jokainen failaa `lint`-jobin selkeällä viestillä | Lokit |
| T00-10 | license-check, negatiivinen | Testihaara + `kingslay/FFmpegKit` | `license-check` failaa | Lokit |
| T00-11 | license-check, positiivinen | Puhdas main | Menee läpi | Lokit |
| T00-12 | Unit molemmilla alustoilla | main-push | JUnit-raportit sekä tvOS- että iOS-simulaattorista | Artefaktit |
| T00-13 | Savutesti + kuvakaappaus | main-push | XCUITest käynnistää appin, ensimmäinen näkymä näkyy, PNG artefaktina | Testaaja avaa PNG:n |
| T00-14 | Artefaktit Linuxilla | Lataa ajon artefaktit | JUnit, PNG:t ja coverage aukeavat ilman macOS:ää (ks. Q2) | Testaaja |
| T00-15 | Aikakatkaisut | Tarkista workflow | macOS 25 min, Linux 10 min, `permissions: contents: read` | Katselmointi |
| T00-16 | Minuuttiseuranta | 10 ensimmäistä ajoa | macOS-minuutit kirjattu, ennuste ≤ 200 min/kk tai eskalointiehdotus | Koodarin raportti |
| T00-17 | Lisenssitiedostot | Repon juuri | `LICENSE` ja `THIRD_PARTY_LICENSES` olemassa, riippuvuudet vastaavat `Package.resolved`:ia | Katselmointi |
| T00-18 | Secretit | `release.yml` (kun tehty) | Ei `pull_request`-triggeriä, avain poistetaan `always()`-stepissä, ei kaikua | Katselmointi + Turvallisuus |

## M01 – testitapaukset
| ID | Testi | Odotettu |
|---|---|---|
| T01-01 | Import-raja | Core ei importtaa SwiftUI:ta tai UIKitiä ilman `#if os(...)` -adapteria (CI-grep failaa testihaarassa) |
| T01-02 | Auth-header ennen kirjautumista | Täsmälleen `MediaBrowser Client="Glassfin", Device="…", DeviceId="…", Version="…"`, ei Token-kenttää |
| T01-03 | Auth-header kirjautuneena | Sama + `Token="…"`; kenttäjärjestys ja lainausmerkit täsmäävät |
| T01-04 | Erikoismerkit laitenimessä | Laitenimessä `"`, `,`, ääkköset ja emoji → header pysyy validina (escape tai sanitointi) |
| T01-05 | Ei header + query yhtä aikaa | Media- ja kuva-URL:issa vain `ApiKey`, ei Authorization-headeria; API-pyynnöissä ei `ApiKey`:tä |
| T01-06 | DeviceId pysyvä | Generoidaan kerran; sama arvo uudelleenkäynnistyksen jälkeen (mock-SecureStore); `-uitest-reset` vaihtaa sen |
| T01-07 | Endpoint-matriisi | Jokaiselle P0-endpointille 6 tapausta: 200, 401, 404, 500, aikakatkaisu ja virheellinen JSON → oikea `APIError`-variantti, ei kaatumista |
| T01-08 | 401-käsittely | 401 tuottaa `unauthorized`-virheen; verkkovirhe ei koskaan tuota sitä (K10) |
| T01-09 | Quick Connect -reitti | Initiate käyttää POSTia (12.x); 10.10:llä toimii myös |
| T01-10 | Ticks ↔ Duration | 0, 1 tick, 10 000 000 (1 s), > 24 h, `Int64.max`-raja, negatiivinen (ks. Q3), edestakainen muunnos häviöttä |
| T01-11 | Mapperit | Jokainen DTO → domain -mapperi fixturella 12.x ja 10.10; puuttuvat valinnaiset kentät (nil overview, ei kuvia, ei trickplayta) eivät kaada |
| T01-12 | Tuntematon enum | Tuntematon `Type`-merkkijono → `.other(String)`; tuntematon `MediaSegmentType` → `.unknown` |
| T01-13 | Token ei UserSessionissa | `UserSession` ei sisällä tokenia; `description` tai `dump` ei vuoda sitä (myös Turvallisuus S-vaatimukset) |
| T01-14 | WebSocket backoff | Katkot → viiveet 1, 2, 4, 8, 16, 30, 30 s (injektoitu kello); onnistuminen nollaa viiveen |
| T01-15 | WebSocket-tapahtumat | Mock-socket lähettää `UserDataChanged` ja `LibraryChanged` → tapahtumat tulevat streamiin; `KeepAlive` ei tuota UI-tapahtumaa; tuntematon tyyppi ohitetaan |
| T01-16 | ServerShuttingDown / Restarting | Ei kirjaa ulos; siirtyy reconnect-tilaan |
| T01-17 | Peruutus | Peruttu `Task` → pyyntö peruuntuu, ei vuotoa, ei virhetoastia (tärkeä M09:n K6:lle) |
| T01-18 | Concurrency | Swift 6 strict concurrency `complete` ilman varoituksia (build-loki) |
| T01-19 | Coverage | Core ≥ 80 % rivikattavuus |
| T01-20 | Integraatio | Kirjautuminen, UserViews, Resume ja PlaybackInfo 12.x:llä; sama 10.10.7:llä ja 10.11.x:llä (ks. Q5) |

## Hyväksyntä
Moduuli on hyväksyttävissä, kun kaikki speksin hyväksymiskriteerit ja yllä olevat P0-testit ovat vihreinä CI:ssä, avoimet kysymykset Q1–Q5 on ratkaistu tai kirjattu tietoisesti auki, eikä avoimia kriittisiä bugeja ole.
