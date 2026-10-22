# M04 – Adding a server and signing in (P0)

**Dependencies:** M01, M02, M03, and M05 (basic UI components; can be done in parallel). **iOS UI:** P1 (M11).

## Use cases
- **UC-A1 (P0)** First launch: the user enters the server address and signs in with Quick Connect.
- **UC-A2 (P0)** Sign in with username and password when Quick Connect is disabled or the user wants a password.
- **UC-A3 (P0)** After a restart the user is still signed in (pain point "signed out between sessions").
- **UC-A4 (P0)** Sign out.
- **UC-A5 (P0)** A self-signed or unencrypted server (warning and confirmation flow, 03-security S4).
- **UC-A6 (P1)** Automatic server discovery on the LAN. Jellyfin's UDP discovery on port 7359 requires the Local Network permission on tvOS and probably Apple's multicast entitlement (`com.apple.developer.networking.multicast`). Whether the entitlement is required is unverified. It needs Apple's approval and presumably a paid membership (SPEC.md §7).
- **UC-A7 (P1)** Several servers and users, and a user picker at launch (`GET /Users/Public`, profile images). This is part of M15.

## Screen flow (tvOS, Siri Remote)
```
Launch ──(token OK: GET /Users/Me 200)──────────────▶ Home (M06)
   │
   ├─(no server)──▶ [A1 Welcome] ──▶ [A2 Server address] ──▶ (GET /System/Info/Public)
   │                                        │  ├─ HTTPS + trusted ───────────────┐
   │                                        │  ├─ HTTP ─▶ [A2b Warning: unencrypted] ─▶│
   │                                        │  └─ self-signed ─▶ [A2c Certificate + fingerprint] ─▶│
   │                                        ▼                                     ▼
   └─(token 401)─────────────────────▶ [A3 Sign-in method] ─┬─▶ [A4 Quick Connect code]
                                                             └─▶ [A5 Username + password]
```
- **A1 Welcome:** the Glassfin logo and name over a brand image or a still background, and one `.glassProminent` button "Connect to server" (default focus). A2–A5 are shown in a glass panel (M05 §2).
- **A2 Server address:** a text field (the tvOS system keyboard; the iPhone continuity keyboard works automatically) and a "Continue" button.
  - Input normalization: if the scheme is missing, try `https://` first, then `http://`. Default ports are tried in order: the entered port, then 8920 (https) and 8096 (http).
  - A loading state is shown on the button. Errors are inline: "Server not found", "Not a Jellyfin server", "Server version X is too old (required ≥ MIN)".
  - When the server responds, show its name (`ServerName`) and version.
- **A3 Sign-in method:** if `GET /QuickConnect/Enabled` is true, **Quick Connect has the default focus**, and the alternative is "Use a password".
- **A4 Quick Connect:** a large 6-character code (`Code`) and the instruction "Open Jellyfin on a phone or in a browser → User → Quick Connect → enter the code". Polling runs in the background every 5 s (S3), and success goes straight to home. The menu button goes back, which cancels polling. The code is renewed when it expires.
- **A5 Username and password:** two fields (`.textContentType(.username/.password)`) and a "Sign in" button. The password field is cleared after an error. The 401 message is "Wrong username or password".
- **Focus:** every view has one defined default focus (`prefersDefaultFocus`). The menu button always goes to the previous view, and on A1 it leaves the app (the system default).

## Behavior
1. At launch: if an active server and a token exist, call `GET /Users/Me` (timeout 5 s).
   - 200 → home.
   - 401 → A3 with the message "Session ended".
   - Network error → **home from cache, offline**. The user is not signed out because of a network error (pain point UC-A3).
2. Successful sign-in: token and DeviceId into the Keychain (S1), server into UserDefaults, and `POST /Sessions/Capabilities/Full` (PlayableMediaTypes `Video` and `Audio`, SupportsMediaControl, DeviceProfile from M08). Then `AppState.phase = .signedIn`.
3. Sign out (Settings → Sign out, confirmation dialog): S2.1.

## Acceptance criteria
- [ ] UC-A1: a clean install → Quick Connect → home, entirely with the Siri Remote. XCUITest against a mock server, screenshots of A1–A4.
- [ ] UC-A2: a wrong password → an inline error, the field clears, and focus returns to the password field.
- [ ] UC-A3: force-quit and relaunch → the home view without signing in (UI test). Server down at launch → home from cache and the offline banner, not the login view.
- [ ] UC-A4: sign out → `POST /Sessions/Logout` was called (the mock verifies) and the Keychain is empty.
- [ ] UC-A5: an HTTP server → the warning view. Self-signed → the fingerprint is visible. Rejection → no connection.
- [ ] A server version that is too old → the blocking view.
- [ ] Quick Connect: leaving the view cancels polling (no network requests after leaving, tested with a mock client).
- [ ] A reverse-proxy subpath (`https://host/jellyfin`) works (integration test or mock).
