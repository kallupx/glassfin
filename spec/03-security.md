# M03 – Security requirements (P0, cross-cutting)

> **Security-bot review:** items marked **[AGREED]** are agreed with Security (the parent's relay of the team decision on 21 Oct 2026). Items marked **[PROPOSAL]** are additions from Specification and are waiting for Security's review.

**Dependencies:** M01. The requirements are implemented in the `CoreNetworking` target and in the auth module (M04). They apply to every module.

## S1 Tokens and credentials
- **S1.1 [AGREED]** The access token is stored **only in the Keychain**, with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Security required the `...ThisDeviceOnly` class; `AfterFirstUnlock` is proposed because tvOS has no lock screen and Top Shelf or background work needs the token. The exact class is a **[PROPOSAL]** waiting for Security's confirmation. The token must not sync to iCloud (`kSecAttrSynchronizable = false`).
- **S1.2 [AGREED]** **The password is never stored** (not in the Keychain, not in UserDefaults, not in logs). The password stays in memory only for the `AuthenticateByName` call, and the field is cleared after that.
- **S1.3** The token is not stored in UserDefaults, a plist, the Caches directory, or the `UserSession` model. Only `CoreNetworking` reads it, through the `SecureStore` protocol.
- **S1.4** The Keychain key is `serverId + userId`, which allows several servers and users (P1). DeviceId is its own Keychain item.
- **S1.5 [AGREED]** The auth header form is `Authorization: MediaBrowser Client=, Device=, DeviceId=, Version=, Token=` (see 01-core.md). Legacy headers and `api_key` are not used.

## S2 Logout and revocation
- **S2.1 [AGREED]** Logout **always** calls `POST /Sessions/Logout` and **deletes the token from the Keychain**. If the call fails (offline), the Keychain is still cleared, and the user is told that the server session may stay active until an admin removes the device (`/Devices`).
- **S2.2** A 401 from any request → the token is removed locally (see 02, the error table).
- **S2.3** Removing a server from the list deletes all of its tokens and certificate pins.

## S3 Quick Connect
- **S3.1 [AGREED]** Flow: `GET /QuickConnect/Enabled` → `POST /QuickConnect/Initiate` (→ `Code` and `Secret`) → poll `GET /QuickConnect/Connect?secret=` → `POST /Users/AuthenticateWithQuickConnect {Secret}`.
- **S3.2** `Secret` is kept only in memory and is not logged. The screen shows only `Code`.
- **S3.3 [PROPOSAL]** The poll interval is 5 s, and the code expires or times out after 5 minutes or when the view disappears (the polling task is cancelled). The server's own code lifetime is unverified, so 5 min is the client's own limit.

## S4 Network traffic and ATS
- **S4.1 [AGREED]** `Info.plist`: `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`. **`NSAllowsArbitraryLoads` is NOT used.** Swiftfin for tvOS uses it (the Researcher confirmed), and we leave it out on purpose.
- **S4.2 [AGREED]** When the connection is not HTTPS, adding a server shows the warning "Connection is not encrypted". In Settings the server row has a permanent unlocked indicator.
- **S4.3 [AGREED] (v1.3.2)** Public HTTP is rejected. Cleartext is allowed for private addresses (127/8, 10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10, `::1`, `fe80::/10`, `fc00::/7`) and for `.local` names and single-label hosts. Only IPv4-mapped `::ffff:0:0/96` uses the embedded IPv4 rules. IPv4-compatible `::/96` and NAT64 `64:ff9b::/96` are public. An IPv4 literal is accepted only as canonical four-part decimal with no leading zeros. A single-label name is not local when it is only digits (decimal, or octal with a leading zero, for example `2130706433`, `017700000001`) or `0x` plus hex. Hex without a `0x` prefix (for example `7f000001`) is an ordinary hostname and may remain a single-label local name. `.local` and other single-label names are accepted as names; that is a known risk. Classification uses the literal, not a DNS lookup. `NSAllowsLocalNetworking` is not the basis of this decision.
- **S4.4 [AGREED] Self-signed certificates:** accepted only after the user confirms. The view shows the certificate's **SHA-256 fingerprint**, subject, and validity. After acceptance the fingerprint is **pinned for that server** (`URLSessionDelegate` `didReceive challenge`).
  - If the pinned certificate changes, the connection is dropped and the user sees a warning with the old and new fingerprints. Acceptance requires a new confirmation.
  - Publicly trusted (CA-validated) certificates are not pinned by default, so Let's Encrypt renewals do not drop the connection. **[PROPOSAL]**
  - **Risk:** AVPlayer (AVURLAsset) does not use the app's URLSession delegate, so media URLs on a self-signed server can fail. Options are `AVAssetResourceLoaderDelegate` (custom scheme) or a local proxy. This is unverified and needs a prototype in M08. Until then a self-signed server works at the API level, and playback support is marked a "known limitation".
- **S4.5** The server URL is validated: only `http` / `https` schemes. Path normalization supports a reverse-proxy subpath (`https://host/jellyfin`). Credentials are stripped from the URL.

## S5 Logs and crash reports
- **S5.1 [AGREED]** **Stream URLs that contain a token (`ApiKey=`, and also `api_key=` and `Token=` to be safe) are never logged**, not to the console, `os_log`, crash reports, or diagnostics.
- **S5.2** Logging goes through one `Logger` wrapper that redacts the query parameters `ApiKey`, `api_key`, `Token`, `secret`, and `Pw`, and the `Authorization` header. The wrapper has a unit test whose input includes every forbidden field.
- **S5.3** `os_log` fields are `privacy: .private` by default. The server name and version may be public.
- **S5.4** CI has a grep that looks for `print(` calls and URL interpolation in log calls (lint rule). The shipping check is `scripts/check-forbidden-calls.py`. UI test sources are scanned. A directory named exactly `Tests` is skipped for call checks only.

## S6 Handling input and media
- **S6.1** Metadata from the server (names, descriptions, an overview that contains HTML) is shown as **plain text**. HTML tags are stripped. HTML and Markdown are not rendered.
- **S6.2** External links (`ExternalUrls`) do not open on tvOS. On iOS they open only with an http(s) scheme.
- **S6.3** Media is untrusted input. **[AGREED]** Any FFmpeg, VLCKit, or MPV libraries are kept up to date (Renovate, security updates within 14 days of release), and only the needed demuxers and decoders are used (smaller attack surface).
- **S6.4** Subtitle files (SRT, VTT, ASS) are parsed with a size limit (max 10 MB) and a timeout.
- **S6.5** Search and filter parameters are passed only through the SDK's query builder (URL encoding). Strings are not concatenated into paths.

## S7 Permissions and admin
- **S7.1** Admin views are shown only when `User.Policy.IsAdministrator == true`. That is only a UI hint: **the server does the real authorization**, and a 403 is handled cleanly (02).
- **S7.2** Destructive admin actions (server restart, deleting a user or a device) require a separate confirmation dialog whose default focus is "Cancel".

## S8 iOS (later)
- **S8.1 [AGREED]** iOS downloads are protected with Data Protection (`NSFileProtectionComplete`, or at least `CompleteUntilFirstUserAuthentication` so background downloads work; the exact class is decided in M18). They are excluded from iCloud backup (`isExcludedFromBackup`).

## S9 Licenses (not a security control)
- No longer a release blocker. See SPEC.md §7 R9: the proposed app license is MPL-2.0 (PROPOSAL – needs the user's confirmation), and the LGPL conditions L1–L5 are mandatory. Only LGPL builds are used, which also supports the small attack surface in S6.3 (only the needed demuxers and decoders).

## Acceptance criteria
- [ ] Unit tests: Keychain storage uses the correct accessibility class (the SecureStore mock checks the attributes), and the token does not appear in a UserDefaults dump.
- [ ] Logout test: `POST /Sessions/Logout` is called, and the Keychain is empty even when the call fails.
- [ ] `Info.plist` does not contain `NSAllowsArbitraryLoads` (CI check). The same check rejects `NSExceptionAllowsInsecureHTTPLoads` and `NSExceptionMinimumTLSVersion` followed by TLSv1.0 or TLSv1.1.
- [ ] Accepting a self-signed certificate, and a pin change, are tested (mock challenge).
- [ ] The logger redaction test passes. An integration-test log dump does not contain the token (grep).
- [ ] The Security bot has reviewed this file and signed off the [PROPOSAL] items.
