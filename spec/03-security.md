# M03 – Turvallisuusvaatimukset (P0, poikkileikkaava)

> 🔒 **Turvallisuus-botin katselmointi:** kohdat, joissa on merkintä **[SOVITTU]**, on sovittu Turvallisuuden kanssa (parentin välittämä tiimin linjaus 21.10.2026). Kohdat, joissa on merkintä **[EHDOTUS]**, ovat Spesifikaation lisäyksiä, jotka odottavat Turvallisuuden katselmointia.

**Riippuvuudet:** M01. Vaatimukset toteutetaan `CoreNetworking`-targetissa ja auth-moduulissa (M04). Ne koskevat kaikkia moduuleja.

## S1 Tokenit ja tunnukset
- **S1.1 [SOVITTU]** Access token tallennetaan **vain Keychainiin**, ja asetuksena on `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Turvallisuus vaati `...ThisDeviceOnly`-luokkaa; `AfterFirstUnlock` ehdotetaan, koska tvOS:ssä ei ole lukitusnäyttöä ja Top Shelf tai taustatoiminnot tarvitsevat tokenin. Tarkka luokka on **[EHDOTUS]**, joka odottaa Turvallisuuden vahvistusta. Token ei saa synkronoitua iCloudiin (`kSecAttrSynchronizable = false`).
- **S1.2 [SOVITTU]** **Salasanaa ei tallenneta koskaan** (ei Keychainiin, UserDefaultsiin eikä lokiin). Salasana pidetään muistissa vain `AuthenticateByName`-kutsun ajan, ja kenttä tyhjennetään sen jälkeen.
- **S1.3** Tokenia ei tallenneta UserDefaultsiin, plistiin, Caches-hakemistoon eikä `UserSession`-malliin. Vain `CoreNetworking` lukee sen `SecureStore`-protokollan kautta.
- **S1.4** Keychain-avaimena on `serverId + userId`, mikä mahdollistaa useita palvelimia ja käyttäjiä (P1). DeviceId on oma Keychain-itemnsä.
- **S1.5 [SOVITTU]** Auth-headerin muoto on `Authorization: MediaBrowser Client=, Device=, DeviceId=, Version=, Token=` (ks. 01-core.md). Legacy-headereita ja `api_key`:ta ei käytetä.

## S2 Uloskirjautuminen ja mitätöinti
- **S2.1 [SOVITTU]** Uloskirjautuminen kutsuu **aina** `POST /Sessions/Logout` ja **poistaa tokenin Keychainista**. Jos kutsu epäonnistuu (offline), Keychain tyhjennetään silti, ja käyttäjälle kerrotaan, että palvelimen istunto voi jäädä voimaan, kunnes admin poistaa laitteen (`/Devices`).
- **S2.2** 401 mistä tahansa pyynnöstä → token poistetaan paikallisesti (ks. 02, virhetaulukko).
- **S2.3** Palvelimen poisto listalta poistaa sen kaikki tokenit ja sertifikaattipinnit.

## S3 Quick Connect
- **S3.1 [SOVITTU]** Kulku: `GET /QuickConnect/Enabled` → `POST /QuickConnect/Initiate` (→ `Code` ja `Secret`) → `GET /QuickConnect/Connect?secret=` pollaten → `POST /Users/AuthenticateWithQuickConnect {Secret}`.
- **S3.2** `Secret` pidetään vain muistissa, eikä sitä lokiteta. Näytölle tulee vain `Code`.
- **S3.3 [EHDOTUS]** Pollausväli on 5 s, ja koodi vanhenee/aikakatkaistaan 5 minuutin jälkeen tai näkymästä poistuttaessa (polling-task perutaan). ⚠️ Palvelimen oma koodin vanhenemisaika on varmistamatta, joten 5 min on clientin oma raja.

## S4 Verkkoliikenne ja ATS
- **S4.1 [SOVITTU]** `Info.plist`: `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`. **`NSAllowsArbitraryLoads`-asetusta EI käytetä.** Swiftfin tvOS käyttää sitä (Tutkija varmisti), mutta me jätämme sen tietoisesti pois.
- **S4.2 [SOVITTU]** Kun yhteys ei ole HTTPS, palvelimen lisäyksessä näytetään varoitus "Yhteys ei ole salattu". Asetuksissa palvelinrivillä on pysyvä 🔓-merkintä.
- **S4.3 [SOVITTU] (v1.3.2)** Julkinen HTTP hylätään. Cleartext sallitaan yksityisille osoitteille (127/8, 10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10, `::1`, `fe80::/10`, `fc00::/7`) sekä nimille `.local` ja yksiosaisille hosteille. IPv4-literaali hyväksytään vain kanonisena neliosaisena desimaalina ilman etunollia. Yksiosainen nimi ei ole paikallinen, jos se on pelkkiä numeroita (desimaali tai etunollainen oktaali, esim. `2130706433`, `017700000001`) tai `0x`+hex. Ilman `0x`-etuliitettä oleva heksa (esim. `7f000001`) on tavallinen hostname ja voi jäädä yksiosaiseksi paikalliseksi nimeksi. `.local` ja muut yksiosaiset nimet hyväksytään nimenä; tämä on tunnettu riski. Luokittelu tehdään literaalista, ei DNS-resoluutiosta. `NSAllowsLocalNetworking` ei ole tämän päätöksen peruste.
- **S4.4 [SOVITTU] Itse allekirjoitetut sertifikaatit:** hyväksytään vain käyttäjän vahvistuksen jälkeen. Näkymässä näytetään sertifikaatin **SHA-256-fingerprint**, subject ja voimassaolo. Hyväksynnän jälkeen fingerprint **pinnataan kyseiselle palvelimelle** (`URLSessionDelegate` `didReceive challenge`).
  - Jos pinnattu sertifikaatti vaihtuu, yhteys katkaistaan ja käyttäjälle näytetään varoitus, jossa on vanha ja uusi fingerprint. Hyväksyntä vaatii uuden vahvistuksen.
  - Julkisesti luotettuja (CA-validoituja) sertifikaatteja ei pinnata oletuksena, jotta Let's Encrypt -uusinnat eivät katkaise yhteyttä. **[EHDOTUS]**
  - ⚠️ **Riski:** AVPlayer (AVURLAsset) ei käytä appin URLSession-delegaattia, joten itse allekirjoitetun palvelimen media-URL:t voivat epäonnistua. Ratkaisuvaihtoehdot ovat `AVAssetResourceLoaderDelegate` (custom scheme) tai paikallinen proxy. Tämä on varmistamatta ja vaatii prototyypin M08:ssa. Siihen asti itse allekirjoitettu palvelin toimii API-tasolla, ja toistotuki merkitään "tunnetuksi rajoitteeksi".
- **S4.5** Palvelin-URL validoidaan: vain `http`/`https`-skeemat. Polun normalisointi tukee reverse proxy -alipolkua (`https://host/jellyfin`). Tunnisteet poistetaan URL:sta.

## S5 Lokit ja kaatumisraportit
- **S5.1 [SOVITTU]** **Stream-URL:eja, joissa on token (`ApiKey=`, ja varmuuden vuoksi myös `api_key=` ja `Token=`), ei lokiteta koskaan**, ei konsoliin, `os_log`iin, kaatumisraportteihin eikä diagnostiikkaan.
- **S5.2** Lokitus tehdään yhden `Logger`-wrapperin kautta, joka redaktoi queryparametrit `ApiKey`, `api_key`, `Token`, `secret` ja `Pw` sekä `Authorization`-headerin. Wrapperille kirjoitetaan yksikkötesti, jossa jokainen kielletty kenttä on syötteenä.
- **S5.3** `os_log`-kentät ovat oletuksena `privacy: .private`. Palvelimen nimi ja versio voivat olla public.
- **S5.4** CI:ssä on grep-tarkistus, joka etsii `print(`-kutsuja ja URL-interpolointia lokikutsuissa (lint-sääntö).

## S6 Syötteiden ja median käsittely
- **S6.1** Palvelimelta tuleva metatieto (nimet, kuvaukset, HTML:ää sisältävä overview) näytetään **pelkkänä tekstinä**. HTML-tagit poistetaan, eikä HTML:ää tai Markdownia renderöidä.
- **S6.2** Ulkoiset linkit (`ExternalUrls`) eivät avaudu tvOS:llä. iOS:llä ne avataan vain http(s)-skeemalla.
- **S6.3** Media on epäluotettavaa syötettä. **[SOVITTU]** Mahdolliset FFmpeg-, VLCKit- tai MPV-kirjastot pidetään ajan tasalla (Renovate, tietoturvapäivitykset ≤ 14 päivää julkaisusta), ja niistä käytetään vain tarvittavat demuxerit ja dekooderit (pienempi hyökkäyspinta).
- **S6.4** Tekstitystiedostot (SRT, VTT, ASS) jäsennetään kokorajalla (max 10 MB) ja aikakatkaisulla.
- **S6.5** Haku- ja suodatinparametrit välitetään vain SDK:n query-rakentajan kautta (URL-enkoodaus). Merkkijonoja ei liitetä polkuihin.

## S7 Oikeudet ja admin
- **S7.1** Admin-näkymät näytetään vain, jos `User.Policy.IsAdministrator == true`. Se on vain UI-vihje, sillä **palvelin tekee todellisen autorisoinnin**, ja 403 käsitellään siististi (02).
- **S7.2** Tuhoavat admin-toiminnot (palvelimen uudelleenkäynnistys, käyttäjän tai laitteen poisto) vaativat erillisen vahvistusdialogin, jonka oletusfokus on "Peruuta".

## S8 iOS (myöhemmin)
- **S8.1 [SOVITTU]** iOS-lataukset suojataan Data Protectionilla (`NSFileProtectionComplete` tai vähintään `CompleteUntilFirstUserAuthentication`, jotta taustalataus toimii; tarkka luokka sovitaan M18:ssa). Ne poissuljetaan iCloud-varmuuskopioista (`isExcludedFromBackup`).

## S9 Lisenssit (ei tietoturvaa)
- Ei enää julkaisun este. Ks. SPEC.md §7 R9: appin lisenssiksi ehdotetaan MPL-2.0:aa (EHDOTUS – vaatii käyttäjän vahvistuksen), ja LGPL-ehdot L1–L5 ovat pakollisia. Vain LGPL-buildeja käytetään, mikä tukee myös S6.3:n pientä hyökkäyspintaa (vain tarvittavat demuxerit ja dekooderit).

## Hyväksymiskriteerit
- [ ] Yksikkötestit: Keychain-tallennus käyttää oikeaa accessibility-luokkaa (SecureStore-mock tarkistaa attribuutit), eikä token esiinny UserDefaults-dumpissa.
- [ ] Uloskirjautumisen testi: `POST /Sessions/Logout` kutsutaan, ja Keychain on tyhjä myös silloin, kun kutsu epäonnistuu.
- [ ] `Info.plist` ei sisällä `NSAllowsArbitraryLoads`-asetusta (CI-tarkistus).
- [ ] Itse allekirjoitetun sertifikaatin hyväksyntä ja pinnauksen vaihtuminen on testattu (mock-challenge).
- [ ] Logger-redaktointitesti menee läpi. Integraatiotestin lokidumpissa ei esiinny tokenia (grep).
- [ ] Turvallisuus-botti on katselmoinut tämän tiedoston ja kuitannut [EHDOTUS]-kohdat.
