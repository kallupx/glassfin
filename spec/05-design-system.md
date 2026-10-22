# M05 – Design system: Liquid Glass (P0)

**Riippuvuudet:** M00. Voidaan tehdä rinnakkain M01–M04:n kanssa.
**Käyttäjän päätös 21.10.2026:** Glassfinin UI noudattaa **Liquid Glass** -suunnittelukieltä, jonka Apple esitteli iOS 26:n ja tvOS 26:n mukana. Minimi-OS on 26, joten **26:ta vanhemmille versioille ei tehdä fallbackia**.

## 0. Varmistetut faktat (Apple-dokumentaatio, tarkistettu 21.10.2026)
- **API:t ja niiden tvOS 26.0 -saatavuus** (Apple docs JSON -metadata): `View.glassEffect(_:in:)`, `Glass` (`.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`), `GlassEffectContainer`, `View.glassEffectID(_:in:)`, `View.glassEffectUnion(id:namespace:)`, `PrimitiveButtonStyle.glass` ja `.glassProminent`, `View.backgroundExtensionEffect()`, `ConcentricRectangle` ja `View.scrollEdgeEffectStyle(_:for:)`. Kaikki ovat saatavilla tvOS 26.0:sta ja iOS 26.0:sta alkaen, joten ne toimivat jaetussa koodissa ilman `#available`-tarkistuksia.
- **Applen "Adopting Liquid Glass" -ohje, tvOS:**
  - "standard buttons and controls take on a Liquid Glass appearance **when focus moves to them**." Omiin kontrolleihin glass-efekti suositellaan lisättäväksi fokuksessa standardien focus-API:en kautta (`focusable()`, `isFocused`, `@FocusState`).
  - "Apple TV 4K (2nd generation) and newer models support Liquid Glass effects. **On older devices, your app maintains its current appearance.**"
- **Laitetuki** (Apple Support ja MacRumors): tvOS 26 asentuu **kaikkiin Apple TV HD- ja Apple TV 4K -malleihin**, myös vuoden 2015 Apple TV HD:hen (A8). Liquid Glass on käytössä vain **Apple TV 4K 2. sukupolvessa (A12, 2021) ja 3. sukupolvessa (A15, 2022)**. Apple TV HD:ssa (A8) ja 4K 1. sukupolvessa (A10X) on vanha ulkoasu.
- **Applen ohjeet:**
  - Glass kuuluu **navigaatiokerrokseen** (tab bar, sidebar, toolbarit ja kontrollit), ei sisältöön.
  - Glassia käytetään säästeliäästi omissa kontrolleissa ("Avoid overusing").
  - Läheiset glass-elementit ryhmitellään `GlassEffectContainer`iin, koska "glass can not sample other glass" ja ryhmittely parantaa suorituskykyä.
  - Omia taustoja ei tehdä kontrolleihin tai navigaatioelementteihin.
  - Hakuun käytetään semanttista `Tab(role: .search)` -välilehteä.
  - Testaus tehdään Reduce Transparency-, Reduce Motion- ja kontrastiasetuksilla, koska standardikomponentit mukautuvat automaattisesti ja omat elementit pitää testata.
- **Varmistamatta (⚠️):**
  - ⚠️ Saako `.buttonStyle(.card)` tvOS 26:ssa glass-käsittelyn fokuksessa vai säilyykö perinteinen nosto ja parallax?
  - ⚠️ Tuleeko `AVPlayerViewController`in transport bar ja info-paneeli automaattisesti Liquid Glass -tyylisenä? Järjestelmäsoitin on lehdistötietojen mukaan glass-tyylinen, mutta AVKitin dokumentaatiota ei tarkistettu.
  - ⚠️ Vaikuttaako `Glass.interactive()` tvOS:llä mitenkään? WWDC25-session 323 mukaan se on tarkoitettu iOS:n kosketukselle.
  - ⚠️ Miten `glassEffect` renderöityy tarkalleen A8- ja A10X-laitteilla ("maintains its current appearance"): blur-materiaalina vai läpinäkymättömänä?
  - ⚠️ Onko tvOS:ssä Liquid Glassin "tinted/clear"-ulkoasuasetus kuten iOS 26.1:ssä?

## 1. Periaatteet
1. **Sisältö on lavalla, glass on kehys.** Taustakuvat (Backdrop), julisteet ja video ovat täysin läpinäkymätöntä sisältöä. Glassia käytetään vain navigaatiossa, kontrolleissa ja sisällön päälle kelluvissa overlayissa.
2. **Järjestelmäkomponentit ennen omia.** `TabView` (glass automaattisesti), `.searchable` ja `Tab(role: .search)`, `.buttonStyle(.glass)` ja `.glassProminent`, natiivi `AVPlayerViewController`, `Menu` ja `.contextMenu`. Omia glass-elementtejä tehdään vain, jos järjestelmä ei tarjoa vastaavaa, ja silloin ne aina `GlassEffectContainer`issa.
3. **Ei omia taustoja, varjoja tai reunoja kontrolleihin** (Applen ohje). Glassin päälle ei lisätä omia blur-kerroksia.
4. **Väri säästeliäästi:** `Glass.tint` vain merkityksen välittämiseen, esim. ensisijainen Toista-painike järjestelmän accent-värillä. Ei koristetarkoitukseen.
5. **Samankeskiset muodot:** `ConcentricRectangle` ja `containerConcentric` korteissa ja paneeleissa, jotta kulmat linjautuvat glass-paneelien kanssa.
6. **Typografia:** järjestelmäfontti (SF) ja Dynamic Type (tvOS 27:n Dynamic Text -asetus). Glassin päällä SwiftUI käyttää automaattisesti vibrant-tekstiväriä, eikä sitä ohiteta kovakoodatuilla väreillä.

## 2. Mitkä pinnat ovat glassia ja mitkä sisältöä
| Pinta | Materiaali | Toteutus | Huom. |
|---|---|---|---|
| Ylävälilehdet (tab bar) | **Glass (järjestelmä)** | `TabView` ja `Tab`, haku `Tab(role: .search)` | Ei omaa taustaa |
| Toimintopainikkeet detailissa (Toista, Jatka, Katsottu, Suosikki, Lisää) | **Glass** | Toista `.buttonStyle(.glassProminent)`, muut `.buttonStyle(.glass)`, kaikki `GlassEffectContainer`issa | Fokus näyttää järjestelmän glass-korostuksen |
| Kausivalitsin | **Glass** | `.glass`-painikkeet tai `Picker(.segmented)` (⚠️ tarkista tvOS 26:n glass-tyyli) yhdessä containerissa | `glassEffectID`: valinnan siirtymä morphaa |
| Lajittelu- ja suodatinpalkki (kirjasto) | **Glass** | `.glass`-painikkeet ja `Menu`, yksi `GlassEffectContainer` | |
| Julistekortit ja jaksokortit | **Sisältöä (EI glassia)** | `.buttonStyle(.card)` (natiivi nosto ja parallax). ⚠️ Jos tvOS 26 lisää cardille glass-korostuksen, hyväksytään järjestelmän oletus | Kuva on läpinäkymätön. Teksti (nimi, edistyminen) on kuvan alla, ei glassin päällä |
| Backdrop-tausta (koti, detail) | **Sisältöä** | Täysi kuva ja `backgroundExtensionEffect()` reunoille, jos glass-paneeli peittää osan | Gradientti alareunassa luettavuuden takia |
| Offline- ja virhebanneri | **Glass** | `glassEffect(.regular, in: .capsule)` | Ei fokusoitava |
| Kontekstivalikko, raita- ja asetusvalikot | **Järjestelmä** | `.contextMenu`, `Menu` ja `transportBarCustomMenuItems` | |
| Toisto: transport bar ja info-paneeli | **Järjestelmä (oletus glass, ⚠️ varmistettava)** | `AVPlayerViewController` | Ei omaa kromia |
| Toisto: "Ohita intro" ja "Seuraava jakso" -kortti | **Järjestelmä** (`contextualActions`) tai oma **glass** | Ensisijaisesti natiivi `contextualActions`. Seuraava jakso -kortti on oma `glassEffect` (`.regular`, ConcentricRectangle), jossa on thumbnail ja `.glassProminent`-painike "Toista nyt" | Ks. 08-playback.md |
| Tekstitykset videon päällä | **EI glassia** | Oma SubtitleOverlay (PB5): teksti ja puoliläpinäkyvä tumma tausta tai reunus | Glass heikentäisi luettavuutta ja maksaisi GPU-aikaa toiston aikana |
| Quick Connect -koodi, kirjautumislomake | **Glass-paneeli** Backdrop- tai brändikuvan päällä | `glassEffect(.regular, in: ConcentricRectangle())` ja järjestelmän tekstikentät | |
| Asetukset | **Järjestelmä** | `Form` ja `List` (järjestelmän oletustyyli) | |

## 3. Fokuskäyttäytyminen tvOS:llä
- Standardipainikkeet saavat glass-ulkoasun fokuksessa automaattisesti (varmistettu). Omat fokusoitavat elementit (`focusable()`) saavat glassin fokuksessa vain, jos järjestelmäkomponentti ei sovi:
  ```swift
  // havainnollistava
  @Environment(\.isFocused) var isFocused
  content.glassEffect(isFocused ? .regular : .identity, in: .capsule)
  ```
- Fokussiirrot `GlassEffectContainer`in sisällä morphaavat (`glassEffectID`). Kontit ovat samalla `.focusSection()`-alueita.
- Kaikki aiemmat fokussäännöt pätevät edelleen: oletusfokus per näkymä, rivien fokusmuisti ja kuvaus, joka ei ole fokusoitava (M07 säännöt 1–6).
- Play/Pause selausnäkymässä aloittaa toiston fokusoidusta kohteesta (Infuse-tyylinen).

## 4. Luettavuus ja kontrasti
- **L-1** Tekstiä ei sijoiteta suoraan kirkkaan Backdropin päälle ilman glass-paneelia tai alareunan gradienttia (musta 0 → 60 %, alin 40 % korkeudesta).
- **L-2** Glassin päällä käytetään järjestelmän vibrant- ja semanttisia värejä (`.primary`, `.secondary`). Omia tekstivärejä ei käytetä glassin päällä.
- **L-3** Kontrasti on vähintään WCAG AA (4,5:1 leipätekstille, 3:1 isolle tekstille ja ikoneille). Se tarkistetaan snapshot-testeillä kolmella taustalla: kirkas Backdrop, tumma Backdrop ja kirjava juliste.
- **L-4** Jokaisella ikonilla on `accessibilityLabel` (Applen ohje).
- **L-5** `scrollEdgeEffectStyle` (järjestelmän oletus) pitää välilehtipalkin luettavana, kun sisältö vierii sen alle.

## 5. Saavutettavuus
| Asetus | Ympäristöarvo | Käyttäytyminen |
|---|---|---|
| Reduce Transparency | `accessibilityReduceTransparency` | Järjestelmäkomponentit mukautuvat automaattisesti. **Omat glass-pinnat** (banneri, Seuraava jakso -kortti, kirjautumispaneeli) vaihdetaan läpinäkymättömään taustaan (`Color(.secondarySystemBackground)`-tyyppinen semanttinen väri, ⚠️ tvOS:n tarkka semanttinen väri valitaan toteutuksessa). |
| Increase Contrast | `colorSchemeContrast == .increased` | Omille glass-pinnoille ohut reunus (`.separator`), tekstiin `.primary`, ja tint poistetaan. |
| Reduce Motion | `accessibilityReduceMotion` | Glass-morphaus (`glassEffectID`-siirtymät), parallax ja taustan crossfade poistetaan tai korvataan välittömällä vaihdolla. |
| Bold Text / Dynamic Type | – | Asettelu joustaa, eikä tekstejä katkaista kriittisistä kohdista. |

## 6. Suorituskykybudjetti
Glass laskee taustan näytteistyksen ja refraktion reaaliajassa, ja Apple rajoitti sen A12-laitteisiin ja uudempiin.
- **G-1** Glass-pintoja on näkyvissä **samanaikaisesti enintään yksi tab bar ja kaksi `GlassEffectContainer`ia** (esim. detailin painikerivi ja kausivalitsin). Jokaisessa containerissa on max 8 elementtiä.
- **G-2** **Glassia ei käytetä vierivissä soluissa** (kortit ja gridit), koska sadat näytteistävät pinnat vierityksessä aiheuttaisivat hitchejä.
- **G-3** Toiston aikana glassia on vain järjestelmän transport barissa ja yksittäisessä overlayssä (segment- tai next-up-kortti). Jatkuvasti näkyviä glass-elementtejä ei ole.
- **G-4** Mittarit (M02:n P3-taulukon lisäksi):
  - Apple TV 4K 2. sukupolvi (A12, vanhin glass-laite): **detailin ja kodin fokusvieritys hitch-ratio < 10 ms/s, 60 fps**.
  - A15: < 5 ms/s.
  - Apple TV HD (A8, vanhin tvOS 26 -laite, ei glassia): < 10 ms/s.
  - Mittaus Instrumentsin Hitches- ja Core Animation -työkaluilla ennen jokaista julkaisua.
- **G-5** Jos A12:lla mittari ei täyty, ensin vähennetään glass-pintoja, ei sisältöä.

## 7. Komponentit
| Komponentti | Kuvaus | Fokus |
|---|---|---|
| `PosterCard` | 2:3-juliste, nimi alla (fokuksessa), edistymispalkki, katsottu-merkki ja jaksolaskuri. ConcentricRectangle-kulmat. | `.buttonStyle(.card)`, kontekstivalikko pitkällä painalluksella |
| `LandscapeCard` | 16:9 Thumb tai Backdrop, edistyminen ja "32 min jäljellä" | Kuten yllä |
| `MediaRow` | Otsikko ja `LazyHStack`, `.focusSection()`, fokusmuisti | – |
| `HeroHeader` | Täysi Backdrop ja `backgroundExtensionEffect`, Logo, metarivi sekä **glass-painikerivi** `GlassEffectContainer`issa (Toista = `.glassProminent`) | Toista-painike on oletusfokus. Kuvaus ei ole fokusoitava, ja "Lisää" avaa koko tekstin |
| `GlassActionBar` | Uudelleenkäytettävä painikerivi: `GlassEffectContainer` ja `.glass`/`.glassProminent`-painikkeet | `.focusSection()` |
| `GlassBanner` | Offline- ja virheilmoitus (capsule glass, Reduce Transparency -fallback) | Ei fokusoitava |
| `AsyncPoster` | Blurhash-placeholder → kuva (fade 150 ms) | – |
| `SkeletonRow` | Shimmer, samat mitat kuin lopullisella rivillä | – |
| `ErrorStateView` | Ikoni, viesti ja `.glassProminent` "Yritä uudelleen" | Oletusfokus |

## 8. Navigaatio ja näyttöhierarkia (tvOS)
```
TabView (Liquid Glass -välilehtipalkki, järjestelmä)
├── Koti (M06)
├── [Kirjasto 1] … [Kirjasto N]   (UserViews; OLETUS max 5, loput "Kirjastot"-välilehdelle)
├── Haku  — Tab(role: .search) (M09)
└── Asetukset (M10)
Jokaisessa välilehdessä NavigationStack:
  Kirjasto → Detail (M07) → Kausi/jaksot (M07) → Toisto (M08, fullScreenCover)
```
- Menu-nappi: sisäkkäisessä näkymässä takaisin, välilehden juuressa välilehtipalkkiin, ja välilehtipalkista poistuminen (järjestelmä).
- iOS (M11): sama `TabView` (iOS 26:n glass-tab bar) ja `Tab(role: .search)`. `tabViewStyle(.sidebarAdaptable)` iPadilla ja `tabBarMinimizeBehavior` iPhonella (⚠️ vain iOS).

## Hyväksymiskriteerit
- [ ] Glass-pinnat vastaavat §2:n taulukkoa (koodikatselmointi): ei glassia korteissa eikä tekstityksissä, ja omat glass-elementit ovat aina `GlassEffectContainer`issa.
- [ ] Kontrollien ja navigaation omat taustat eivät ole sallittuja (SwiftLint-sääntö tai katselmointi).
- [ ] Snapshot-testit 1080p:llä ja 4K:lla: oletus, Reduce Transparency, Increase Contrast ja Reduce Motion (CI-artefakti Testaajalle).
- [ ] Kontrasti on AA kolmella testitaustalla (L-3).
- [ ] XCUITest: `MediaRow`-fokusmuisti, HeroHeaderin kuvaus ei saa fokusta, ja Toista on oletusfokus.
- [ ] Suorituskyky G-4 on mitattu laitteilla Apple TV 4K 2. sukupolvi ja Apple TV HD (kirjataan julkaisuun).
- [ ] ⚠️-kohdat (card-tyylin glass, AVPlayerViewControllerin glass, A8/A10X-renderöinti, `interactive()` tvOS:llä) on selvitetty prototyypillä ja kirjattu ADR M05-1:een ennen M06:ta.
