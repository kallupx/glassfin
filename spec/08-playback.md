# M08 – Videotoisto (P0, sovelluksen tärkein moduuli)

**Riippuvuudet:** M01, M02, M03, M05 ja M07. **Edellytys M08b:lle:** suorituskykyprototyyppi R2 on läpäisty, ja LGPL-ehdot L1–L5 täyttyvät (SPEC.md §7 R9). Lisenssi ei enää ole blokkeri, koska appi on avointa lähdekoodia ja lisenssiehdotus on MPL-2.0.
**Taustaa (Tutkija, osa 3):** AVPlayer ei avaa MKV:ta eikä tue DTS:ää, TrueHD:ta, PGS:ää tai ASS:ää. Sen vahvuudet ovat natiivi UI, frame rate- ja HDR-matchaus sekä Dolby Vision P5/P8. Apple TV ei bitstreamaa TrueHD:ta tai DTS:ää millään clientillä, ja Atmos onnistuu vain DD+:n (E-AC-3 JOC) kautta.

## Jako
| Osa | Sisältö | Prioriteetti |
|---|---|---|
| **M08a** | AVPlayer-polku: direct play (MP4/MOV/M4V) sekä palvelimen DirectStream (remux HLS:ksi, video kopioidaan) ja Transcode. DeviceProfile, raportointi, natiivi transport bar, raidat, media segments, trickplay ja seuraava jakso. | **P0 (MVP)** |
| **M08b** | Laitteella tehtävä FFmpeg-remux (MKV → fMP4/HLS paikallisesti) → AVPlayer. Vähentää palvelinkuormaa ja säilyttää DV:n MKV:ssä. | **P1** (edellytys: R2-prototyyppi, LGPL-ehdot L1–L5) |
| **M14** | Vaihtoehtoinen toistomoottori (VLCKit tai MPVKit) PGS-, ASS- ja DTS/TrueHD-dekoodaukselle ilman transkoodausta. Infuse-pariteetti. | P1 (LGPL-ehdot L1–L5) |

**OLETUS – vaatii käyttäjän vahvistuksen:** MVP:n toistopolku on **AVPlayer ja palvelimen DirectStream/Transcode-fallback**. Fallback tarvitaan joka tapauksessa. Lisenssin osalta laiteremux on nyt sallittu (MPL-2.0-ehdotus ja LGPL-ehdot, SPEC.md §7 R9), mutta se pysyy P1:ssä, koska sen suorituskyky 50–80 Gt:n tiedostoilla on varmistamatta (R2). Se lisätään M08b:ssä, kun R2-prototyyppi läpäisee mittarit.

## Player-abstraktio (GlassfinCore/CorePlayback)
```swift
public protocol PlaybackEngine: AnyObject, Sendable {           // AVPlayerEngine (P0), RemuxEngine (M08b), VLCEngine/MPVEngine (M14)
  var state: AsyncStream<PlaybackState> { get }                 // idle, loading, playing, paused, buffering, ended, failed(PlaybackError)
  var position: Duration { get }
  func load(_ source: PlaybackSource, startAt: Duration) async throws
  func play(); func pause(); func seek(to: Duration) async
  func select(audio: Track.ID?) async throws; func select(subtitle: Track.ID?) async throws
}
public protocol PlaybackCoordinator { /* PlaybackInfo → engine valinta → raportointi → segments → next-up; testattava ilman UI:ta */ }
```
- `PlaybackCoordinator` on UI-riippumaton, joten iOS käyttää sitä sellaisenaan. tvOS-UI on `AVPlayerViewController`-wrapper (`UIViewControllerRepresentable`).

## Toiston aloitus (sekvenssi)
1. Käyttäjä painaa Toista tai Jatka → `POST /Items/{id}/PlaybackInfo` bodyllä `{DeviceProfile, UserId, StartTimeTicks, MaxStreamingBitrate, AudioStreamIndex?, SubtitleStreamIndex?, MediaSourceId?, EnableDirectPlay:true, EnableDirectStream:true, EnableTranscoding:true, AllowVideoStreamCopy:true, AllowAudioStreamCopy:true}`.
2. Vastauksesta valitaan `MediaSources[0]` (tai käyttäjän valitsema versio):
   - `SupportsDirectPlay` → `GET /Videos/{id}/stream?static=true&mediaSourceId=&playSessionId=&deviceId=&ApiKey=` (PlayMethod `DirectPlay`).
   - muuten `TranscodingUrl` (palvelimen HLS; `DirectStream`, jos video ja ääni kopioidaan, muuten `Transcode`). URL on suhteellinen, joten se liitetään palvelimen base-URL:iin. Tarkistetaan, että se sisältää `ApiKey`:n tai lisätään se. **URL:ia ei lokiteta** (S5.1).
3. `AVURLAsset` → `AVPlayerItem`. `preferredForwardBufferDuration` saa olla oletus.
4. Ensimmäinen ruutu → `POST /Sessions/Playing` (PlaybackStartInfo: ItemId, MediaSourceId, PlaySessionId, PlayMethod, PositionTicks, AudioStreamIndex, SubtitleStreamIndex, CanSeek).
5. Edistyminen: `POST /Sessions/Playing/Progress` 10 s välein **sekä heti** pausessa, jatkossa, kelauksen jälkeen ja raidanvaihdossa (`IsPaused`, `PositionTicks`). Transkoodaussessioissa lisäksi `POST /Sessions/Playing/Ping`, jos palvelin sitä vaatii (OLETUS: 30 s).
6. Lopetus (Menu, loppu tai virhe) → `POST /Sessions/Playing/Stopped {PositionTicks, PlaySessionId, Failed}`. Raportointi sietää verkkovirheen: yksi uudelleenyritys, ja epäonnistunut Stopped tallennetaan muistiin ja lähetetään, kun yhteys palaa (sama appi-istunto).
7. **Automaattinen fallback:** jos AVPlayerItem menee tilaan `.failed` tai ensimmäistä ruutua ei tule 10 sekunnissa direct playssä, PlaybackInfo pyydetään uudelleen `EnableDirectPlay=false`-asetuksella (→ DirectStream), ja sen jälkeen `AllowVideoStreamCopy=false` (→ Transcode). Käyttäjä näkee vain latausindikaattorin, ellei kaikki epäonnistu. Lopullinen virhe näytetään selkokielisenä ("Tätä tiedostoa ei voitu toistaa", lisätiedot Diagnostiikassa).

## DeviceProfile (kipupiste: "tarpeeton transkoodaus")
- Rakennetaan **ajonaikaisesti laitteen kyvyistä**, ei kovakoodatusta listasta. Swiftfinin `DeviceProfile`-laajennus toimii referenssinä (Tutkijan raportti).
- DirectPlayProfiles (AVPlayer):
  - Container `mp4, m4v, mov`.
  - Video `h264, hevc` sekä `av1` vain, jos `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`.
  - Audio `aac, ac3, eac3, alac, flac, mp3`, ja `opus` vain, jos tuki varmistetaan.
- CodecProfiles: HEVC- ja H.264-levelit ja bit depth. `VideoRangeType` sallii `SDR, HDR10, HLG, DOVI, DOVIWithHDR10, DOVIWithSDR` vain, jos näyttö ja laite tukevat niitä (`AVPlayer.availableHDRModes`, `eligibleForHDRPlayback`). Muuten palvelin tone-mappaa.
- TranscodingProfiles: `Type=Video, Protocol=hls, Container=mp4 (fMP4)`, VideoCodec `hevc,h264`, AudioCodec `eac3,ac3,aac`, `MaxAudioChannels=8`, `BreakOnNonKeyFrames=true` (tarkistetaan SDK:n kenttänimet).
- SubtitleProfiles: `vtt` (External/Hls), `mov_text` (Embed). `pgssub, dvdsub, ass/ssa`:
  - MVP: `Encode` (burn-in palvelimella) PGS:lle, VobSubille ja ASS:lle, kun ne valitaan. ASS:lle vaihtoehto on `vtt`-konversio, jolloin tyylit katoavat (asetus, oletus = konversio).
  - M14: client-renderöinti.
- `MaxStreamingBitrate`: LAN 120 Mbps (OLETUS) ja etäyhteys käyttäjän asetus (oletus 20 Mbps). P1: automaattinen arvo `GET /Playback/BitrateTest`-mittauksella.
- **Diagnostiikka-overlay** (Asetukset → Näytä toistotiedot, tai toistossa Info-paneeli): PlayMethod, `TranscodeReasons`, lähteen ja kohteen koodekit, bitrate ja puskuri. Käyttäjä ja Testaaja näkevät heti, miksi transkoodataan.

## Toistonäkymä ja Siri Remote
- **Liquid Glass:** toiston kromi on järjestelmän (`AVPlayerViewController`), jonka oletetaan saavan glass-ulkoasun tvOS 26:ssa automaattisesti (⚠️ varmistetaan ADR M05-1:ssä). Omaa transport baria tai kromia ei tehdä, paitsi M14:n VLC-polulla, jossa oma bar matkii järjestelmän glass-ulkoasua (`glassEffect` `GlassEffectContainer`issa). Toiston aikana näkyvissä on max yksi oma glass-overlay (G-3). Tekstitykset eivät ole glassia.
- **Natiivi `AVPlayerViewController`** (transport bar, clickpad-scrubbaus, ±10 s klikkaus vasemmalle/oikealle, swaipattava scrubbaus ja Info-paneeli alas pyyhkäisemällä).
- Paneelin sisältö: `transportBarCustomMenuItems` (tvOS 15+) ääni-, tekstitys-, laatu- ja nopeusvalikoille, jos natiivi `AVMediaSelectionGroup`-valikko ei kata kaikkia raitoja (esim. palvelimen ulkoiset tekstitykset). `customInfoViewControllers` näyttää jakson tiedot ja Seuraavat jaksot -välilehden.
- **Frame rate- ja dynamic range -matchaus:** `appliesPreferredDisplayCriteriaAutomatically = true`. Toiminta riippuu käyttäjän tvOS-asetuksista (Match Content), ja asetuksissa kerrotaan siitä.
- Now Playing ja MPRemoteCommandCenter: otsikko, sarja, kuva ja kesto Ohjauskeskukseen. Toimii myös iPhonen Remote-sovelluksella.
- **Fokus toistossa:** kun transport bar on piilossa, ainoa fokusoitava elementti on mahdollinen "Ohita intro" -painike.

## Ominaisuudet ja hyväksymiskriteerit
| ID | Ominaisuus (kipupiste) | Vaatimus | Hyväksymiskriteeri |
|---|---|---|---|
| PB1 | Scrubbaus ja kelaus (kipupiste 1) | Natiivi scrubbaus kaikissa PlayMethodeissa. Transkoodauksessa kelaus pyytää uuden streamin `StartTimeTicks`-arvolla, jos HLS ei ulotu kohtaan. | Kelaus mihin tahansa kohtaan toimii direct playssä (P7 ≤ 1,0 s) ja transkoodauksessa (≤ 3 s). ±10 s klikkaus toimii. 20 peräkkäistä kelausta ei jumita toistoa. |
| PB2 | Trickplay-esikatselu | Kun `Trickplay`-data on olemassa (`fields=Trickplay`), scrubbaus näyttää thumbnailin. Kuvat haetaan `GET /Videos/{id}/Trickplay/{width}/{index}.jpg` (tile-kuva, josta rajataan `Interval`/`TileWidth`/`TileHeight`), ja tilet esiladataan scrubbauksen alkaessa. ⚠️ **Avoin tekninen päätös (ADR M08-1):** AVPlayerViewControllerissa ei ole tvOS:llä julkista API:a omille scrub-thumbnaileille (varmistamatta). Vaihtoehdot: (a) palvelimen HLS I-frame/image-playlist, jos AVPlayer hyödyntää sitä; (b) oma overlay natiivin transport barin päälle; (c) oma transport bar. Koodari tekee 1–2 päivän prototyypin ennen toteutusta ja kirjaa päätöksen. | Trickplay-data olemassa → thumbnail näkyy P8:n rajoissa. Ei dataa → scrubbaus toimii ilman thumbnailia. |
| PB3 | Raidanvaihto lennossa (kipupiste 3) | Ääni ja tekstitys ovat yhden painalluksen päässä Info-paneelissa. Upotetut raidat (MP4/HLS) vaihdetaan `AVMediaSelectionGroup`illa ilman uudelleenlatausta. Jos raita vaatii palvelimen muutoksen (esim. transkoodaus tai burn-in), PlaybackInfo pyydetään uudella `AudioStreamIndex`/`SubtitleStreamIndex`-arvolla, ja toisto jatkuu samasta kohdasta. | Upotettu raita vaihtuu ≤ 1 s ilman katkosta (P9). Palvelinvaihto ≤ 4 s, ja kohta säilyy ± 2 s. Valinta raportoidaan Progressissa. |
| PB4 | Raitojen oletusvalinta | Käytetään käyttäjän Jellyfin-asetuksia (`AudioLanguagePreference`, `SubtitleLanguagePreference`, `SubtitleMode`). ⚠️ Kentät tulevat `/Users/Me`-vastauksen `Configuration`-osasta, tarkistettava. Sarjakohtainen muisti: jos käyttäjä vaihtaa raidan jaksossa, sama kieli valitaan seuraavassa jaksossa (P1). | Fixture: käyttäjän kieli fi + elokuvassa fi- ja en-raidat → fi valitaan. |
| PB5 | Tekstitysten renderöinti (tvOS 26:n CJK-neliöbugi) | Tekstiä sisältävät ulkoiset tekstitykset (SRT/VTT → palvelimelta `Stream.vtt`) renderöidään omalla `SubtitleOverlay`-näkymällä järjestelmäfontilla, jossa on CJK-fallback, tai natiivisti, jos testi osoittaa natiivin toimivan. Tyyliasetukset: koko, tausta ja sijainti (P1). | Testimedia, jossa on japanilainen, kiinalainen ja korealainen SRT sekä ASS (konvertoituna) → merkit näkyvät oikein tvOS 26- ja 27 -simulaattorissa ja laitteella (kuvakaappaus). Ei neliöitä. |
| PB6 | Media segments: intro, recap, outro, preview ja commercial (kipupiste 7) | `GET /MediaSegments/{id}` toiston alussa. Kun segmentti alkaa, näytetään `contextualActions`-painike "Ohita intro" / "Ohita kertaus" (tvOS 15+ natiivi). Asetus segmenttityypeittäin: **Kysy (oletus) / Ohita automaattisesti / Älä tee mitään** (Android TV:n malli). Painike häviää segmentin päättyessä. | Mock-segmentti Intro 60–150 s → painike näkyy 60 s kohdalla ja häviää 150 s kohdalla. Painallus kelaa 150 s kohtaan. Auto-tila ohittaa ilman painallusta. Ei segmenttejä (palvelin < 10.10 tai ei dataa) → ei virhettä. |
| PB7 | Seuraava jakso automaattisesti (kipupiste 4) | Jaksolle haetaan seuraava `GET /Shows/{seriesId}/Episodes?startItemId=&limit=2` tai NextUp. Kun Outro-segmentti alkaa (tai 30 s ennen loppua, jos segmenttiä ei ole), näytetään kortti "Seuraava: S1E3 – nimi" (oma `glassEffect`-paneeli, ConcentricRectangle, thumbnail, Reduce Transparency → läpinäkymätön) ja 10 s lähtölaskenta, ja toiminnot ovat "Toista nyt" (`.glassProminent`, oletusfokus) ja "Peru" (`.glass`). Lähtölaskennan jälkeen seuraava jakso alkaa samoilla raitakielillä. Asetus päälle/pois. P1: "Katsotko vielä?" kolmen automaattisen jakson jälkeen ilman käyttäjän toimintaa. | Viimeinen jakso → ei korttia. Muuten lähtölaskenta 10 s → seuraava jakso alkaa, ja edellinen raportoidaan Stopped-kutsulla ja merkitään katsotuksi palvelimella. "Peru" → toisto jatkuu loppuun, ja menu palaa jaksonäkymään, jossa fokus on seuraavassa jaksossa. |
| PB8 | Jatka katselua | `StartTimeTicks` = `UserData.PlaybackPositionTicks`. Detailissä on "Jatka" ja "Alusta". | Jatka alkaa ± 2 s tallennetusta kohdasta. |
| PB9 | Katsottu-tila päivittyy (kipupiste 2) | Raportointi kohtien 4–6 mukaan. Stopped päivittää `UserDataStore`n heti. | P14 ≤ 2 s. Palvelimen dashboardilla näkyy aktiivinen sessio oikealla PlayMethodilla. |
| PB10 | HDR ja Dolby Vision | DV P5/P8 ja HDR10 toistuvat natiivisti, kun näyttö tukee niitä. Muuten palvelin tone-mappaa (DeviceProfile). | Testimatriisin HDR10-, DV P5- ja DV P8.1 MP4 -tiedostot → DirectPlay ja oikea näyttötila (laitetesti). |
| PB11 | Äänet | E-AC-3 (Atmos JOC) ja AC-3 suoraan. DTS, DTS-HD ja TrueHD → palvelin transkoodaa äänen (E-AC-3 tai monikanavainen AAC, kanavat säilyttäen), ja video kopioidaan (DirectStream). Selitys käyttäjälle Info-paneelissa. | MKV (HEVC + TrueHD 7.1) → DirectStream, video copy, audio transcode (diagnostiikka näyttää sen), ja toisto alkaa P6:n rajoissa. |
| PB12 | Virhe kesken toiston | Verkkokatkos → puskurointi-indikaattori. Jos toisto ei palaudu 30 sekunnissa, virheviesti ja "Yritä uudelleen", joka jatkaa samasta kohdasta. Token 401 → 02-virhetaulukon mukaan. | Verkkoyhteyden katkaisu 10 s ajaksi → toisto jatkuu yhteyden palattua ilman käyttäjän toimia. |
| PB13 | Kuvasuhde ja zoom | P1: Aspect fill / fit (`videoGravity`). | – |
| PB14 | Toistonopeus | P1: 0,5–2× (`AVPlayer.rate`, natiivi nopeusvalikko tvOS 16+). | – |
| PB15 | Kappaleet (Chapters) | P1: kappalelista Info-paneelissa (`fields=Chapters`) ja hyppy kappaleeseen. | – |

## Testimediamatriisi (CI-integraatio ja laitetestit)
Testaaja ylläpitää listaa, ja tiedostot ovat testipalvelimella:
1. MP4 H.264 AAC stereo (DirectPlay)
2. MP4 HEVC 10-bit HDR10, E-AC-3 5.1 Atmos (DirectPlay)
3. MP4 DV P8.1, MP4 DV P5 (DirectPlay)
4. MKV H.264 AC-3, SRT ulkoinen + upotettu (DirectStream)
5. MKV HEVC TrueHD 7.1, PGS (DirectStream ja audio transcode, PGS burn-in → Transcode)
6. MKV HEVC DTS-HD MA, ASS (DirectStream ja audio transcode, ASS → VTT)
7. AVI MPEG-4 Part 2 (Transcode)
8. 50–80 Gt UHD remux MKV (R2-suorituskyky)
9. Jakso, jossa intro- ja outro-segmentit sekä trickplay-data
10. CJK-tekstitykset (ja, zh, ko)
11. VobSub (12.0 tukee)

## Moduulin hyväksymiskriteerit
- [ ] PB1–PB12 täyttyvät. Jokaisesta on automaattinen testi, kun se on mahdollista (PlaybackCoordinator mockatulla enginellä ja API:lla), ja laitetesti on kirjattu.
- [ ] Testimatriisin tiedostot 1–7 ja 9–11 toistuvat odotetulla PlayMethodilla (diagnostiikka kirjattu).
- [ ] Raportointisekvenssi Start → Progress×N → Stopped on verifioitu mock-API:lla, mukaan lukien pause, seek, raidanvaihto ja virhe (`Failed=true`).
- [ ] Ei token-URL:eja lokeissa (S5).
- [ ] Muisti P12/P13 ja aloitus P5/P6 täyttyvät.
- [ ] ADR M08-1 (trickplay-toteutus) on kirjattu ennen PB2:ta.

## M08b – laitteella tehtävä remux (P1)
- **Edellytykset:** LGPL-ehdot L1–L5 (SPEC.md §7 R9): FFmpeg ilman `--enable-gpl`- ja `--enable-nonfree`-optioita, dynaaminen framework, CI-tarkistus, `THIRD_PARTY_LICENSES` ja lisenssinäkymä. Lisäksi R2-prototyyppi läpäissyt: 80 Gt:n UHD-remux käynnistyy ≤ 3 s, kelaus ≤ 2 s, muisti ≤ 500 MB ja 2 tunnin toistossa ei ole drop-outeja.
- Laajuus: `RemuxEngine` toteuttaa `PlaybackEngine`n (FFmpeg demux MKV → fMP4-segmentit → paikallinen HLS-palvelin tai `AVAssetResourceLoader`). Valitaan DeviceProfilessa direct playksi MKV-containerille, kun koodekit ovat AVPlayer-yhteensopivia.
- FFmpeg-pohjainen kirjasto: vain LGPL-build. Esim. dynaamisina frameworkeina toimitettu LGPL-2.1+-FFmpeg-build tai oma build. **kingslay/FFmpegKit (GPL-3.0) on kielletty.** Tietoturvapäivitykset S6.3:n mukaan.
- Lisähyöty: itse allekirjoitettujen palvelinten toisto (S4.4-riski), koska verkkoliikenne kulkee appin oman URLSessionin kautta.
