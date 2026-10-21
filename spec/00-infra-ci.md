# M00 – Infra, repo ja macOS-CI (P0)

**Riippuvuudet:** ei mitään (tehdään ensin). **Omistaja:** Koodari. **Katselmoijat:** Testaaja, Turvallisuus.

## Miksi
Testaajalla on vain Linux-kone. Xcode, tvOS-simulaattori ja XCUITest toimivat vain macOS:llä, joten **kaikki testaus ajetaan CI:ssä macOS-runnerilla**. Testaaja lukee tulokset artefakteista (JUnit, xcresult, kuvakaappaukset).

## Repo
- ✅ **RATKAISTU (21.10.2026): yksityinen GitHub-repo `kallupx/glassfin`.** Se voidaan myöhemmin siirtää organisaatiolle, ja se **julkaistaan avoimeksi julkaisuhetkellä**. M00:lla ei ole enää blokkereita.
  - Siirto organisaatiolle: GitHub ohjaa vanhat URL:t uuteen, mutta Actions-secretit, branch protection -säännöt ja mahdolliset GitHub Apps -asennukset tarkistetaan siirron jälkeen. Workflow'issa ei käytetä kovakoodattua omistajaa (`${{ github.repository }}`).
  - Kun repo muuttuu julkiseksi, standardien GitHub-hostattujen runnerien minuutit ovat ilmaisia (ks. kustannukset alla), ja CI:n rajoituksia voi löysentää.
- Sovelluksen nimi on **Glassfin** (tvOS ja iOS). Bundle ID -ehdotus on `org.glassfin.app` (placeholder, SPEC.md §6.13).
- **Apple Developer -tili ei ole M00:n edellytys:** CI buildaa ja testaa simulaattorilla ilman allekirjoitusta (`CODE_SIGNING_ALLOWED=NO`, ei Apple-tiliä). Omalle laitteelle asennus onnistuu ilmaisella Apple ID:llä (Personal Team, 7 päivän provisiointi). Maksullinen jäsenyys tarvitaan vasta ennen TestFlightia (SPEC.md §7).
- Rakenne:
  ```
  /Packages/GlassfinCore   # Swift package, jaettu tvOS + iOS (M01–M02; speksissä "GlassfinCore")
  /Apps/tvOS               # Glassfin tvOS -app target, UI (ensisijainen)
  /Apps/iOS                # Glassfin iOS -app target, käännetään päivästä 1 (UI aluksi tynkä, M11)
  /Tests/Fixtures          # JSON-fixturet oikeista Jellyfin-vastauksista (12.x ja 10.10/10.11)
  /Tests/Media             # testimediamatriisi (ks. 08-playback.md), ei repossa vaan ladattava
  /spec                    # tämä speksi
  ```
- Xcode-projektin generointi: XcodeGen tai Tuist (Koodari valitsee, jotta projektitiedosto ei aiheuta merge-konflikteja). Tämä on suositus, ei vaatimus.
- Swift 6 -kielitila ja strict concurrency `complete`.
- **Avoin lähdekoodi:** käyttäjän päätös 21.10.2026 on, että appi on ilmainen ja open source. Repo on yksityinen kehityksen ajan ja julkinen julkaisusta alkaen. Lisenssitiedostot ovat mukana alusta asti, jotta julkaisu ei vaadi jälkityötä.
  - Juuressa on `LICENSE` (**MPL-2.0 – EHDOTUS – vaatii käyttäjän vahvistuksen**, ks. SPEC.md §7 R9) ja `THIRD_PARTY_LICENSES` (L4): jokainen riippuvuus, sen versio, lisenssi ja lähdekoodilinkki. Binäärikirjastoille (FFmpeg, VLCKit, MPV) lisätään täsmälleen vastaavan lähdekoodin linkki tai tarball sekä build-konfiguraatio (configure-rivi ja mahdollinen `changes.diff`).
  - Swiftfinistä kopioidut tiedostot säilyttävät MPL-2.0-otsakkeensa ja tekijänoikeusilmoituksensa.

## CI-vaatimukset (GitHub Actions)
- Varmistettu 21.10.2026:
  - GitHubin `xcode-27`-runner-label on yleisesti saatavilla 15.10.2026 alkaen (Apple Silicon). Siinä ovat tvOS 27.0/27.2- ja iOS 27 -SDK:t sekä simulaattorit "Apple TV 4K (3rd generation)" ja "(at 1080p)".
  - `macos-26`-imagessa on Xcode 26.6 ja tvOS 26.x -simulaattorit.
  - **Käytetään vain standardilabeleita** (`xcode-27`, `macos-26`), **ei `xcode-27-xlarge`-labelia**. Larger runnerit eivät kuulu ilmaisminuutteihin edes julkisissa repoissa.

### Kustannusrajat (yksityinen repo)
- Varmistettu GitHub Docsista 21.10.2026:
  - GitHub Free -tilillä yksityisille repoille kuuluu **2 000 Actions-minuuttia kuukaudessa**.
  - macOS-standardirunner maksaa 0,062 $/min ja Linux 2-core 0,006 $/min, eli **macOS kuluttaa minuutteja noin 10-kertaisesti**. Käytännössä budjetti on **noin 200 macOS-minuuttia kuukaudessa**.
  - Minuutit pyöristetään ylöspäin per job.
  - Ilman maksutapaa käyttö estyy kiintiön täytyttyä.
  - Julkisissa repoissa standardirunnerit ovat ilmaisia.
- **Pakolliset säästötoimet:**
  1. **Triggerit:** `pull_request` (kohteena `main`) ja `push` `main`-haaraan. **Ei** feature-haarojen pusheja, **ei** ajastettuja macOS-ajoja oletuksena. `workflow_dispatch` on käsiajoa varten.
  2. **Path-filtterit:** macOS-jobit ajetaan vain, kun muutos koskee `Packages/**`, `Apps/**`, `Tests/**`, `*.xcodeproj`/`project.yml`/`Project.swift`, `Package.resolved` tai `.github/workflows/**`. Pelkät `spec/**`-, `*.md`- ja `docs/**`-muutokset eivät käynnistä macOS-jobeja.
  3. **Concurrency:** `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }`. Saman PR:n uusi push peruu vanhan ajon.
  4. **Välimuistit:** `actions/cache` SPM:lle (`~/Library/Caches/org.swift.swiftpm`, `.build`, avaimena `Package.resolved`-hash) ja DerivedDatalle (avaimena Xcode-versio, `Package.resolved` ja projektitiedoston hash). Muista cache-tallennuksen 10 Gt/repo -raja: vanhat avaimet siivotaan.
  5. **Nopea Linux-job ensin** (`runs-on: ubuntu-latest`, noin 1×-hinta). macOS-jobit riippuvat siitä (`needs: lint`), joten lint- tai lisenssivirhe ei kuluta macOS-minuutteja.
  6. **Kevyt macOS-runko PR:issä:** PR:ssä ajetaan GlassfinCoren testit (`swift test`) sekä tvOS-yksikkö- ja UI-savutestit yhdessä macOS-jobissa (yksi simulaattorin käynnistys). **iOS-testit ajetaan PR:ssä vain, jos muutos koskee `Apps/iOS/**`-polkua tai `Packages/**`-polkua**, ja aina main-pushissa. Raskas UI-testisuite (kaikki XCUITestit ja snapshotit 1080p/4K + saavutettavuusvariantit) ja `XCTMetric`-suorituskykytestit ajetaan **main-pushissa ja PR-labelilla `full-ci`**, ei jokaisessa PR-pushissa.
  7. **Minimiversion tvOS 26 -savutesti** (`macos-26`): käsiajona ja ennen julkaisua/TestFlightia, ei päivittäin (päivittäinen ajo kuluttaisi yksinään merkittävän osan budjetista).
  8. **Aikakatkaisut:** `timeout-minutes` per job (macOS 25 min, Linux 10 min), jotta jumiutunut simulaattori ei polta budjettia.
  9. **Budjettivahti:** GitHubin Billing → Budgets: Actions-budjetti 0 $ ja "Stop usage when budget limit is reached" (käyttäjä asettaa), jotta yllätyslaskuja ei tule. Koodari seuraa kulutusta (Settings → Billing → Usage), ja jos 200 min ei riitä, vaihtoehdot ovat (a) käyttäjän oma Mac self-hosted runnerina (ilmainen minuuteissa; ⚠️ turvallisuus: vain yksityinen repo, ei forkkien PR-ajoja), (b) GitHub Pro (3 000 min ≈ 300 macOS-min) tai (c) repon aikaisempi julkistus.
- Arvio (OLETUS, mitattava ensimmäisillä ajoilla): kylmä tvOS-build ja testit noin 12–15 min, välimuistilla noin 6–8 min. Budjetti riittää siis noin 20–30 PR-ajoon kuukaudessa, jos raskas suite ajetaan harvoin.

### Workflow'n rakenne
- **`ci.yml`:**
  1. **`lint` (Linux, kaikissa PR:issä ja main-pushissa):** SwiftLint ja `swift-format --lint` (molemmat toimivat Linuxilla), **lisenssitarkistuksen Linux-osuus** (L3: `Package.resolved`-estolista, `THIRD_PARTY_LICENSES`-vastaavuus ja lisenssinäkymän datan vastaavuus), CI-grepit (ei `NSAllowsArbitraryLoads`, ei legacy-auth-headereita tai `api_key`:ta, ei `print(`-lokitusta; 03-security.md) sekä `Info.plist`- ja entitlements-tarkistukset. Lisäksi `swift build`/`swift test` niille GlassfinCore-targeteille, jotka eivät riipu Apple-frameworkeista (mallit, mapperit, ticks-muunnokset), jos ne saadaan kääntymään Linuxilla (⚠️ jellyfin-sdk-swiftin/NIOTransportServicesin Linux-yhteensopivuus tarkistamatta; jos ei onnistu, tämä kohta jätetään pois).
  2. **`test-tvos` (`xcode-27`, `needs: lint`, path-filtteri):** `swift test` GlassfinCorelle ja `xcodebuild test -scheme Glassfin-tvOS -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' CODE_SIGNING_ALLOWED=NO -only-testing:<unit + smoke>`.
  3. **`test-ios` (`xcode-27`, `needs: lint`, ehdollinen kohdan 6 mukaan):** `xcodebuild test -scheme Glassfin-iOS -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`. Yksikkötestit ajetaan **molemmille alustoille** (main-pushissa aina).
  4. **`full-ui` (`xcode-27`, main-push tai `full-ci`-label):** kaikki XCUITestit, snapshotit, `XCTMetric`-testit ja **lisenssitarkistuksen binääriosuus** (`otool -L`/`file`, MH_DYLIB, FFmpeg-konfiguraatio; vaatii macOS-buildin, aktivoituu kun FFmpeg/VLC-binääri lisätään).
  5. **Artefaktit:** `.xcresult` (säilytys 7 päivää artefaktitilan 500 Mt -rajan vuoksi), JUnit-raportti (`xcresultparser`/`trainer`) ja XCUITest-kuvakaappaukset. Testaaja katselmoi ne Linuxilla.
  6. **Coverage:** GlassfinCore ≥ 80 % rivikattavuus (P0-moduulit), UI-kerros ei pakollinen.
- **`integration.yml`** (vain `workflow_dispatch` ja ennen julkaisua, ei yöllinen yksityisen repon aikana): GlassfinCore-integraatiotestit oikeaa Jellyfin-palvelinta vastaan.
  - ❓ **AVOIN:** Mitä testipalvelinta käytetään? Vaihtoehdot: (a) käyttäjän oma testipalvelin, jonka URL ja tunnukset ovat GitHub Secretsissä; (b) Linux-job, joka käynnistää `jellyfin/jellyfin`-Docker-kontin (10.10.7, 10.11.x, 12.x) ja ajaa Linuxilla kääntyvät integraatiotestit (halvin, jos GlassfinCore kääntyy Linuxilla); (c) self-hosted Mac.
- **`release.yml` (myöhemmin, TestFlight; vaatii maksullisen Apple Developer Programin, SPEC.md §7):**
  - Allekirjoitus ja upload **App Store Connect API keyllä**, joka tallennetaan **vain GitHub Actions -secreteiksi**: `ASC_KEY_ID`, `ASC_ISSUER_ID` ja `ASC_KEY_P8` (base64), mieluiten `production`-environmentin secreteinä manuaalisella hyväksynnällä.
  - **Avainta ei koskaan liitetä chattiin, issueihin, PR-kommentteihin, lokeihin eikä repoon.** Käyttäjä lisää sen itse GitHubin UI:ssa (Settings → Secrets and variables → Actions). Workflow'ssa avain kirjoitetaan väliaikaistiedostoon, joka poistetaan `always()`-stepissä, eikä sitä tulosteta. GitHub maskaa secretit lokeissa, mutta base64-dekoodattua sisältöä ei kaiuteta.
  - App Store Connectissa avaimelle annetaan pienin riittävä rooli (App Manager tai Developer; ⚠️ tarkka minimirooli TestFlight-uploadille tarkistetaan), ja avain vaihdetaan, jos se epäillään vuotaneen.
  - Triggeri: vain `workflow_dispatch` tai tagi `v*` main-haarasta. Ei koskaan `pull_request`-tapahtumasta, jotta secretit eivät altistu PR-koodille.
- **Salaisuudet yleisesti:** ei tokeneita, palvelin-URL:eja eikä Apple-avaimia repoon. Vain GitHub Secrets. Workflow'ien `permissions:` on oletuksena `contents: read`.
- **Dependency-päivitykset:** Dependabot/Renovate SPM-riippuvuuksille (Dependabot-ajot eivät kuluta Actions-minuutteja, mutta niiden käynnistämät CI-ajot kuluttavat; ryhmitellään viikoittaisiksi PR:iksi). **FFmpeg-pohjaisten kirjastojen päivitykset tarkistetaan viikoittain** (Turvallisuus: ne jäsentävät epäluotettavaa mediaa).

## Testattavuusvaatimukset (koskee kaikkia moduuleja)
- Kaikki palvelut ovat protokollia (`protocol XService`), ja ne injektoidaan konstruktorissa tai `Environment`-arvona. Singletoneja ei käytetä.
- API-asiakas on mockattava (`JellyfinAPIClient`-protokolla, ks. 01-core.md). Testeissä käytetään `MockAPIClient`-toteutusta, joka palauttaa fixture-JSONia.
- Kello, verkon tila, Keychain ja UserDefaults abstrahoidaan (`Clock`, `NetworkMonitor`, `SecureStore`, `SettingsStore`), jotta virhetilanteita voi simuloida.
- Jokaisella näkymällä on `accessibilityIdentifier` XCUITestiä varten (nimeämiskäytäntö `screen.element`, esim. `home.continueWatching.item.0`).
- Launch-argumentit UI-testeille: `-uitest-mock-server` (käytä mockattua API:a), `-uitest-reset` (tyhjennä tila).

## Hyväksymiskriteerit
- [ ] Tyhjä tvOS- ja iOS-app sekä GlassfinCore kääntyvät CI:ssä repossa `kallupx/glassfin`, ja `ci.yml` on vihreä.
- [ ] Säästötoimet 1–8 ovat käytössä: pelkkä `spec/**`-muutos ei käynnistä macOS-jobia, uusi push peruu vanhan ajon, cache-osuma näkyy toisella ajolla, ja lint-virhe estää macOS-jobit (`needs`).
- [ ] Ensimmäisten 10 ajon macOS-minuuttikulutus on kirjattu, ja kuukausiennuste on ≤ 200 min tai eskalointiehdotus (self-hosted, Pro tai julkistus) on tehty käyttäjälle.
- [ ] Yksikkötestit ajetaan sekä tvOS- että iOS-simulaattorilla, ja tulokset näkyvät JUnit-artefaktina.
- [ ] Yksi XCUITest-savutesti (app käynnistyy ja ensimmäinen näkymä näkyy) tuottaa kuvakaappauksen artefaktiksi.
- [ ] Lint estää mergen virheiden kanssa.
- [ ] Testaaja vahvistaa saavansa artefaktit auki Linuxilla.
- [ ] `LICENSE` (MPL-2.0, käyttäjän vahvistuksen jälkeen) ja `THIRD_PARTY_LICENSES` ovat repossa.
- [ ] `license-check` epäonnistuu testihaarassa, johon on lisätty kielletty riippuvuus (esim. kingslay/FFmpegKit) tai `--enable-gpl`-buildi, ja menee läpi puhtaalla mainilla.
