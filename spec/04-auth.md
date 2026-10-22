# M04 – Adding a server and signing in (P0)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M01, M02, M03, and M05 (basic UI components; can be done in parallel). **iOS UI:** P1 (M11).

## Use cases
- **UC-A1 (P0)** First launch: the user enters the server address and signs in with Quick Connect.
- **UC-A2 (P0)** Sign-in with a username and password, when Quick Connect is not enabled or the user wants a password.
- **UC-A3 (P0)** After a restart the user is still signed in (the pain point "sign-out between sessions").
- **UC-A4 (P0)** Sign-out.
- **UC-A5 (P0)** A self-signed or unencrypted server (the warning and confirmation flow, 03-security S4).
- **UC-A6 (P1)** Automatic server discovery on the LAN. Jellyfin's UDP discovery on port 7359 requires the Local Network permission on tvOS and probably Apple's multicast entitlement (`com.apple.developer.networking.multicast`). ⚠️ Whether the entitlement is required is unverified. It requires Apple's approval and presumably paid membership (SPEC.md §7).
  - **Security (S4.7):** discovery responses are untrusted. The list shows each discovered server's **name and address** ("Home server — http://192.168.1.10:8096" (fi: "Kotipalvelin — http://192.168.1.10:8096")), and the user chooses the server themselves. There is no automatic connection or sign-in. After the choice, the flow continues as in A2 (`GET /System/Info/Public`, the HTTP warning, the certificate flow, the id comparison). Manual address entry is always available.
- **UC-A7 (P1)** Several servers and users, a user picker at launch (`GET /Users/Public`, profile images). This is part of M15.

## Screen flow (tvOS, Siri Remote)
```
Launch ──(token OK: GET /Users/Me 200)──────────────▶ Home (M06)
   │
   ├─(no server)──▶ [A1 Welcome] ──▶ [A2 Server address] ──▶ (GET /System/Info/Public)
   │                                        │  ├─ HTTPS + trusted ────────────────────┐
   │                                        │  ├─ HTTP ─▶ [A2b Warning: unencrypted] ─▶│
   │                                        │  └─ self-signed ─▶ [A2c Certificate + fingerprint] ─▶│
   │                                        ▼                                          ▼
   └─(token 401)─────────────────────▶ [A3 Sign-in method] ─┬─▶ [A4 Quick Connect code]
                                                             └─▶ [A5 Username + password]
```
- **A1 Welcome** (fi: "Tervetuloa"): the Glassfin logo and name over a brand image or a still backdrop, and one `.glassProminent` button "Connect to a server" (fi: "Yhdistä palvelimeen") (default focus). A2–A5 are shown in a glass panel (M05 §2).
- **A2 Server address** (fi: "Palvelimen osoite"): a text field (the tvOS system keyboard; the iPhone continuity keyboard also works automatically) and a button "Continue" (fi: "Jatka").
  - Input normalization: if the scheme is missing, try `https://` first, then `http://`. Default ports are tried in order: the one entered, then 8920 (https) and 8096 (http).
  - A loading state is shown in the button. Errors are shown inline: "Server not found" (fi: "Palvelinta ei löytynyt"), "Not a Jellyfin server" (fi: "Ei Jellyfin-palvelin"), "Server version X is too old (required ≥ MIN)" (fi: "Palvelimen versio X on liian vanha (vaaditaan ≥ MIN)").
  - When the server answers, its name (`ServerName`) and version are shown.
- **A3 Sign-in method** (fi: "Kirjautumistapa"): if `GET /QuickConnect/Enabled` is true (start with the call `POST /QuickConnect/Initiate`), **Quick Connect has the default focus**, and the alternative is "Use a password" (fi: "Käytä salasanaa").
- **A4 Quick Connect:** a large 6-character code (`Code`) and the instruction "Open Jellyfin on a phone or in a browser → User → Quick Connect → enter the code" (fi: "Avaa Jellyfin puhelimella tai selaimella → Käyttäjä → Quick Connect → syötä koodi"). Polling runs in the background every 5 s (S3), and success goes straight to home. The Menu button goes back, which cancels polling. The code is renewed when it expires.
- **A5 Username and password** (fi: "Tunnus ja salasana"): two fields (`.textContentType(.username/.password)`) and a button "Sign in" (fi: "Kirjaudu"). The password field is cleared after an error. The error message for 401 is "Incorrect username or password" (fi: "Väärä käyttäjätunnus tai salasana").
- **Focus:** every view has one defined default focus (`prefersDefaultFocus`). The Menu button always goes to the previous view, and on A1 it exits the application (the system default).

## Behavior
1. At launch: if an active server and a token are found, call `GET /Users/Me` (timeout 5 s).
   - 200 → home.
   - 401 → A3 with the message "Session expired, please sign in again" (fi: "Istunto päättyi, kirjaudu uudelleen") (Q4-11).
   - A network error → **home from the cache in the offline state**. The user is not signed out because of a network error (pain point UC-A3).
2. A successful sign-in: the token and DeviceId go into the Keychain (S1), the server goes into UserDefaults, and `POST /Sessions/Capabilities/Full` (PlayableMediaTypes `Video` and `Audio`, SupportsMediaControl, DeviceProfile from M08). Then `AppState.phase = .signedIn`.
3. Sign-out (Settings → "Sign out" (fi: "Asetukset → Kirjaudu ulos"), a confirmation dialog): S2.1.

## Acceptance criteria
- [ ] UC-A1: a clean install → Quick Connect → home, all with only the Siri Remote. An XCUITest with a mock server, screenshots A1–A4.
- [ ] UC-A2: a wrong password → an inline error, the field clears, and focus returns to the password field.
- [ ] UC-A3: force-quit the app and restart → the home view without signing in (UI test). The server down at launch → home from the cache and the offline banner, not the sign-in view.
- [ ] UC-A4: sign-out → `POST /Sessions/Logout` was called (the mock verifies) and the Keychain is empty.
- [ ] UC-A5: an HTTP server → the warning view. Self-signed → the fingerprint is shown. Rejection → no connection.
- [ ] A server version that is too old → the blocking view.
- [ ] Quick Connect: leaving the view cancels polling (no network requests after leaving, a test with the mock client).
- [ ] A reverse-proxy subpath (`https://host/jellyfin`) works (an integration test or a mock).
- [ ] Quick Connect is started with the call **`POST /QuickConnect/Initiate`** (the mock verifies the method; `GET` was removed in 12.0).
- [ ] A public `http://` address → the error "Public addresses require HTTPS" (fi: "Julkiset osoitteet vaativat HTTPS:n") (S4.3).
- [ ] UC-A6 (P1): a forged discovery response → the address is shown, no automatic connection (S4.7).

## Clarifications v1.3.3 (22.10.2026, the Tester's questions)
- **Q4-01, MIN:** `10.10.0`. The version is read from the `Version` field of the `GET /System/Info/Public` response: the numeric `major.minor.patch` part is compared, and a possible suffix (`-rc1`, `-beta`, and so on) is ignored. An RC version is accepted if its numeric part is ≥ 10.10.0. An unparsed version → "Not a Jellyfin server" (fi: "Ei Jellyfin-palvelin"). CI tests 10.10.7, 10.11.11, and 12.2. The ruling is deliberately more permissive than the official Kotlin SDK's minimum of 12.0.0, because the user confirmed support for version 10.10+.
- **Q4-02, schemes, ports, and timeout:**
  - A subpath (`/jellyfin`) is kept as-is on every attempt, and a trailing `/` is removed.
  - If the user gave a scheme, only that scheme is tried. `https://` never changes to `http://`.
  - If the user gave a port, only that port is tried: first `https`, then `http`.
  - If no scheme or port was given, the order is: 1) `https://host` (443), 2) `https://host:8920`, 3) `http://host:8096`, 4) `http://host` (80).
  - HTTP attempts are made only if S4.3 allows the host. Otherwise they are skipped, and if nothing succeeds, the `publicHTTPRejected` message is shown.
  - The order deliberately differs from the Kotlin SDK's `AddressCandidateHelper`, which tries Jellyfin's ports before the default ports: 443 is first, because servers that use HTTPS are usually behind a reverse proxy.
  - Local names for HTTP (S4.3): `.local`, single-label names, and private IP addresses. `.lan`, `.internal`, and `.home.arpa` are not local, because ATS would block them. They produce an error that includes guidance to use an IP address.
  - Attempts are made one after another, 5 s per attempt and an overall cap of 20 s. The first response that is a valid Jellyfin response (`Id` and `ProductName`) wins.
  - A move to the next attempt happens only if the connection is refused (connection refused) or times out. A DNS error ends the search immediately with the error "Server not found" (fi: "Palvelinta ei löytynyt"), because the same name would also fail over HTTP (aligned with Security's Q4-03). A certificate error (a `serverTrust` failure) does not move to the next attempt; it opens A2c, so there is no fallback from HTTPS to HTTP because of a TLS error (Q4-03, 🔒 Security confirms).
- **Q4-09, `/Users/Me` at launch:** the rule in 04 applies at launch: 5 s, no retries. A timeout or a connection error → home from the cache in the offline state (K10) and a background ping every 10 s (02). 401 → sign-out per S2.2. 02's 15 s and 2 retries apply to other API calls.
- **Q4-05, default focus:**
  - **A2:** the text field. If the field is already filled (coming back), the default focus is "Continue" (fi: "Jatka").
  - **A2b (unencrypted):** "Cancel" (fi: "Peruuta"). "Continue unencrypted" (fi: "Jatka salaamattomana") requires a deliberate move.
  - **A2c (certificate):** "Cancel" (fi: "Peruuta"). The accept button requires a deliberate move.
- **Q4-18:** A move to the next candidate also happens when the response is HTTP 2xx but not a valid Jellyfin response (`Id` or `ProductName` is missing, or the JSON does not parse). An example is a router's or a reverse proxy's default page. If no candidate succeeds and at least one answered something other than Jellyfin, the error is "Not a Jellyfin server" (fi: "Ei Jellyfin-palvelin"). Otherwise the error is "Server not found" (fi: "Palvelinta ei löytynyt"). A TLS or certificate error and a DNS error stop the search as before.
- **Q4-19:** A two-part version (`10.10`) is accepted and interpreted as `10.10.0`. A one-part or non-numeric version is treated as unparsed.
- **Q4-14:** If `StartupWizardCompleted = false`, sign-in does not continue. The message shown is "Server setup is incomplete. Finish setup in a browser at <server URL>" (fi: "Palvelimen käyttöönotto on kesken. Viimeistele asennus selaimella osoitteessa <palvelimen URL>"). A guided setup is not implemented in the app (P0). The admin module M17 may add it later. "Try again" (fi: "Yritä uudelleen") calls `/System/Info/Public` again.
- **Q4-20:** `publicHTTPRejected` with the reverse-proxy guidance (S4.3) is shown only when the user explicitly typed `http://` for a public host. In every other case where no candidate succeeds, the normal error applies ("Server not found" (fi: "Palvelinta ei löytynyt"), or Q4-18's "Not a Jellyfin server"). If HTTP candidates were skipped because S4.3 does not allow HTTP for that host, the error carries a flag (`httpSkippedByPolicy`) and the UI adds the hint line "If your server only uses HTTP, it must be on your local network" (fi: "Jos palvelimesi käyttää vain HTTP:tä, sen pitää olla lähiverkossa"), from `Localizable.xcstrings`. Tests assert the flag and the string key, not the text.
- **Q4-06:** If `GET /QuickConnect/Enabled` is false, A3 is skipped and the flow goes straight to A5. Menu on A5 then returns to A2.
- **Q4-07:** A3 calls only `GET /QuickConnect/Enabled`. `POST /QuickConnect/Initiate` is called when A4 opens, never on A3.
- **Q4-08:** While A4 is visible, an expired code is renewed automatically (a new `Initiate`) at most 3 times. After that A4 shows "The code expired" (fi: "Koodi vanheni") and a "Get a new code" (fi: "Hae uusi koodi") button with default focus. Going to the background cancels polling. On return to A4, a code younger than 5 minutes is checked once immediately and polling resumes; an older code is renewed (counts toward the limit).
- **Q4-10:** On launch, `/Users/Me` 403 or 5xx never signs the user out and keeps the token; the result is the same as a network error (Q4-09): home from cache with `connectivity = .serverUnreachable`, the banner, and the 10 s ping. With no cached snapshot, home shows the M05 full-screen error state "Can't reach the server" (fi: "Palvelimeen ei saada yhteyttä") with "Try again" (fi: "Yritä uudelleen", default focus). The tab bar stays usable, so Settings and sign-out remain reachable. Never the sign-in view.
- **Q4-11:** One message everywhere: "Session expired, please sign in again" (fi: "Istunto päättyi, kirjaudu uudelleen"), one string key. 04 TL1's "Session ended" is replaced by it.
- **Q4-12:** Sign-out removes the token but keeps the server. It goes to the user picker if other users of the same server are saved, otherwise to A3 (or A5 under Q4-06). The confirmation dialog's default focus is "Cancel" (fi: "Peruuta"). Before M10, sign-out lives in a minimal Settings tab placeholder that shows only "Sign out" (fi: "Kirjaudu ulos") and the app version; M10 replaces it.
- **Q4-13:** Before M08, `POST /Sessions/Capabilities/Full` sends `PlayableMediaTypes` [`Video`, `Audio`], `SupportsMediaControl = false` and no `DeviceProfile` (the field is optional); M08 adds the profile and sets media control. A failed call does not block `.signedIn`; it is retried once on the next launch or foreground, and logged redacted.
- **Q4-15:** Sign-in messages (A5 and A4): network error or timeout, "Can't reach the server. Check your connection and try again." (fi: "Palvelimeen ei saada yhteyttä. Tarkista yhteys ja yritä uudelleen."); 5xx, "The server ran into a problem. Try again later." (fi: "Palvelimella tapahtui virhe. Yritä myöhemmin uudelleen."); Quick Connect `AuthenticateWithQuickConnect` 401, "Quick Connect sign-in failed. Get a new code and try again." (fi: "Quick Connect -kirjautuminen epäonnistui. Hae uusi koodi ja yritä uudelleen."). Tests compare error types and keys.
- **Q4-16:** Proposal pending Security: the S4.7 rule (plain text, 64 characters) applies to `ServerName` everywhere it is shown, including A2 and the user picker.
- **Q4-17:** Resolved (all files v1.3.3).
