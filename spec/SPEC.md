# Glassfin – Jellyfin-client tvOS:lle (ja myöhemmin iOS:lle) – Spesifikaatio v1.2

**Laatija:** Spesifikaatio · **Päivämäärä:** 21.10.2026 · **Versio:** v1.2 · **Tila:** LUONNOS. Turvallisuus on hyväksynyt 03-security.md:n. Odottaa käyttäjän vahvistuksia (§6). Muutoshistoria on alla.
**Lähteet:** Tutkijan tutkimusraportti v1 osat 1–5, käyttäjän tavoitteet ryhmässä, Turvallisuuden ja Testaajan pyynnöt, tiimin linjaukset (iOS, admin, turvallisuus) sekä Spesifikaation omat verkkotarkistukset 21.10.2026 (Jellyfinin OpenAPI 12.2.0, jellyfin-sdk-swift, Applen ja GitHubin julkaisutiedot, lisenssit). Ladattu OpenAPI-kopio: `/workspace/jellyfin-tvos/research/openapi.json`.

> Merkinnät: **P0** = MVP, **P1** = seuraava julkaisu (pariteetti ja iOS), **P2** = myöhemmin. **OLETUS – vaatii käyttäjän vahvistuksen** = Spesifikaation valitsema oletus. ⚠️ = varmistamaton tieto tai riski. **[SOVITTU]** = sovittu Turvallisuuden kanssa.

## Muutoshistoria
- **v1.2 (21.10.2026, Testaajan kysymykset ja Turvallisuuden tarkennukset)**
  - **Paketin nimi on `GlassfinCore` kaikkialla** (vanha työnimi poistettu kaikista tiedostoista, grep: 0 osumaa).
  - **M00, CI-artefaktit:** JUnit XML, PNG-kuvakaappaukset, `xccov`-coverage-JSON ja epäonnistuneiden testien lokit `.xcresult`in lisäksi, jotta ne voi lukea Linuxilla. S5-redaktointi ja skannaus koskevat myös artefakteja (S5.5).
  - **M00, integraatiotestipalvelin (EHDOTUS, §6.10):** `jellyfin/jellyfin`-kontit `10.10.7`, `10.11.11` ja `12.2` Linux-servicenä, generoitu ja seedattu testikirjasto, ei macOS-minuutteja. Tunnukset vain GitHub Secretsistä. ⚠️ SDK:n Linux-build on varmistamatta, ja sille on varasuunnitelma.
  - **M01, tick-rajatapaukset:** negatiivinen sijainti → 0 ja yksi varoitus. `RunTimeTicks` ≤ 0 → kesto tuntematon, eikä edistymispalkkia näytetä. Palvelimelle ei koskaan lähetetä negatiivista arvoa.
  - **M01, WebSocket-reconnect:** full jitter `random(0, min(30 s, 1 s · 2^n))`, ja laskuri nollautuu vasta 10 s:n vakaan yhteyden jälkeen. Aikalähde on injektoitu `Clock`, ja foregroundissa yhdistetään heti.
  - **S1.6/M01, header-enkoodaus:**
    - Arvot URL-enkoodataan ja lainausmerkitään, ja CR/LF tai muu ohjausmerkki hylätään.
    - Varmistettu palvelimen `GetParts` (`WebUtility.UrlDecode`) ja jellyfin-sdk-typescript (`encodeURIComponent`).
    - ⚠️ jellyfin-sdk-swift 3.3.0 ei enkoodaa, joten header rakennetaan itse.
  - **S2.2/M01/M02:** vain HTTP 401 kirjaa ulos. Verkko-, TLS-, aikakatkaisu- ja 5xx-virheet eivät koskaan.
  - **S4.6 [SOVITTU]:**
    - `ApiKey`-URL:n cross-host- ja HTTPS→HTTP-redirect hylätään (ei pelkkää parametrin poistoa). Same-host HTTPS toimii.
    - Sääntö kattaa vain appin omat pyynnöt, joten AVPlayerille annetaan aina resolvoitu lopullinen URL.
    - `ApiKey` HLS-transkoodaussegmenteissä on hyväksytty riski.
  - **ADR M08-2:** resource loader sieppaa HLS:ssä käytännössä vain playlistit ja avaimet (⚠️ foorumiraportit). Prototyyppi testaa erikseen direct playn, palvelimen HLS:n (segmenteille todennäköisesti `ApiKey`) ja oman loopback-remuxin (ei tokenia).
- **v1.1 (21.10.2026)**
  - **Turvallisuus hyväksyi 03-security.md:n.** Sovituiksi merkittiin:
    - S1.1 `AfterFirstUnlockThisDeviceOnly` (tvOS:ssä ei ole lukitusnäyttöä, ja tiukempi luokka rikkoisi Top Shelfin)
    - S3.3 Quick Connect -pollaus 5 s ja aikakatkaisu 5 min
    - S4.3 julkiset osoitteet vaativat HTTPS:n
    - S4.4 CA-sertifikaatteja ei pinnata
  - **S1.4:** jaettu Keychain access group vain app- ja Top Shelf -targeteille (CI-tarkistus).
  - **S1.5/S5.1-ristiriita ratkaistu:** media-token välitetään ensisijaisesti headerina (`AVAssetResourceLoaderDelegate` tai dokumentoimaton `AVURLAssetHTTPHeaderFieldsKey` ⚠️). Fallback on `ApiKey=` vain media-URL:eissa, ja silloin S5-redaktointi on pakollinen. Uusi ADR M08-2: yksi prototyyppi ratkaisee sekä tämän että R3:n (itse allekirjoitettujen palvelinten media).
  - **Jellyfin 12.0 poisti `api_key`:n.** Ainoa queryparametri on `ApiKey` (Jellyfinin mukaan viimeinen keino, koska se vuotaa proxy-lokeihin). Sanamuodot korjattu M01:ssä, M03:ssa ja M08:ssa.
  - **Uudet vaatimukset:**
    - S4.6: Authorization-headeria ei välitetä cross-host-redirectissä, ja HTTPS → HTTP -redirect hylätään. Lisätty M01:n hyväksymiskriteereihin.
    - S4.7: UDP 7359 -discovery-vastaukset ovat epäluotettavia, osoite näytetään aina ja käyttäjä valitsee itse. Lisätty M04:ään.
  - **Quick Connect:** aloitus on **`POST /QuickConnect/Initiate`** (12.0 poisti GET:n). Lisätty M04:n hyväksymiskriteereihin.
  - **ADR M08-1 päätetty (Tutkija varmisti):** `AVPlayerViewController` näyttää scrub-thumbnailit vain `#EXT-X-I-FRAME-STREAM-INF`-variantilla, jota Jellyfin ei tuota (trickplay on JPEG-spritejä). Siksi rakennetaan oma scrubbaus-overlay Jellyfinin spriteillä, eikä palvelinpluginia tarvita. Kolmannen osapuolen native-trickplay-plugin (vain 10.11) on valinnainen vaihtoehto. M05:een lisättiin trickplay-glass-overlay. R1 suljettu päätöksellä, jäljellä toteutusriski (⚠️ natiivin scrub-tilan seuranta vai oma scrub-bar).
- **v1.0+ (21.10.2026, samana päivänä):**
  - avoin lähdekoodi ja MPL-2.0-ehdotus (B1 → R9, LGPL-ehdot L1–L5)
  - nimi Glassfin (nimikonflikti R10)
  - Liquid Glass -design system (M05)
  - Apple Developer -tili ei ole M00-blokkeri
  - repo `kallupx/glassfin` ja CI-kustannusrajat (R13)
- **v1.0 (21.10.2026):** ensimmäinen versio.

---

## 1. Tavoite ja periaatteet
Rakennetaan **Glassfin**: paras, tehokkain, helppokäyttöisin ja siistein Jellyfin-client Apple TV:lle. Myöhemmin tulee iOS-versio **samalla nimellä (Glassfin)** ja samoilla ominaisuuksilla.
1. **Luotettavuus ennen ominaisuuksia.** Tutkijan johtopäätös: suurin kilpailuetu syntyy toiston luotettavuudesta ja perusnavigoinnin hiomisesta. Jokainen tunnettu kipupiste on muutettu vaatimukseksi ja hyväksymiskriteeriksi (§4).
2. **Liquid Glass -ulkoasu (käyttäjän päätös):** Applen tvOS/iOS 26 -suunnittelukieli. Glass on navigaatiossa ja kontrolleissa, ja sisältö (julisteet, taustat, video) pysyy läpinäkymättömänä. Järjestelmäkomponentit ensin (`TabView`, `.buttonStyle(.glass)`, `GlassEffectContainer`, natiivi transport bar, `.card`). Ks. 05-design-system.md.
3. **Yksi jaettu ydin:** Swift package `GlassfinCore` sisältää API:n, mallit, ViewModelit ja tilan, toistologiikan sekä authin ja verkon. Vain UI on alustakohtainen. iOS-target kääntyy päivästä 1.
4. **Testattavuus:** protokollapohjaiset palvelut, mockattava API-asiakas ja macOS-CI (Testaajalla on vain Linux).
5. **Turvallisuus oletuksena:** token Keychainissa, ei `NSAllowsArbitraryLoads`-asetusta, eikä tokeneita lokeissa.

## 2. Alustat ja versiot
| Asia | Päätös | Perustelu |
|---|---|---|
| tvOS-minimi | **tvOS 26** – OLETUS, vaatii käyttäjän vahvistuksen | Varmistettu: nykyinen julkinen versio on tvOS 27.0 (14.9.2026), ja 27.2 RC julkaistiin 19.10.2026. Minimiksi ehdotetaan nykyistä miinus yksi. Tutkijan vaihtoehdot "17 vai 18" ovat vanhentuneita (Apple siirtyi vuosinumerointiin, 18 → 26). |
| iOS-minimi | **iOS 26** – OLETUS | Sama ydin ja samat API:t |
| Build-työkalut | Xcode 27, Swift 6 | GitHub `xcode-27`-runner yleisesti saatavilla 15.10.2026 alkaen |
| Jellyfin-palvelimen minimi | **10.10** (käytännössä 10.10.7) – OLETUS, vaatii käyttäjän vahvistuksen | Media segments ja trickplay vaativat 10.10+, ja Android TV vaatii saman. ⚠️ **Uusi havainto:** nykyinen palvelin on **Jellyfin 12.2** (5.10.2026; 12.0 julkaistiin 8.9.2026), ja Tutkijan raportti ei maininnut 12.x-sarjaa. 12.0 poisti legacy-authin ja `GET /QuickConnect/Initiate`-reitin. Testataan 10.10.7-, 10.11.x- ja 12.x-versioilla. Vaihtoehto: minimiksi 10.11, jolloin testimatriisi pienenee. |
| SDK | jellyfin-sdk-swift ≥ 3.3.0 (MPL-2.0, generoitu 12.1:lle) | ⚠️ Yhteensopivuus 10.10:n kanssa on varmistamatta, ja se varmistetaan integraatiotesteillä (M00/M01). |

## 3. Moduulit toteutusjärjestyksessä (Koodarille)
| # | Tiedosto | Moduuli | Prio | Riippuvuudet | Huom. |
|---|---|---|---|---|---|
| M00 | [00-infra-ci.md](00-infra-ci.md) | Repo, projekti, macOS-CI (tvOS ja iOS), lint ja artefaktit Testaajalle | **P0** | – | Ensin. Repo `kallupx/glassfin` (yksityinen). Ei blokkereita. |
| M01 | [01-core.md](01-core.md) | GlassfinCore: verkko, auth-header, API-kerros (SDK), domain-mallit, endpointit ja WebSocket | **P0** | M00 | Jaettu tvOS ja iOS |
| M02 | [02-state-errors-performance.md](02-state-errors-performance.md) | Tilanhallinta (`@Observable`), virhemalli, välimuisti (tvOS 500 KB -raja), suorituskykytavoitteet P1–P15 | **P0** | M01 | Poikkileikkaava |
| M03 | [03-security.md](03-security.md) | Turvallisuusvaatimukset S1–S9 | **P0** | M01 | 🔒 Turvallisuus katselmoi |
| M04 | [04-auth.md](04-auth.md) | Palvelimen lisäys, Quick Connect, salasana, uloskirjautuminen ja sertifikaattivirta | **P0** | M01–M03, M05 | |
| M05 | [05-design-system.md](05-design-system.md) | Liquid Glass -design system, komponentit, fokussäännöt, saavutettavuus, glass-suorituskykybudjetti ja näyttöhierarkia | **P0** | M00 | Rinnakkain M01–M04:n kanssa. ADR M05-1 (⚠️-kohdat) ennen M06:ta |
| M06 | [06-home.md](06-home.md) | Koti: jatka katsomista, seuraavat ja viimeksi lisätyt | **P0** | M01–M05 | |
| M07 | [07-library-detail.md](07-library-detail.md) | Kirjastot, detail sekä sarja-, kausi- ja jaksonäkymä | **P0** | M01–M05 | |
| M08 | [08-playback.md](08-playback.md) | **M08a** AVPlayer + palvelimen DirectStream/Transcode, DeviceProfile, raportointi, raidat, segments, trickplay ja next-up | **P0** | M01–M07 | ADR M08-2 (media-token ja itse allekirjoitettu media) prototyyppinä ensin. ADR M08-1 on päätetty (oma sprite-overlay). |
| M08b | [08-playback.md](08-playback.md#m08b--laitteella-tehtävä-remux-p1) | Laitteella tehtävä FFmpeg-remux | P1 | M08a, R2-prototyyppi | LGPL-ehdot L1–L5 (§7) |
| M09 | [09-search.md](09-search.md) | Haku | **P0** | M01–M07 | |
| M10 | [10-settings.md](10-settings.md) | Asetukset (P0-minimi), diagnostiikka ja appin sisäinen lisenssinäkymä | **P0**/P1 | M02, M04, M08 | |
| M11 | [11-ios-ui.md](11-ios-ui.md) | iOS-UI MVP-moduuleille | P1 | tvOS M04, M06 ja M07 vakaat | +30–50 %, oletus |
| M12 | [12-music-audiobooks.md](12-music-audiobooks.md) | Musiikki, lyrics ja äänikirjat | P1 | M08 | |
| M13 | [13-livetv.md](13-livetv.md) | Live TV ja tallenteet | P1 | M08 | |
| M14 | [14-alt-player.md](14-alt-player.md) | VLCKit (tai MPV) -varamoottori: PGS, ASS ja DTS/TrueHD direct play | P1 | M08 | Infuse-pariteetti, LGPL-ehdot L1–L5 (§7) |
| M15 | [15-extras.md](15-extras.md) | Useat palvelimet ja käyttäjät, Top Shelf, kokoelmat, PiP ja trailerit | P1/P2 | M04, M06, M07 | |
| M16 | [16-syncplay.md](16-syncplay.md) | SyncPlay | P2 | M08 | |
| M17 | [17-admin.md](17-admin.md) | Admin: tvOS-kevytversio ja iOS-täysversio | P2 | M01–M04, M10 | |
| M18 | [18-ios-downloads.md](18-ios-downloads.md) | iOS-lataukset ja offline | P2 | M11, M08 | Vain iOS |

**MVP (P0) valmis, kun:** M00–M10 ovat hyväksytty (jokaisen tiedoston hyväksymiskriteerit kuitattu, Testaajan raportti "hyväksyttävissä" ja Turvallisuuden katselmointi tehty) ja suorituskykytavoitteet P1–P15 on mitattu laitteella.

## 4. Kipupisteet → vaatimus → hyväksymiskriteeri
Lähde: Tutkijan raportti, osa 2 (Reddit, Jellyfin-foorumi, Swiftfin #1743) ja osa 3.
| # | Kipupiste | Vaatimus | Hyväksymiskriteeri (tiivistetty) | Moduuli / prio |
|---|---|---|---|---|
| K1 | Scrubbaus tai kelaus puuttuu tai on rikki | PB1 natiivi scrubbaus kaikissa PlayMethodeissa, PB2 trickplay | Kelaus direct playssä ≤ 1,0 s ja transkoodauksessa ≤ 3 s. 20 peräkkäistä kelausta ilman jumia. Thumbnail ≤ 150 ms. | M08 P0 |
| K2 | Katsottu-tila ei päivity, kirjasto ei päivity ilman uudelleenkäynnistystä | `UserDataStore` yhtenä totuuden lähteenä, raportointi Start/Progress/Stopped, WebSocket `UserDataChanged`/`LibraryChanged` ja päivitys etualalle palattaessa | Koti päivittyy ≤ 2 s toiston jälkeen (P14), toisen clientin muutos ≤ 5 s (P15) | M02, M06, M08 P0 |
| K3 | Ääni- ja tekstitysvalinta vaikea löytää, vaihto ei onnistu kesken toiston | PB3 yhden painalluksen valinta Info-paneelissa, lennossa vaihto. PB4 oletusvalinta käyttäjän kieliasetuksista. | Upotettu raita vaihtuu ≤ 1 s ilman katkosta, palvelinvaihto ≤ 4 s ja kohta säilyy ± 2 s | M08 P0 |
| K4 | Seuraava jakso ei käynnisty automaattisesti | PB7 lähtölaskenta Outro-segmentistä tai 30 s ennen loppua | 10 s lähtölaskenta → seuraava jakso samoilla raitakielillä. Peru toimii. | M08 P0 |
| K5 | Kausi- ja jaksonäkymän fokus hyppii, fokus jää jumiin kuvaukseen | Fokussäännöt 1–6 (M07), kuvaus ei fokusoitava (M05 HeroHeader), rivien fokusmuisti | Jokaisesta säännöstä oma XCUITest. Paluu palauttaa saman kohteen. | M05, M07 P0 |
| K6 | Haku bugaava (merkkejä katoaa, tulokset päällekkäin) | SR1 vanhojen hakujen peruutus ja termitarkistus, SR2 tila ViewModelissa | Käänteisessä järjestyksessä tulevat vastaukset → vain viimeisin näkyy. 20 merkkiä nopeasti → kaikki tallessa. | M09 P0 |
| K7a | Intro skipper ei toimi | PB6 media segments natiivilla `contextualActions`-painikkeella: Kysy / Ohita / Ei mitään | Painike näkyy ja häviää segmentin rajoilla, ja auto-ohitus toimii | M08 P0 |
| K7b | Live TV: ei ääntä tai kaatuu | M13 live-kohtainen TranscodingProfile ja äänen pakotettu yhteensopivuus | Ääni kuuluu MP2-, AC-3- ja AAC-testikanavilla, 2 h ilman kaatumista | M13 P1 |
| K8 | Tarpeeton transkoodaus (väärä device profile) | Ajonaikainen DeviceProfile laitteen ja näytön kyvyistä sekä diagnostiikka-overlay (`TranscodeReasons`) | Testimatriisin tiedostot 1–3 DirectPlay, 4–6 DirectStream (video copy) | M08 P0 |
| K9 | Musiikki- ja äänikirjakirjastot puuttuvat | M12 | Albumi, lyrics ja äänikirjan jatkokohta | M12 P1 |
| K10 | Uloskirjautuminen istuntojen välillä | Token Keychainissa (S1.1). Verkkovirhe ei koskaan kirjaa ulos, vain 401 kirjaa. | Pakkosulku ja palvelin alhaalla käynnistyksessä → koti välimuistista ilman kirjautumista | M04 P0 |
| K11 | tvOS 26: tekstitykset näkyvät neliöinä (CJK) | PB5 oma `SubtitleOverlay` järjestelmäfontilla ja CJK-fallbackilla (tai natiivi, jos todistetusti toimii) | ja/zh/ko-testitekstitykset oikein tvOS 26:lla ja 27:llä (kuvakaappaus) | M08 P0 |
| K12 | (osa 3) tvOS:llä vain noin 500 KB pysyvää tilaa, Caches voidaan tyhjentää | Tallennusbudjetti: Keychain, UserDefaults < 50 KB, Caches purgeable | Appi toimii tyhjennetyn välimuistin jälkeen, UserDefaults < 50 KB testattu | M02 P0 |
| K13 | (osa 3) Apple TV ei bitstreamaa TrueHD:ta tai DTS:ää | PB11 palvelin transkoodaa äänen (video copy). M14 dekoodaa laitteella PCM:ksi. | TrueHD 7.1 -MKV toistuu DirectStreamina P6:n rajoissa | M08 P0, M14 P1 |

## 5. Ominaisuuspariteetti (tiivistelmä)
| Ominaisuus | Android TV / web | Infuse | Me |
|---|---|---|---|
| Quick Connect, kirjautuminen | ✔ | ✘ | **P0** |
| Koti, kirjastot, sarjat, haku | ✔ | ✔ | **P0** |
| Media segments (skip/ask) | ✔ (10.10+) | osittain | **P0** |
| Trickplay | ✔ | oma | **P0** (ADR M08-1) |
| DirectPlay MP4/HEVC/DV/Atmos | ✔ | ✔ | **P0** |
| MKV ilman palvelinkuormaa | – | ✔ | P0 palvelinremux (DirectStream), P1 laiteremux (M08b) |
| PGS/ASS natiivisti, DTS/TrueHD-dekoodaus | osittain | ✔ | P0 burn-in/transkoodaus, **P1 M14** |
| Musiikki, lyrics | ✔ | ✔ | P1 |
| Live TV, tallenteet | ✔ | rajoitettu | P1 |
| Top Shelf, monikäyttäjä | – | ✔ | P1 |
| SyncPlay | web ✔, Android TV ✘ | ✘ | P2 |
| Admin | web ✔ | ✘ | P2 |
| Lataukset | mobiili ✔ | ✔ (iOS) | P2 (vain iOS) |
| Kuvat, kirjat | web ✔ | osittain | P2 |
| SMB/Plex/muut lähteet | – | ✔ | ✘ ei skoopissa (Tutkijan oletus) |

## 6. Päätökset, jotka vaativat käyttäjän vahvistuksen
1. **Palvelinminimi 10.10 (10.10.7)**, testaus myös 10.11.x:llä ja 12.x:llä. Vaihtoehto: 10.11+.
2. **tvOS 26+ / iOS 26+**, build Xcode 27:llä.
3. **MVP:n toistopolku = AVPlayer + palvelimen DirectStream/Transcode.** Laiteremux (M08b) ja VLCKit-varamoottori (M14) ovat P1. Lisenssi ei enää estä niitä (§7 B1 → R9), mutta M08b odottaa yhä suorituskykyprototyyppiä R2. Tämä tarkoittaa, että MVP ei vielä ole Infuse-tasoa PGS-, ASS-, DTS- ja TrueHD-tiedostoilla.
4. **Admin-työkalut P2:ssa** (tiimin linjaus): tvOS kevyt, iOS täysi.
5. **iOS-UI on P1**, ja se alkaa, kun tvOS:n auth, koti ja kirjasto ovat vakaat. +30–50 % on Tutkijan mittaamaton arvio.
6. **"Infuse-taso" = toistolaatu ja sujuvuus**, ei monilähdetukea (SMB, Plex).
7. Kotinäkymässä "Jatka katsomista" ja "Seuraavat jaksot" ovat erillisiä rivejä (P1-asetus yhdistää). Kirjastot näytetään omina välilehtinään (max 5).
8. ~~Julkiset palvelinosoitteet vaativat HTTPS:n~~ **SOVITTU Turvallisuuden kanssa (S4.3).** HTTP sallitaan vain LAN:issa. Käyttäjälle tiedoksi, koska se on näkyvä rajoite.
9. ~~Repo~~ **RATKAISTU: yksityinen GitHub-repo `kallupx/glassfin`** (käyttäjän päätös 21.10.2026). Se voidaan siirtää organisaatiolle myöhemmin, ja se julkaistaan avoimena julkaisuhetkellä. CI ajetaan GitHub Actionsilla kustannusrajoin (M00): macOS-minuutit kuluvat noin 10-kertaisesti, joten Free-tilillä budjetti on noin 200 macOS-minuuttia kuukaudessa.
10. **CI:n integraatiotestipalvelin – EHDOTUS (v1.2) – vaatii käyttäjän vahvistuksen:** `jellyfin/jellyfin`-Docker-kontit (`10.10.7`, `10.11.11` ja `12.2`) GitHub Actions -servicenä Linux-runnerilla, seedattu pienellä generoidulla tai CC0-testikirjastolla. Ei macOS-minuutteja, ja tunnukset tulevat vain Secretsistä (M00). ⚠️ SDK:n Linux-build on varmistamatta, ja varasuunnitelma on M00:ssa.
11. **Sovelluksen lisenssi: MPL-2.0** – EHDOTUS – vaatii käyttäjän vahvistuksen (käyttäjä päätti 21.10.2026, että appi on ilmainen ja avoin lähdekoodi; ks. §7 R9).
12. ~~Sovelluksen nimi~~ **RATKAISTU: Glassfin** (sama nimi tvOS:llä ja iOS:llä, käyttäjän päätös 21.10.2026). ⚠️ Nimitarkistuksen tulos on §7 R10:ssä.
13. **Bundle ID: `org.glassfin.app`** (tvOS ja iOS jaettuna, universal purchase). Top Shelf -laajennus `org.glassfin.app.topshelf`, App Group `group.org.glassfin.app` ja Keychain access group `$(AppIdentifierPrefix)org.glassfin.app`. **EHDOTUS / placeholder – vaatii käyttäjän vahvistuksen.** Reverse-DNS edellyttää, että käyttäjä omistaa tai hallitsee domainin `glassfin.org`, tai valitaan oma domain.
14. ~~Apple Developer -tili M00:ssa~~ → **pakollinen ennen TestFlightia** (ks. §7 "Vaaditaan ennen TestFlightia").
15. Kaatumisraportointi (MetricKit vai muu).

## 7. Blokkerit, lisenssit ja ennen TestFlightia vaadittavat
### ~~B1~~ → R9 – Lisenssit: RATKAISTU EHDOTUKSELLA (ei enää blokkeri)
**Muutos 21.10.2026:** käyttäjä päätti, että sovellus on **ilmainen ja avointa lähdekoodia**. Siksi B1 on muutettu blokkerista riskiksi R9, jolle on ratkaisuehdotus. M08b ja M14 eivät enää ole lisenssin takia blokattuja (ne ovat yhä P1).

**Sovelluksen lisenssi: MPL-2.0** – **EHDOTUS – vaatii käyttäjän vahvistuksen**
- Sama lisenssi kuin Swiftfinissä ja jellyfin-sdk-swiftissä (varmistettu GitHubista 21.10.2026). Swiftfinin koodia voi käyttää uudelleen, kunhan kopioiduissa tiedostoissa säilyvät tiedostotason MPL-2.0-ilmoitukset.
- MPL-2.0 on tiedostotason copyleft. Se on yhteensopiva LGPL-kirjastojen kanssa, kun ne linkitetään erillisinä dynaamisina kirjastoina.

**Perustelu** (*ei oikeudellinen neuvo*):
- App Store -ehtojen ristiriita on historiallisesti koskenut **GPL**:ää: VLC poistettiin App Storesta vuonna 2011. VLC palasi myöhemmin, kun libVLC oli relisensoitu LGPL:ksi ja iOS-appi MPL/GPL-kaksoislisenssiin. ⚠️ Tämä on historiallista taustatietoa, jota ei tarkistettu uudelleen tässä työssä.
- LGPL-lisensoitua FFmpegiä ja VLCKitiä toimitetaan laajasti App Store -apeissa dynaamisina frameworkeina. Varmistettu esimerkkejä: Swiftly Player ja Sotto IPTV julkaisevat lisenssisivut, joiden mukaan VLCKit on dynaaminen framework ja FFmpeg on buildattu ilman `--enable-gpl`-optiota.
- Koska koko lähdekoodimme on julkinen ja kirjastot linkitetään dynaamisesti, LGPL:n uudelleenlinkitys- ja lähdekoodivelvoitteet täyttyvät: käyttäjä voi buildata appin itse vaihdetulla kirjastolla, ja kirjastojen lähdekoodi on saatavilla.

**Varmistetut lisenssifaktat** (verkkotarkistus 21.10.2026):
- **FFmpeg:** LGPL-2.1+, mutta GPL, jos build sisältää `--enable-gpl`-osia (ffmpeg.org/legal, jossa on myös compliance-checklist).
- **VLCKit:** LGPL-2.1 (libVLC LGPL-2.1+).
- **mpv:** oletuksena GPLv2+, ja LGPLv2.1+ vain `-Dgpl=false`-buildilla. mpv:n Copyright-tiedosto korostaa, ettei flag yksin luo lisenssiä, vaan käytettyjen tiedostojen lisenssit on tarkistettava.
- **MPVKit:** LGPL-oletusvariantti ja erillinen GPL-variantti. Ylläpito on vähäistä.
- **kingslay/FFmpegKit:** GPL-3.0.

**Pakolliset ehdot (L1–L5)**, jotka koskevat M00:aa, M08b:tä, M10:tä ja M14:ää:
- **L1 Vain LGPL-buildit:** FFmpeg ilman `--enable-gpl`- ja `--enable-nonfree`-optioita, mpv `-Dgpl=false`-optiolla (MPVKitistä vain LGPL-variantti, ei `MPVKit-GPL`) ja VLCKit LGPL-buildina ilman GPL-moduuleja. **kingslay/FFmpegKit (GPL-3.0) on kielletty**, samoin x264 ja muut GPL- tai nonfree-komponentit.
- **L2 Dynaamiset frameworkit:** LGPL-kirjastot upotetaan erillisinä dynaamisina frameworkeina ("Embed & Sign"). Niitä ei linkitetä staattisesti.
- **L3 CI-tarkistus (M00):** build epäonnistuu, jos GPL- tai nonfree-konfiguraatio havaitaan.
- **L4 Lisenssitiedostot repossa:** `THIRD_PARTY_LICENSES` sekä source offer tai linkit kunkin binäärikirjaston täsmälleen vastaavaan lähdekoodiin ja build-konfiguraatioon (configure-rivi ja mahdollinen `changes.diff`).
- **L5 Appin sisäinen lisenssinäkymä (M10):** listaa kaikki kolmannen osapuolen komponentit, niiden lisenssit ja lähdekoodilinkit. FFmpegin checklistin mukainen maininta: "This software uses libraries from the FFmpeg project under the LGPLv2.1".

**Jäljelle jäävä riski:** pieni. Se toteutuu, jos riippuvuus vaihtuu huomaamatta GPL-buildiin, ja L3 kattaa tämän. Lopullinen oikeudellinen tulkinta on käyttäjän vastuulla.

### ~~B2 – GitHub-repo~~ RATKAISTU
Repo on **`kallupx/glassfin`** (yksityinen, myöhemmin mahdollisesti organisaatiolle, julkinen julkaisussa). **M00:lla ei ole enää blokkereita.** Avoimena jää vain integraatiotestipalvelimen valinta (§6.10), mutta se ei estä M00:n aloitusta.
- Seuraus: yksityisessä repossa macOS-runnerit kuluttavat ilmaisminuutteja noin 10-kertaisesti. Kustannusrajat ja säästötoimet ovat 00-infra-ci.md:ssä (R13).

### Vaaditaan ennen TestFlightia (ei M00-blokkeri): maksullinen Apple Developer Program
**Ei tarvita kehityksen alkuun** (varmistettu Applen dokumentaatiosta 21.10.2026):
- **CI-simulaattoribuildit ja -testit:** Apple-tiliä ei tarvita (`xcodebuild … CODE_SIGNING_ALLOWED=NO`, simulaattori).
- **Ilmainen Apple ID (Personal Team) omalle laitteelle:** max 3 laitetta ja 3 appia per laite. Provisioning profilet, App ID:t ja laitteet vanhenevat **7 päivän välein**, ja App ID:itä voi rekisteröidä max 10 per 7 päivää (Apple "Developer account overview").

**Applen "Supported capabilities (tvOS)" -taulukko (ilmainen = sarake "Apple Developer"):**
- Sallittu myös ilmaisella tilillä: **App Groups, Keychain sharing, Background modes ja Data protection**. Siksi Top Shelf -laajennus App Groupin tai jaetun Keychainin kanssa onnistuu kehityksessä ilmaisellakin tilillä. ⚠️ Huom: parentin oletus "App Groups vaatii maksullisen tilin" ei pidä paikkaansa Applen taulukon mukaan. Personal Teamin 10 App ID / 7 pv -raja voi kuitenkin haitata, koska jokainen extension on oma App ID.
- **Vain maksullisella tilillä:** Push notifications, iCloud (CloudKit, KVS), Associated domains, Sign in with Apple, Siri, Group Activities (SharePlay), Game Center, In-App Purchase, **User management** (tvOS:n järjestelmäprofiilit, M15 P2) ja App Attest. Multicast-entitlement (UC-A6 LAN-discovery) haetaan erikseen Appleltä ⚠️ (oletettavasti vaatii jäsenyyden).

**TestFlight-automaatio:** App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID` ja `ASC_KEY_P8`) tallennetaan **vain GitHub Actions -secreteiksi** (mieluiten `production`-environment manuaalisella hyväksynnällä). **Avainta ei koskaan laiteta chattiin, repoon, issueihin tai lokeihin.** Käyttäjä lisää sen itse GitHubin UI:ssa. Ks. 00-infra-ci.md `release.yml`.

**Maksullinen jäsenyys (99 $/v) on pakollinen ennen:** TestFlightia, App Store -julkaisua, yli 7 päivän provisioning-profiileja, laitetestausta useammalla kuin kolmella laitteella sekä yllä lueteltuja vain maksullisella tilillä saatavia ominaisuuksia. Ajankohta: viimeistään ennen MVP:n beta-vaihetta.

## 8. Riskit
| # | Riski | Vaikutus | Hallinta |
|---|---|---|---|
| R1 | ~~Trickplay natiivissa transport barissa~~ **Päätetty (ADR M08-1):** I-frame-variantti puuttuu Jellyfinistä, joten tehdään oma sprite-overlay. Jäljellä toteutusriski: natiivin scrub-tilan seuranta vai oma scrub-bar ⚠️ | K1:n laatu ja natiivi tuntuma | Prototyyppi M08:ssa, UI-testi ja Testaajan arvio |
| R2 | Laiteremuxin suorituskyky 50–80 Gt:n tiedostoilla on varmistettu vain GMPlayerin väitteenä | M08b | Prototyyppi ja mittarit ennen M08b:tä |
| R3 | AVPlayer ei käytä appin URLSession-delegaattia, joten itse allekirjoitetun palvelimen media voi epäonnistua, ja token pitää välittää medialle ilman URL:ia ⚠️ | S4.4, S1.5 | **ADR M08-2**: yksi prototyyppi (`AVAssetResourceLoaderDelegate` → dokumentoimaton header-optio → `ApiKey`-fallback). M08b ratkaisee myös. |
| R4 | SDK 3.x (12.x) vs palvelin 10.10 | Yhteensopivuus | Integraatiotestit kolmella palvelinversiolla |
| R5 | `NSAllowsLocalNetworking` ei salli HTTP:tä julkiseen domainiin | Osa käyttäjistä | §6.8, selkeä virheviesti |
| R6 | MPVKitin ylläpito | M14 | Ensisijaisesti VLCKit |
| R7 | Testaaja ei voi ajaa laitetestejä | Laatu | CI-artefaktit. Laitemittaukset tekee Koodari tai käyttäjä ennen julkaisua (ilmaisella Apple ID:llä max 3 laitetta, 7 pv provisiointi). |
| R8 | Multicast-entitlement LAN-discoveryyn ⚠️ | UC-A6 | P1, haetaan Appleltä tarvittaessa |
| R9 | Lisenssit (entinen blokkeri B1) | M08b, M14 | MPL-2.0-appi ja ehdot L1–L5, ks. §7 |
| R10 | **Nimikonflikti "Glassfin"** (tarkistettu 21.10.2026). App Storessa ei löytynyt Glassfin-nimistä iOS- tai tvOS-appia (iTunes Search API). GitHubissa: **KBH-Reeper/GlassFin**, noin 250 tähteä, aktiivinen 9/2026, on **Jellyfin-web CSS-teema** (Liquid Glass -tyylinen), siis samassa ekosysteemissä. Lisäksi pkyanam/jellyflex kuvaa itseään "Glassfin: a Plex-inspired Jellyfin web frontend" (3 tähteä), ja muutama tyhjä `glassfin`-repo. | Sekaannus Jellyfin-yhteisössä ("GlassFin-teema" vs "Glassfin-appi"), hakunäkyvyys ja mahdollinen pyyntö nimenvaihdosta | Käyttäjä päättää, pidetäänkö nimi. Vaihtoehtoja: erottuva kirjoitusasu tai alaotsikko (esim. "Glassfin for Jellyfin"), yhteydenotto teeman tekijään. Tavaramerkkihakua (USPTO/EUIPO) ei tehty ⚠️. Huom: Jellyfinin nimen/logon käyttöön kolmannen osapuolen apissa voi liittyä ohjeita, joita ei tarkistettu ⚠️. |
| R11 | Liquid Glass -yksityiskohdat tvOS:llä varmistamatta (card-tyylin glass, AVPlayerViewControllerin glass, renderöinti A8/A10X-laitteilla) ⚠️ | M05–M08 ulkoasu | ADR M05-1 -prototyyppi ennen M06:ta |
| R13 | GitHub Actions -minuutit yksityisessä repossa: noin 200 macOS-min/kk Free-tilillä (macOS noin 10×, varmistettu GitHub Docsista) | CI pysähtyy kiintiön täytyttyä | M00:n säästötoimet 1–9. Eskalointi: self-hosted Mac, GitHub Pro tai repon aikaisempi julkistus |
| R12 | Glassin GPU-kuorma Apple TV 4K 2. sukupolvella (A12, vanhin glass-laite) | Hitchit | Budjetti G-1…G-5 (M05) |

## 9. Ristiriidat ja epäselvyydet
1. **"Tue kaikkea mitä Android/web/desktop tukevat" vs MVP-skooppi:** ratkaistu vaiheistuksella (§5). Webin ominaisuuksista osa ei ole mielekkäitä tvOS:llä (kirjat, sarjakuvat, metatiedon editointi, laaja admin), joten ne ovat P2 tai iOS-only. Käyttäjän vahvistettava, että tämä tulkinta käy.
2. **"Vähintään yhtä hyvä kuin Infuse" vs AVPlayer-MVP:** Infuse toistaa PGS:n, ASS:n ja DTS/TrueHD:n ilman palvelinta. MVP tarvitsee näihin palvelimen transkoodausta tai burn-inin. Täysi pariteetti vaatii M14:n (P1; lisenssi ei enää estä sitä, ks. §7 R9). Lisäksi Infusen monilähdetuki on rajattu pois (oletus).
3. **"Tehokkain" vs FFmpeg-remux laitteella:** laiteremux lisää muistin- ja CPU:n käyttöä Apple TV:llä mutta vähentää palvelinkuormaa. Speksi priorisoi laitteen sujuvuutta (P12-raja 500 MB).
4. **Ominaisuuspariteetti vs tvOS-alusta:** lataukset ovat mahdottomia tvOS:llä (500 KB) ja kuuluvat vain iOS:lle. Tämä poikkeaa "samat ominaisuudet iOS:llä ja tvOS:llä" -tavoitteesta.
5. **Tutkijan versioehdotukset vanhentuneita:** "tvOS 17 vai 18" → nykyinen on tvOS 27. Palvelin 10.10 → nykyinen on 12.2. Lisäksi 12.0:n breaking changes (legacy auth, `GET /QuickConnect/Initiate`, `/emby`-reitit) on huomioitu.
6. **Turvallisuuden Keychain-luokka:** `...ThisDeviceOnly` on sovittu. Speksi ehdottaa tarkaksi luokaksi `AfterFirstUnlockThisDeviceOnly` Top Shelfin ja taustatoimintojen takia, ja Turvallisuuden pitää vahvistaa se.
7. **Tutkijan raportissa kahdessa versiossa pieni ero:** suoraan Spesifikaatiolle lähetetty osa 4 mainitsee DTS/TrueHD:n VLCKit-varapolun syyksi, ryhmäversio ei. Speksi seuraa laajempaa versiota.

## 10. Puutteet tässä speksissä
- Ryhmächatin transkriptia ei saatu suoraan (ei tallennettu). Tutkijan osat 1–3 luettiin sanatarkasti Tutkijan omasta transkriptista.
- Swiftfin PR #1230:n (admin) ja Swiftfinin DeviceProfile-koodin sisältöä ei katselmoitu. Ne ovat referenssejä Koodarille.
- WebSocket-polun tarkka muoto, Quick Connect -koodin palvelinpuolen vanhenemisaika ja `NSAllowsLocalNetworking`-käyttäytyminen AVPlayerissa tvOS 26:lla ovat varmistamatta (merkitty ⚠️ moduuleihin).
