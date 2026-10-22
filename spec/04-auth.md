# M04 – Palvelimen lisäys ja kirjautuminen (P0)

**Riippuvuudet:** M01, M02, M03 ja M05 (perus-UI-komponentit; voidaan tehdä rinnakkain). **iOS-UI:** P1 (M11).

## Käyttötapaukset
- **UC-A1 (P0)** Ensikäynnistys: käyttäjä syöttää palvelimen osoitteen ja kirjautuu Quick Connectilla.
- **UC-A2 (P0)** Kirjautuminen käyttäjätunnuksella ja salasanalla, kun Quick Connect ei ole käytössä tai käyttäjä haluaa salasanan.
- **UC-A3 (P0)** Uudelleenkäynnistyksen jälkeen käyttäjä on yhä kirjautunut (kipupiste "uloskirjautuminen istuntojen välillä").
- **UC-A4 (P0)** Uloskirjautuminen.
- **UC-A5 (P0)** Itse allekirjoitettu tai salaamaton palvelin (varoitus- ja vahvistusvirta, 03-security S4).
- **UC-A6 (P1)** Palvelimen automaattinen löytö LAN:ista. Jellyfinin UDP-discovery portissa 7359 vaatii tvOS:llä Local Network -luvan ja todennäköisesti Applen multicast-entitlementin (`com.apple.developer.networking.multicast`). ⚠️ Entitlementin tarve on varmistamatta. Se vaatii Applen hyväksynnän ja oletettavasti maksullisen jäsenyyden (SPEC.md §7).
- **UC-A7 (P1)** Useita palvelimia ja käyttäjiä, käyttäjävalitsin käynnistyksessä (`GET /Users/Public`, profiilikuvat). Tämä on osa M15:tä.

## Näyttövirta (tvOS, Siri Remote)
```
Launch ──(token OK: GET /Users/Me 200)──────────────▶ Koti (M06)
   │
   ├─(ei palvelinta)──▶ [A1 Tervetuloa] ──▶ [A2 Palvelimen osoite] ──▶ (GET /System/Info/Public)
   │                                             │  ├─ HTTPS + luotettu ───────────────┐
   │                                             │  ├─ HTTP ─▶ [A2b Varoitus: salaamaton] ─▶│
   │                                             │  └─ itse allekirj. ─▶ [A2c Sertifikaatti + fingerprint] ─▶│
   │                                             ▼                                     ▼
   └─(token 401)──────────────────────────▶ [A3 Kirjautumistapa] ─┬─▶ [A4 Quick Connect -koodi]
                                                                   └─▶ [A5 Tunnus + salasana]
```
- **A1 Tervetuloa:** Glassfin-logo ja -nimi brändikuvan tai liikkeettömän taustan päällä sekä yksi `.glassProminent`-painike "Yhdistä palvelimeen" (oletusfokus). A2–A5 näytetään glass-paneelissa (M05 §2).
- **A2 Palvelimen osoite:** tekstikenttä (tvOS-järjestelmänäppäimistö, myös iPhonen jatkuvuusnäppäimistö toimii automaattisesti) ja painike "Jatka".
  - Syötteen normalisointi: jos skeema puuttuu, kokeillaan ensin `https://`, sitten `http://`. Oletusportit kokeillaan järjestyksessä: syötetty, sitten 8920 (https) ja 8096 (http).
  - Lataustila näytetään painikkeessa. Virheet näytetään inline: "Palvelinta ei löytynyt", "Ei Jellyfin-palvelin", "Palvelimen versio X on liian vanha (vaaditaan ≥ MIN)".
  - Kun palvelin vastaa, näytetään sen nimi (`ServerName`) ja versio.
- **A3 Kirjautumistapa:** jos `GET /QuickConnect/Enabled` on true, **Quick Connect on oletusfokuksessa**, ja vaihtoehtona on "Käytä salasanaa".
- **A4 Quick Connect:** iso 6-merkkinen koodi (`Code`) ja ohje "Avaa Jellyfin puhelimella tai selaimella → Käyttäjä → Quick Connect → syötä koodi". Taustalla pollataan 5 s välein (S3), ja onnistuminen siirtää suoraan kotiin. Valikkonapilla pääsee takaisin, mikä peruu pollauksen. Koodi uusitaan, kun se vanhenee.
- **A5 Tunnus ja salasana:** kaksi kenttää (`.textContentType(.username/.password)`) ja painike "Kirjaudu". Salasanakenttä tyhjennetään virheen jälkeen. Virheviesti 401:lle on "Väärä käyttäjätunnus tai salasana".
- **Fokus:** jokaisella näkymällä on yksi määritelty oletusfokus (`prefersDefaultFocus`). Valikkonappi vie aina edelliseen näkymään, ja A1:ssä se poistuu sovelluksesta (järjestelmän oletus).

## Toimintalogiikka
1. Käynnistyksessä: jos aktiivinen palvelin ja token löytyvät, kutsutaan `GET /Users/Me` (aikakatkaisu 5 s).
   - 200 → koti.
   - 401 → A3 viestillä "Istunto päättyi".
   - Verkkovirhe → **koti välimuistista offline-tilassa**. Käyttäjää ei kirjata ulos verkkovirheen takia (kipupiste UC-A3).
2. Onnistunut kirjautuminen: token ja DeviceId Keychainiin (S1), palvelin UserDefaultsiin ja `POST /Sessions/Capabilities/Full` (PlayableMediaTypes `Video` ja `Audio`, SupportsMediaControl, DeviceProfile M08:sta). Sen jälkeen `AppState.phase = .signedIn`.
3. Uloskirjautuminen (Asetukset → Kirjaudu ulos, vahvistusdialogi): S2.1.

## Hyväksymiskriteerit
- [ ] UC-A1: puhdas asennus → Quick Connect → koti, kaikki pelkällä Siri Remotella. XCUITest mock-palvelimella, kuvakaappaukset A1–A4.
- [ ] UC-A2: väärä salasana → inline-virhe, kenttä tyhjenee, fokus palaa salasanakenttään.
- [ ] UC-A3: appin pakkosulku ja uudelleenkäynnistys → kotinäkymä ilman kirjautumista (UI-testi). Palvelin alhaalla käynnistyksessä → koti välimuistista ja offline-banneri, ei kirjautumisnäkymää.
- [ ] UC-A4: uloskirjautuminen → `POST /Sessions/Logout` kutsuttu (mock verifioi) ja Keychain tyhjä.
- [ ] UC-A5: HTTP-palvelin → varoitusnäkymä. Itse allekirjoitettu → fingerprint näkyy. Hylkäys → ei yhteyttä.
- [ ] Liian vanha palvelinversio → estonäkymä.
- [ ] Quick Connect: näkymästä poistuminen peruu pollauksen (ei verkkopyyntöjä poistumisen jälkeen, testi mock-clientillä).
- [ ] Reverse proxy -alipolku (`https://host/jellyfin`) toimii (integraatiotesti tai mock).
