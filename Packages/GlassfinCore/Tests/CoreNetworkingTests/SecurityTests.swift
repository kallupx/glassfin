import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class SecurityCredentialTests: XCTestCase {
    private let serverID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let userID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    private let otherUser = "cccccccccccccccccccccccccccccccc"
    private let otherServer = "dddddddddddddddddddddddddddddddd"
    private let token = "token-value-should-not-leak"
    private let accessGroup = "TEAMID.org.glassfin.app"

    /// T03-18. The keychain write uses AfterFirstUnlockThisDeviceOnly, and the token is absent from settings.
    func testT03_18_keychainAttributesAndSettingsDump() throws {
        let secure = AttributeSecureStore()
        let settings = InMemorySettingsStore()
        let vault = CredentialVault(secureStore: secure, settings: settings, accessGroup: accessGroup)
        let profile = StoredSessionProfile(
            serverID: serverID,
            serverName: "Living Room",
            serverURL: "https://media.example",
            userID: userID,
            userName: "Ada",
            isAdministrator: false
        )
        try vault.save(token: token, serverID: serverID, userID: userID, profile: profile)
        let account = try CredentialVault.tokenAccount(serverID: serverID, userID: userID)
        let attributes = try XCTUnwrap(secure.attributes(for: account))
        XCTAssertEqual(attributes.accessibility, "AfterFirstUnlockThisDeviceOnly")
        XCTAssertFalse(attributes.synchronizable)
        XCTAssertEqual(attributes.accessGroup, accessGroup)
        XCTAssertNotEqual(account, DeviceIdentityStore.account)
        XCTAssertEqual(try vault.loadToken(serverID: serverID, userID: userID), token)

        let dump = settings.allValues().map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        XCTAssertFalse(dump.contains(token))
        XCTAssertTrue(dump.contains("Living Room"))
        let session = UserSession(
            server: ServerInfo(
                id: serverID, name: "Living Room", url: URL(string: "https://media.example")!,
                version: SemVer(major: 12, minor: 2, patch: 0)
            ), userID: userID, userName: "Ada", isAdministrator: false)
        XCTAssertFalse(String(describing: session).contains(token))
        let json = String(decoding: try JSONEncoder().encode(session), as: UTF8.self)
        XCTAssertFalse(json.contains(token))
        XCTAssertThrowsError(try vault.save(token: "", serverID: serverID, userID: userID, profile: profile)) {
            error in
            XCTAssertEqual(error as? SecurityInvariantError, .internalInvariant)
        }
    }

    /// T03-17. The password field is empty after authenticate, and settings reject password keys.
    func testT03_17_passwordIsNotStored() async throws {
        var field = PasswordField("hunter2")
        let seen = await field.authenticate { password in password }
        XCTAssertEqual(seen, "hunter2")
        XCTAssertTrue(field.isEmpty)

        let settings = InMemorySettingsStore()
        let guarded = GuardedSettings(store: settings)
        XCTAssertThrowsError(try guarded.set("hunter2", forKey: "password")) { error in
            XCTAssertEqual(error as? SecurityInvariantError, .internalInvariant)
        }
        XCTAssertThrowsError(try guarded.set(token, forKey: "access_token"))
        XCTAssertThrowsError(try guarded.set("qc", forKey: "quick-connect-secret"))
        try guarded.set("Living Room", forKey: "server-name")
        let dump = settings.allValues().values.joined(separator: "\n")
        XCTAssertFalse(dump.contains("hunter2"))
        XCTAssertFalse(dump.contains(token))
        XCTAssertTrue(dump.contains("Living Room"))
    }

    /// T03-19. Logout always posts /Sessions/Logout and clears the keychain when that call fails.
    func testT03_19_logoutClearsKeychainWhenTheServerCallFails() async throws {
        let secure = AttributeSecureStore()
        let settings = InMemorySettingsStore()
        let vault = CredentialVault(secureStore: secure, settings: settings, accessGroup: accessGroup)
        try save(token, server: serverID, user: userID, vault: vault)
        try save("other-token", server: serverID, user: otherUser, vault: vault)
        try save("kept-token", server: otherServer, user: userID, vault: vault)
        let pins = SettingsCertificatePinStore(settings: settings)
        let fingerprint = CertificateFingerprint.sha256Hex(Data("leaf".utf8))
        try pins.save(fingerprint: fingerprint, serverID: serverID)
        try pins.save(fingerprint: fingerprint, serverID: otherServer)

        let client = RecordingAPIClient(error: .network)
        let failed = await CoreNetworking.SessionTermination.logOut(
            serverID: serverID, userID: userID, vault: vault, client: client)
        XCTAssertEqual(client.calls().map(\.path), ["/Sessions/Logout"])
        XCTAssertEqual(client.calls().map(\.method), ["POST"])
        XCTAssertTrue(failed.serverCallAttempted)
        XCTAssertFalse(failed.serverCallSucceeded)
        XCTAssertTrue(failed.tokenRemoved)
        XCTAssertTrue(failed.serverSessionMayRemain)
        XCTAssertEqual(failed.messageKey, .serverSessionMayRemain)
        XCTAssertNil(try vault.loadToken(serverID: serverID, userID: userID))

        let ok = RecordingAPIClient(error: nil)
        let succeeded = await CoreNetworking.SessionTermination.logOut(
            serverID: serverID, userID: otherUser, vault: vault, client: ok)
        XCTAssertTrue(succeeded.serverCallSucceeded)
        XCTAssertTrue(succeeded.tokenRemoved)
        XCTAssertNil(succeeded.userMessage)
        XCTAssertNil(succeeded.messageKey)
        XCTAssertEqual(try vault.loadToken(serverID: otherServer, userID: userID), "kept-token")

        try ServerDataRemoval.remove(serverID: serverID, vault: vault, pins: pins)
        XCTAssertNil(try pins.fingerprint(for: serverID))
        XCTAssertEqual(try pins.fingerprint(for: otherServer), fingerprint)
        XCTAssertEqual(try vault.loadToken(serverID: otherServer, userID: userID), "kept-token")
        try ServerDataRemoval.remove(serverID: otherServer, vault: vault, pins: pins)
        XCTAssertNil(try vault.loadToken(serverID: otherServer, userID: userID))
        XCTAssertNil(try pins.fingerprint(for: otherServer))
    }

    /// T03-27. Network, timeout, TLS, 5xx, and 403 keep the token. Only an authenticated 401 removes it.
    func testT03_27_onlyAuthenticated401EndsTheSession() throws {
        let failures: [APIError] = [
            .network, .timeout, .tls, .forbidden, .server(status: 500), .server(status: 502), .server(status: 503),
            .server(status: 504), .redirectRejected(.httpsDowngrade),
        ]
        for error in failures {
            let vault = try seededVault()
            let effect = try CoreNetworking.SessionTermination.apply(
                error: error, kind: .authenticated, serverID: serverID, userID: userID, vault: vault)
            XCTAssertEqual(effect, .keepToken)
            XCTAssertEqual(try vault.loadToken(serverID: serverID, userID: userID), token)
            XCTAssertFalse(LogoutPolicy.shouldLogOut(error))
        }
        let expired = try seededVault()
        XCTAssertEqual(
            try CoreNetworking.SessionTermination.apply(
                error: .unauthorized, kind: .authenticated, serverID: serverID, userID: userID, vault: expired),
            .endSession
        )
        XCTAssertNil(try expired.loadToken(serverID: serverID, userID: userID))

        let login = try seededVault()
        XCTAssertEqual(
            try CoreNetworking.SessionTermination.apply(
                error: .unauthorized, kind: .login, serverID: serverID, userID: userID, vault: login),
            .invalidCredentials
        )
        XCTAssertEqual(try login.loadToken(serverID: serverID, userID: userID), token)
    }

    private func seededVault() throws -> CredentialVault {
        let vault = CredentialVault(
            secureStore: AttributeSecureStore(), settings: InMemorySettingsStore(), accessGroup: accessGroup)
        try save(token, server: serverID, user: userID, vault: vault)
        return vault
    }

    private func save(_ token: String, server: String, user: String, vault: CredentialVault) throws {
        try vault.save(
            token: token,
            serverID: server,
            userID: user,
            profile: StoredSessionProfile(
                serverID: server, serverName: "Home", serverURL: "https://media.example", userID: user, userName: "Ada",
                isAdministrator: false)
        )
    }
}

final class SecurityCertificateTests: XCTestCase {
    private let serverID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    /// T03-01. Confirming fingerprint B while the connection presents C cancels. The pin store keeps A.
    func testT03_01_acceptedFingerprintMismatchOnChangeCancels() throws {
        let leafA = presentation(Data("leaf-a".utf8), subject: "CN=old")
        let leafB = presentation(Data("leaf-b".utf8), subject: "CN=accepted")
        let leafC = presentation(Data("leaf-c".utf8), subject: "CN=presented")
        let settings = InMemorySettingsStore()
        let store = SettingsCertificatePinStore(settings: settings)
        try store.save(fingerprint: leafA.sha256, serverID: serverID)

        let outcome = SelfSignedTrustFlow.handle(
            isSystemTrusted: false,
            leaf: leafC,
            pinnedSHA256: leafA.sha256,
            userAcceptedFingerprint: grouped(leafB.sha256, separator: ":")
        )
        guard case .cancelPinMismatch(let previous, let presented) = outcome.decision else {
            return XCTFail("Expected a pin mismatch")
        }
        XCTAssertEqual(previous, CertificateFingerprint.normalize(leafA.sha256))
        XCTAssertEqual(presented.sha256, leafC.sha256)
        XCTAssertNil(outcome.pinToStore)
        XCTAssertEqual(try store.fingerprint(for: serverID), CertificateFingerprint.normalize(leafA.sha256))
        let dump = settings.allValues().values.joined(separator: "\n")
        XCTAssertFalse(dump.contains(CertificateFingerprint.normalize(leafB.sha256)))
        XCTAssertFalse(dump.contains(CertificateFingerprint.normalize(leafC.sha256)))
    }

    /// T03-02. The same mismatch on first acceptance, with no prior pin, cancels and stores nothing.
    func testT03_02_firstAcceptanceMismatchCancels() throws {
        let leafB = presentation(Data("leaf-b".utf8), subject: "CN=accepted")
        let leafC = presentation(Data("leaf-c".utf8), subject: "CN=presented")
        let settings = InMemorySettingsStore()
        let store = SettingsCertificatePinStore(settings: settings)
        let outcome = SelfSignedTrustFlow.handle(
            isSystemTrusted: false,
            leaf: leafC,
            pinnedSHA256: nil,
            userAcceptedFingerprint: grouped(leafB.sha256, separator: " ")
        )
        XCTAssertEqual(outcome.decision, .cancelUntrusted)
        XCTAssertNil(outcome.pinToStore)
        XCTAssertNil(try store.fingerprint(for: serverID))
        XCTAssertTrue(settings.allValues().isEmpty)
    }

    /// T03-03. A confirmed fingerprint that matches the leaf is pinned. The next connection does not prompt.
    func testT03_03_matchingFingerprintIsPinnedAndReused() throws {
        let leaf = presentation(Data("leaf-a".utf8), subject: "CN=jellyfin")
        let hex = CertificateFingerprint.normalize(leaf.sha256)
        let colon = grouped(hex, separator: ":")
        let spaced = grouped(hex, separator: " ")
        let mixed = colon.replacingOccurrences(of: ":", with: ": ")
        for accepted in [colon, spaced, mixed, hex.uppercased()] {
            let outcome = SelfSignedTrustFlow.handle(
                isSystemTrusted: false, leaf: leaf, pinnedSHA256: nil, userAcceptedFingerprint: accepted)
            XCTAssertEqual(outcome.decision, .usePinnedCredential, accepted)
            XCTAssertEqual(outcome.pinToStore, hex, accepted)
        }
        let settings = InMemorySettingsStore()
        let store = SettingsCertificatePinStore(settings: settings)
        let first = SelfSignedTrustFlow.handle(
            isSystemTrusted: false, leaf: leaf, pinnedSHA256: nil, userAcceptedFingerprint: mixed)
        try store.save(fingerprint: try XCTUnwrap(first.pinToStore), serverID: serverID)
        XCTAssertEqual(try store.fingerprint(for: serverID), hex)

        let next = SelfSignedTrustFlow.handle(
            isSystemTrusted: false, leaf: leaf, pinnedSHA256: colon, userAcceptedFingerprint: nil)
        XCTAssertEqual(next.decision, .usePinnedCredential)
        XCTAssertNil(next.pinToStore)
        XCTAssertEqual(try store.fingerprint(for: serverID), hex)
    }

    /// T03-04. A pinned certificate that changes to D is blocked, and the dialog shows D's fingerprint.
    func testT03_04_changedCertificateShowsNewFingerprint() throws {
        let leafA = presentation(Data("leaf-a".utf8), subject: "CN=old")
        let leafD = presentation(Data("leaf-d".utf8), subject: "CN=new")
        let settings = InMemorySettingsStore()
        let store = SettingsCertificatePinStore(settings: settings)
        try store.save(fingerprint: grouped(leafA.sha256, separator: ":"), serverID: serverID)
        let outcome = SelfSignedTrustFlow.handle(
            isSystemTrusted: false,
            leaf: leafD,
            pinnedSHA256: try store.fingerprint(for: serverID),
            userAcceptedFingerprint: nil
        )
        guard case .cancelPinMismatch(let previous, let presented) = outcome.decision else {
            return XCTFail("Expected a pin mismatch")
        }
        XCTAssertEqual(previous, CertificateFingerprint.normalize(leafA.sha256))
        XCTAssertEqual(presented, leafD)
        XCTAssertEqual(presented.sha256, leafD.sha256)
        XCTAssertNil(outcome.pinToStore)
        XCTAssertEqual(try store.fingerprint(for: serverID), CertificateFingerprint.normalize(leafA.sha256))
        XCTAssertFalse(settings.allValues().values.joined().contains(CertificateFingerprint.normalize(leafD.sha256)))
    }

    /// T03-21. NIST SHA-256 vectors, and a system-trusted leaf is not pinned.
    func testT03_21_systemTrustedCertificateIsNotPinned() throws {
        XCTAssertEqual(
            CertificateFingerprint.sha256Hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            CertificateFingerprint.sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        let leaf = presentation(Data("leaf-b".utf8), subject: "CN=public")
        let trusted = SelfSignedTrustFlow.handle(
            isSystemTrusted: true,
            leaf: leaf,
            pinnedSHA256: nil,
            userAcceptedFingerprint: leaf.sha256
        )
        XCTAssertEqual(trusted.decision, .performDefaultHandling)
        XCTAssertNil(trusted.pinToStore)
    }

    private func presentation(_ data: Data, subject: String) -> CertificatePresentation {
        CertificatePresentation(
            sha256: CertificateFingerprint.sha256Hex(data),
            subject: subject,
            notBefore: Date(timeIntervalSince1970: 1_700_000_000),
            notAfter: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func grouped(_ hex: String, separator: Character) -> String {
        var pieces: [String] = []
        var current = ""
        for character in hex.uppercased() {
            current.append(character)
            if current.count == 2 {
                pieces.append(current)
                current = ""
            }
        }
        return pieces.joined(separator: String(separator))
    }
}

final class SecurityTransportTests: XCTestCase {
    /// T03-05. Public IPv4 HTTP is rejected before the transport is called.
    func testT03_05_publicIPv4HTTPIsRejectedBeforeAnyRequest() async throws {
        for host in ["203.0.113.5", "8.8.8.8"] {
            let url = try XCTUnwrap(URL(string: "http://\(host)/library"))
            XCTAssertEqual(ServerTransportPolicy.hostClass(host), .publicAddress, host)
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .publicHTTPRejected, host)
            XCTAssertEqual(
                ServerTransportPolicy.messageKey(for: .publicHTTPRejected),
                .publicAddressRequiresHTTPS
            )
            let transport = RecordingRequestTransport()
            let client = HTTPJellyfinClient(
                server: url,
                identity: ClientIdentity(
                    deviceName: "TV", deviceID: "device-1", version: "1.0.0", token: "secret-token"),
                transport: transport
            )
            do {
                _ = try await client.send(APIRequest(method: "GET", path: "/library"))
                XCTFail("Expected public HTTP to be rejected before the transport is called")
            } catch {
                XCTAssertEqual(error, .invalidURL, host)
            }
            XCTAssertEqual(transport.calls(), [], host)
        }
    }

    /// T03-06. Public IPv6 HTTP is rejected before any request is built.
    func testT03_06_publicIPv6HTTPIsRejectedBeforeAnyRequest() throws {
        for host in ["2001:db8::1", "2606:4700::1111"] {
            let url = try XCTUnwrap(URL(string: "http://[\(host)]/library"))
            XCTAssertEqual(url.host, host)
            XCTAssertEqual(ServerTransportPolicy.hostClass(host), .publicAddress, host)
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .publicHTTPRejected, host)
        }
    }

    /// T03-07. Private ranges, including the documented boundaries, stay on local HTTP.
    func testT03_07_privateAddressBoundariesAllowed() throws {
        let allowed = [
            "172.16.0.1", "172.31.255.254", "100.64.0.1", "100.127.255.254",
            "127.0.0.1", "10.255.255.255", "169.254.0.1", "192.168.0.1",
        ]
        for host in allowed {
            let url = try XCTUnwrap(URL(string: "http://\(host)/"))
            XCTAssertEqual(ServerTransportPolicy.hostClass(host), .privateAddress, host)
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .unencryptedLocal, host)
        }
        for host in ["::1", "fe80::1", "fd00::1", "fc00::1"] {
            let url = try XCTUnwrap(URL(string: "http://[\(host)]/"))
            XCTAssertEqual(url.host, host)
            XCTAssertEqual(ServerTransportPolicy.hostClass(host), .privateAddress, host)
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .unencryptedLocal, host)
        }
    }

    /// T03-08. Addresses just outside the private ranges are public. IPv4-mapped literals use the IPv4 rules.
    func testT03_08_addressesJustOutsidePrivateRangesRejected() throws {
        let rejected = ["172.15.255.255", "172.32.0.1", "100.63.255.255", "100.128.0.1", "192.169.1.1"]
        for host in rejected {
            let url = try XCTUnwrap(URL(string: "http://\(host)/"))
            XCTAssertEqual(ServerTransportPolicy.hostClass(host), .publicAddress, host)
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .publicHTTPRejected, host)
        }
        let mappedPublic = "::ffff:8.8.8.8"
        let mappedPrivate = "::ffff:192.168.1.1"
        let publicURL = try XCTUnwrap(URL(string: "http://[\(mappedPublic)]/"))
        let privateURL = try XCTUnwrap(URL(string: "http://[\(mappedPrivate)]/"))
        XCTAssertEqual(publicURL.host, mappedPublic)
        XCTAssertEqual(privateURL.host, mappedPrivate)
        XCTAssertEqual(ServerTransportPolicy.hostClass(mappedPublic), .publicAddress)
        XCTAssertEqual(ServerTransportPolicy.evaluate(publicURL), .publicHTTPRejected)
        XCTAssertEqual(ServerTransportPolicy.hostClass(mappedPrivate), .privateAddress)
        XCTAssertEqual(ServerTransportPolicy.evaluate(privateURL), .unencryptedLocal)
    }

    /// T03-09. inet_aton shorthands are rejected. The class is the literal host, with no DNS lookup.
    func testT03_09_nonCanonicalNumericHostsAreRejected() throws {
        let rejected = [
            "0x7f000001", "2130706433", "017700000001", "134744072", "0x08080808",
            "127.1", "010.0.0.1", "0x7f.1", "0177.0.0.1",
        ]
        for host in rejected {
            let url = try XCTUnwrap(URL(string: "http://\(host)/"))
            XCTAssertEqual(url.host, host, host)
            XCTAssertEqual(ServerTransportPolicy.hostClass(host), .publicAddress, host)
            XCTAssertNotEqual(ServerTransportPolicy.hostClass(host), .localHostname, host)
            XCTAssertNotEqual(ServerTransportPolicy.hostClass(host), .privateAddress, host)
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .publicHTTPRejected, host)
        }
        XCTAssertEqual(ServerTransportPolicy.hostClass("nas"), .localHostname)
        XCTAssertEqual(ServerTransportPolicy.hostClass("cafe"), .localHostname)
        let bareHex = "7f000001"
        XCTAssertEqual(ServerTransportPolicy.hostClass(bareHex), .localHostname)
        XCTAssertEqual(
            ServerTransportPolicy.evaluate(try XCTUnwrap(URL(string: "http://\(bareHex)/"))),
            .unencryptedLocal
        )
        let rebound = "192.168.1.1.nip.io"
        XCTAssertEqual(ServerTransportPolicy.hostClass(rebound), .publicHostname)
        XCTAssertNotEqual(ServerTransportPolicy.hostClass(rebound), .privateAddress)
        XCTAssertEqual(
            ServerTransportPolicy.evaluate(try XCTUnwrap(URL(string: "http://\(rebound)/"))),
            .publicHTTPRejected
        )
    }

    /// T03-28. Testaaja T03-11. Only a canonical four-octet IPv4 literal is accepted.
    func testT03_28_nonCanonicalIPv4LiteralsAreRejected() throws {
        let rejected = [
            "134744072", "0x08080808", "0177.0.0.1", "010.0.0.1", "127.1", "127.0.1", "0x7f.1",
            "192.168.1.1.", "192.168.001.010",
        ]
        for host in rejected {
            let url = try XCTUnwrap(URL(string: "http://\(host)/"))
            XCTAssertEqual(url.host, host, host)
            XCTAssertEqual(ServerTransportPolicy.hostClass(host), .publicAddress, host)
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .publicHTTPRejected, host)
        }
    }

    /// T03-29. Testaaja T03-12. Only IPv4-mapped addresses use the embedded IPv4 rules.
    func testT03_29_embeddedIPv4AndZoneID() throws {
        let mappedLocal = try XCTUnwrap(URL(string: "http://[::ffff:7f00:1]/"))
        XCTAssertEqual(mappedLocal.host, "::ffff:7f00:1")
        XCTAssertEqual(ServerTransportPolicy.hostClass("::ffff:7f00:1"), .privateAddress)
        XCTAssertEqual(ServerTransportPolicy.evaluate(mappedLocal), .unencryptedLocal)

        let mappedPublic = try XCTUnwrap(URL(string: "http://[::ffff:808:808]/"))
        XCTAssertEqual(mappedPublic.host, "::ffff:808:808")
        XCTAssertEqual(ServerTransportPolicy.hostClass("::ffff:808:808"), .publicAddress)
        XCTAssertEqual(ServerTransportPolicy.evaluate(mappedPublic), .publicHTTPRejected)

        let compatible = try XCTUnwrap(URL(string: "http://[::192.168.1.1]/"))
        XCTAssertEqual(compatible.host, "::192.168.1.1")
        XCTAssertEqual(ServerTransportPolicy.hostClass("::192.168.1.1"), .publicAddress)
        XCTAssertEqual(ServerTransportPolicy.evaluate(compatible), .publicHTTPRejected)

        for host in ["64:ff9b::808:808", "64:ff9b::c0a8:101"] {
            let url = try XCTUnwrap(URL(string: "http://[\(host)]/"))
            XCTAssertEqual(url.host, host, host)
            XCTAssertEqual(ServerTransportPolicy.hostClass(host), .publicAddress, host)
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .publicHTTPRejected, host)
        }

        let zoned = try XCTUnwrap(URL(string: "http://[fe80::1%25en0]/"))
        XCTAssertEqual(zoned.host, "fe80::1%en0")
        XCTAssertEqual(ServerTransportPolicy.hostClass("fe80::1%en0"), .privateAddress)
        XCTAssertEqual(ServerTransportPolicy.hostClass("fe80::1%25en0"), .privateAddress)
        XCTAssertEqual(ServerTransportPolicy.evaluate(zoned), .unencryptedLocal)
    }

    /// T03-20. App plists allow local networking and do not allow arbitrary loads.
    func testT03_20_appTransportSecurityDoesNotAllowArbitraryLoads() throws {
        let arbitraryLoads = "NSAllows" + "ArbitraryLoads"
        let root = repoRoot()
        for platform in ["tvOS", "iOS"] {
            let url = root.appendingPathComponent("Apps/\(platform)/Info.plist")
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.contains(arbitraryLoads), platform)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let ats = try XCTUnwrap(plist["NSAppTransportSecurity"] as? [String: Any])
            XCTAssertEqual(ats["NSAllowsLocalNetworking"] as? Bool, true, platform)
            XCTAssertNil(ats[arbitraryLoads], platform)
        }
        let topShelf = try Data(contentsOf: root.appendingPathComponent("Apps/TopShelf/Info.plist"))
        XCTAssertFalse(String(decoding: topShelf, as: UTF8.self).contains(arbitraryLoads))
    }

    /// T03-25. The keychain access group is only on the app and Top Shelf entitlements.
    func testT03_25_keychainAccessGroupIsLimitedToAppAndTopShelf() throws {
        let root = repoRoot()
        let allowed: Set<String> = [
            "Apps/tvOS/Glassfin.entitlements",
            "Apps/iOS/Glassfin.entitlements",
            "Apps/TopShelf/TopShelf.entitlements",
        ]
        var saw: Set<String> = []
        for relative in entitlements(under: root) {
            let url = root.appendingPathComponent(relative)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
            guard plist["keychain-access-groups"] != nil else { continue }
            XCTAssertTrue(allowed.contains(relative), relative)
            let groups = try XCTUnwrap(plist["keychain-access-groups"] as? [String])
            XCTAssertEqual(groups, ["$(AppIdentifierPrefix)org.glassfin.app"])
            saw.insert(relative)
        }
        XCTAssertEqual(saw, allowed)
    }

    /// T03-13. Public HTTP is rejected. Local HTTP is allowed and marked unencrypted. Userinfo is rejected.
    func testT03_13_publicHTTPIsRejectedAndLocalHTTPIsMarked() throws {
        let publicHTTP = try XCTUnwrap(URL(string: "http://jellyfin.example.com"))
        XCTAssertEqual(ServerTransportPolicy.evaluate(publicHTTP), .publicHTTPRejected)
        XCTAssertEqual(
            ServerTransportPolicy.messageKey(for: .publicHTTPRejected),
            .publicAddressRequiresHTTPS
        )
        XCTAssertFalse(ServerTransportPolicy.showsUnencryptedMark(publicHTTP))

        let lan = try XCTUnwrap(URL(string: "http://192.168.0.2:8096"))
        XCTAssertEqual(ServerTransportPolicy.evaluate(lan), .unencryptedLocal)
        XCTAssertEqual(
            ServerTransportPolicy.messageKey(for: ServerTransportPolicy.evaluate(lan)), .connectionNotEncrypted)
        XCTAssertTrue(ServerTransportPolicy.badge(for: lan).showsUnencryptedMark)
        XCTAssertEqual(
            ServerTransportPolicy.evaluate(try XCTUnwrap(URL(string: "http://jellyfin.local"))), .unencryptedLocal)
        XCTAssertEqual(ServerTransportPolicy.evaluate(try XCTUnwrap(URL(string: "http://nas"))), .unencryptedLocal)
        XCTAssertEqual(
            ServerTransportPolicy.evaluate(try XCTUnwrap(URL(string: "http://[fe80::1]:8096"))), .unencryptedLocal)
        XCTAssertEqual(
            ServerTransportPolicy.evaluate(try XCTUnwrap(URL(string: "https://jellyfin.example.com"))), .secure)
        XCTAssertEqual(
            ServerTransportPolicy.evaluate(try XCTUnwrap(URL(string: "ftp://jellyfin.example.com"))), .invalid)

        XCTAssertThrowsError(try ServerAddress.canonical(XCTUnwrap(URL(string: "https://user:secret@example.com"))))
        let canonical = try ServerAddress.canonical(
            XCTUnwrap(URL(string: "https://media.example/jellyfin/../jellyfin/./web?ApiKey=sekret&x=1#frag"))
        )
        XCTAssertNil(canonical.user)
        XCTAssertNil(canonical.password)
        XCTAssertEqual(canonical.host, "media.example")
        XCTAssertEqual(canonical.path, "/jellyfin/web")
        XCTAssertNil(canonical.fragment)
        XCTAssertFalse(canonical.absoluteString.contains("sekret"))
        XCTAssertFalse(canonical.absoluteString.contains("secret"))
        XCTAssertNil(canonical.query)
        XCTAssertThrowsError(try ServerAddress.canonical(XCTUnwrap(URL(string: "ftp://media.example/jellyfin"))))
    }

    func testTransportMessageKeysCoverEveryVerdict() throws {
        let cases: [(String, ServerTransportPolicy.Verdict, AuthCopy.Key?)] = [
            ("https://jellyfin.example.com", .secure, nil),
            ("http://192.168.0.2:8096", .unencryptedLocal, .connectionNotEncrypted),
            ("http://jellyfin.example.com", .publicHTTPRejected, .publicAddressRequiresHTTPS),
            ("ftp://jellyfin.example.com", .invalid, nil),
        ]
        for (address, verdict, expectedKey) in cases {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(ServerTransportPolicy.messageKey(for: verdict), expectedKey, address)
            XCTAssertEqual(ServerTransportPolicy.message(for: verdict) == nil, expectedKey == nil, address)
            let badge = ServerTransportPolicy.badge(for: url)
            XCTAssertEqual(badge.messageKey, expectedKey, address)
            XCTAssertEqual(badge.message == nil, expectedKey == nil, address)
        }
    }

    private func entitlements(under root: URL) -> [String] {
        var found: [String] = []
        for folder in ["Apps", "Packages"] {
            let base = root.appendingPathComponent(folder)
            guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "entitlements" {
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                found.append(relative)
            }
        }
        return found
    }
}

final class SecurityRedirectAndMediaTests: XCTestCase {
    /// T03-23. Cross-host drops Authorization, HTTPS to HTTP fails, same-host works, and the sixth hop stops.
    func testT03_23_redirectBudgetAndOriginRules() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://media.example/a"))
        var original = URLRequest(url: originalURL)
        original.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")

        var cross = URLRequest(url: try XCTUnwrap(URL(string: "https://other.example/a")))
        cross.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        guard
            case .follow(let stripped) = RedirectFollowLimit.decide(
                followed: 0, seen: [originalURL], original: original, proposed: cross)
        else { return XCTFail("Expected a stripped follow") }
        XCTAssertNil(stripped.value(forHTTPHeaderField: "Authorization"))

        var downgrade = URLRequest(url: try XCTUnwrap(URL(string: "http://media.example/a")))
        downgrade.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        XCTAssertEqual(
            RedirectFollowLimit.decide(followed: 0, seen: [originalURL], original: original, proposed: downgrade),
            .reject(.httpsDowngrade)
        )

        var seen = [originalURL]
        var followed = 0
        for index in 1...5 {
            let next = try XCTUnwrap(URL(string: "https://media.example/p\(index)"))
            var proposed = URLRequest(url: next)
            proposed.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
            guard
                case .follow(let kept) = RedirectFollowLimit.decide(
                    followed: followed, seen: seen, original: original, proposed: proposed)
            else { return XCTFail("Hop \(index) should follow") }
            XCTAssertNotNil(kept.value(forHTTPHeaderField: "Authorization"))
            followed += 1
            seen.append(next)
        }
        var sixth = URLRequest(url: try XCTUnwrap(URL(string: "https://media.example/p6")))
        sixth.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        XCTAssertEqual(
            RedirectFollowLimit.decide(followed: followed, seen: seen, original: original, proposed: sixth),
            .reject(.notFollowed)
        )
        let loop = URLRequest(url: originalURL)
        XCTAssertEqual(
            RedirectFollowLimit.decide(followed: 1, seen: seen, original: original, proposed: loop),
            .reject(.notFollowed)
        )
        XCTAssertEqual(RedirectFollowLimit.maximum, 5)

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let delegate = RedirectSessionDelegate()
        let privateURL = try XCTUnwrap(URL(string: "http://192.168.1.10/a"))
        let publicURL = try XCTUnwrap(URL(string: "http://203.0.113.5/a"))
        let taskA = session.dataTask(with: privateURL)
        let taskB = session.dataTask(with: try XCTUnwrap(URL(string: "https://media.example/a")))
        let response = try XCTUnwrap(
            HTTPURLResponse(url: privateURL, statusCode: 302, httpVersion: nil, headerFields: nil))
        var proposedA = URLRequest(url: publicURL)
        proposedA.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        var proposedB = URLRequest(url: try XCTUnwrap(URL(string: "http://media.example/a")))
        proposedB.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        delegate.urlSession(
            session, task: taskA, willPerformHTTPRedirection: response, newRequest: proposedA
        ) { request in
            XCTAssertNil(request)
        }
        delegate.urlSession(
            session, task: taskB, willPerformHTTPRedirection: response, newRequest: proposedB
        ) { request in
            XCTAssertNil(request)
        }
        delegate.urlSession(session, task: taskA, didCompleteWithError: nil)
        XCTAssertEqual(delegate.consumeRejection(for: taskA.taskIdentifier), .notFollowed)
        XCTAssertEqual(delegate.consumeRejection(for: taskB.taskIdentifier), .httpsDowngrade)
        XCTAssertNil(delegate.consumeRejection(for: taskA.taskIdentifier))
        XCTAssertNotEqual(taskA.taskIdentifier, taskB.taskIdentifier)
    }

    /// T03-10. A redirect from private HTTP onto public HTTP is not followed, and Authorization is not sent.
    func testT03_10_redirectFromPrivateToPublicHTTPIsRejected() throws {
        let originalURL = try XCTUnwrap(URL(string: "http://192.168.1.10/Items"))
        var original = URLRequest(url: originalURL)
        original.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        let target = try XCTUnwrap(URL(string: "http://8.8.8.8/Items"))
        var proposed = URLRequest(url: target)
        proposed.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        XCTAssertEqual(RedirectPolicy.apply(original: original, proposed: proposed), .reject(.notFollowed))
        XCTAssertNil(PlayerMediaHandoff.urlForPlayer(start: originalURL, hops: [target]))

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: original)
        let response = try XCTUnwrap(
            HTTPURLResponse(url: originalURL, statusCode: 302, httpVersion: nil, headerFields: nil))
        let delegate = RedirectSessionDelegate()
        var followed: URLRequest? = proposed
        delegate.urlSession(
            session, task: task, willPerformHTTPRedirection: response, newRequest: proposed
        ) { followed = $0 }
        XCTAssertNil(followed)
        XCTAssertEqual(delegate.consumeRejection(for: task.taskIdentifier), .notFollowed)
    }

    /// T03-11. An ApiKey URL is not followed off-origin, and AVPlayer only receives the resolved URL.
    func testT03_11_apiKeyRedirectsAndResolvedPlayerURL() throws {
        let token = "media-token-value"
        let start = try XCTUnwrap(URL(string: "https://media.example/Videos/id/stream?ApiKey=\(token)"))
        let same = try XCTUnwrap(URL(string: "https://media.example/Videos/id/final?ApiKey=\(token)"))
        let cross = try XCTUnwrap(URL(string: "https://cdn.example/Videos/id/final?ApiKey=\(token)"))
        let down = try XCTUnwrap(URL(string: "http://media.example/Videos/id/final?ApiKey=\(token)"))
        XCTAssertEqual(MediaURLSecurity.resolve(start: start, hops: [same]), .playable(same))
        XCTAssertEqual(MediaURLSecurity.resolve(start: start, hops: [cross]), .rejected(.credentialQueryCrossHost))
        XCTAssertEqual(MediaURLSecurity.resolve(start: start, hops: [down]), .rejected(.credentialQueryDowngrade))
        XCTAssertEqual(PlayerMediaHandoff.urlForPlayer(start: start, hops: [same]), same)
        XCTAssertNil(PlayerMediaHandoff.urlForPlayer(start: start, hops: [cross]))
        XCTAssertNil(PlayerMediaHandoff.urlForPlayer(start: start, hops: [down]))

        let plain = try XCTUnwrap(URL(string: "https://media.example/Videos/id/stream"))
        let otherHost = try XCTUnwrap(URL(string: "https://cdn.example/Videos/id/stream"))
        XCTAssertEqual(MediaURLSecurity.resolve(start: plain, hops: [otherHost]), .rejected(.notFollowed))
        XCTAssertNil(PlayerMediaHandoff.urlForPlayer(start: plain, hops: [otherHost]))

        var hops: [URL] = []
        for index in 1...6 {
            hops.append(try XCTUnwrap(URL(string: "https://media.example/h\(index)?ApiKey=\(token)")))
        }
        XCTAssertEqual(MediaURLSecurity.resolve(start: start, hops: Array(hops.prefix(5))), .playable(hops[4]))
        XCTAssertEqual(MediaURLSecurity.resolve(start: start, hops: hops), .rejected(.notFollowed))

        XCTAssertEqual(MediaProbeMethod.directPlay.httpMethod, "HEAD")
        XCTAssertEqual(MediaProbeMethod.hlsMaster.httpMethod, "GET")
        let prepared = PreparedMediaRequest(url: same, authorizationHeader: nil, usesAPIKeyQuery: true)
        XCTAssertFalse(String(describing: prepared).contains(token))
    }
}

final class SecurityDiscoveryTests: XCTestCase {
    /// T03-24. A forged discovery packet is shown and never connects or rewrites a stored address.
    func testT03_24_forgedDiscoveryDoesNotAutoConnect() throws {
        let stored = try XCTUnwrap(URL(string: "http://192.168.1.9:8096"))
        let name = "<script>alert(1)</script><b>" + String(repeating: "N", count: 80) + "</b>\n"
        let rejected = try JSONSerialization.data(withJSONObject: [
            "Address": "http://user:pass@192.168.1.50:8096/jellyfin"
        ])
        XCTAssertNil(DiscoveryPolicy.parse(rejected, storedURL: stored, publicInfoID: nil))
        let packet = try JSONSerialization.data(withJSONObject: [
            "Address": "http://192.168.1.50:8096/jellyfin",
            "Id": "discovered-id",
            "Name": name,
        ])
        let presentation = try XCTUnwrap(
            DiscoveryPolicy.parse(packet, storedURL: stored, publicInfoID: "real-server-id"))
        XCTAssertEqual(presentation.url.host, "192.168.1.50")
        XCTAssertEqual(presentation.port, 8096)
        XCTAssertEqual(presentation.url.path, "/jellyfin")
        XCTAssertNil(presentation.url.user)
        XCTAssertFalse(presentation.autoConnect)
        XCTAssertTrue(presentation.idMismatch)
        XCTAssertEqual(presentation.storedURL, stored)
        XCTAssertEqual(DiscoveryPolicy.storedAddress(afterDiscovery: stored, packet: packet), stored)
        XCTAssertTrue(presentation.name.contains("<"))
        XCTAssertTrue(presentation.name.contains("alert"))
        XCTAssertFalse(presentation.name.contains("\n"))
        XCTAssertEqual(presentation.name.count, 64)
        XCTAssertEqual(presentation.id, "discovered-id")

        let matched = try XCTUnwrap(DiscoveryPolicy.parse(packet, storedURL: nil, publicInfoID: "discovered-id"))
        XCTAssertFalse(matched.idMismatch)
        XCTAssertFalse(matched.autoConnect)
        XCTAssertNil(matched.storedURL)

        let https = try JSONSerialization.data(withJSONObject: [
            "Address": "https://jellyfin.local/jellyfin",
            "Id": "id-1",
            "Name": "Local",
        ])
        let secure = try XCTUnwrap(DiscoveryPolicy.parse(https, storedURL: stored, publicInfoID: nil))
        XCTAssertEqual(secure.port, 443)
        XCTAssertEqual(secure.host, "jellyfin.local")
        XCTAssertEqual(secure.transport, .secure)
        XCTAssertFalse(secure.autoConnect)
        XCTAssertEqual(secure.storedURL, stored)

        let implicit = try JSONSerialization.data(withJSONObject: [
            "Address": "http://nas", "Id": "id-2", "Name": "NAS",
        ])
        let nas = try XCTUnwrap(DiscoveryPolicy.parse(implicit, storedURL: nil, publicInfoID: nil))
        XCTAssertEqual(nas.port, 80)
        XCTAssertEqual(nas.transport, .unencryptedLocal)
        XCTAssertNil(DiscoveryPolicy.parse(Data("nope".utf8), storedURL: nil, publicInfoID: nil))
        XCTAssertNil(
            DiscoveryPolicy.parse(Data("{\"Address\":\"ftp://192.168.1.2\"}".utf8), storedURL: nil, publicInfoID: nil))

        let spoofed = "\u{202E}Room\u{202C}\u{2066}TV\u{2069}"
        XCTAssertEqual(DiscoveryPolicy.displayName(spoofed), "RoomTV")
        XCTAssertFalse(
            DiscoveryPolicy.displayName(spoofed).unicodeScalars.contains {
                (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
            })
    }
}

final class SecurityHeaderAndLogTests: XCTestCase {
    /// T03-26. Quotes, comma, equals, plus, space, emoji, and non-ASCII letters round-trip. One Authorization header leaves.
    func testT03_26_headerEncodingRejectionAndSingleAuthorization() throws {
        let device = "Room + \"TV\", ää=ö 📺"
        let header = try AuthorizationHeader.value(
            client: "Glassfin", device: device, deviceID: "device-1", version: "1.0.0", token: "tok+en")
        let parts = AuthorizationHeaderParts.parse(header)
        XCTAssertEqual(parts["Device"], device)
        XCTAssertEqual(parts["Client"], "Glassfin")
        XCTAssertEqual(parts["Token"], "tok+en")
        XCTAssertTrue(header.contains("%2B"))
        XCTAssertTrue(header.contains("%20"))
        XCTAssertTrue(header.contains("%22"))
        XCTAssertTrue(header.contains("%2C"))
        XCTAssertTrue(header.contains("%3D"))
        XCTAssertTrue(header.contains("%C3%A4"))
        XCTAssertTrue(header.contains("%C3%B6"))
        XCTAssertTrue(header.contains("%F0%9F%93%BA"))
        XCTAssertFalse(header.contains("📺"))
        XCTAssertFalse(header.contains("ää"))

        let fallback = try SafeAuthorizationHeader.value(
            client: "Glassfin", device: "Living\r\nRoom", deviceID: "device-1", version: "1", token: nil)
        XCTAssertTrue(fallback.contains("Device=\"Apple%20TV\""))
        XCTAssertFalse(fallback.contains("\n"))
        XCTAssertThrowsError(
            try SafeAuthorizationHeader.value(
                client: "Glassfin", device: "Apple TV", deviceID: "id\u{0001}", version: "1", token: "abc")
        ) { error in
            XCTAssertEqual(error as? SecurityInvariantError, .internalInvariant)
        }
        XCTAssertThrowsError(
            try SafeAuthorizationHeader.value(
                client: "Glassfin", device: "Apple TV", deviceID: "device-1", version: "1", token: "ab\ncd")
        ) { error in
            XCTAssertEqual(error as? SecurityInvariantError, .internalInvariant)
        }

        let client = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://media.example")),
            identity: ClientIdentity(deviceName: "Living\nRoom", deviceID: "device-1", version: "1.0", token: "abc")
        )
        let request = try client.makeURLRequest(APIRequest(method: "GET", path: "/System/Ping"))
        let fields = request.allHTTPHeaderFields ?? [:]
        let authKeys = fields.keys.filter { $0.compare("Authorization", options: .caseInsensitive) == .orderedSame }
        XCTAssertEqual(authKeys.count, 1)
        let authorization = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authorization.contains("Device=\"Apple%20TV\""))
        XCTAssertFalse(authorization.contains("\n"))

        var replaced = URLRequest(url: try XCTUnwrap(URL(string: "https://media.example/Items")))
        replaced.addValue("MediaBrowser Token=raw", forHTTPHeaderField: "Authorization")
        AuthorizationHeaderWriter.replace(authorization, on: &replaced)
        XCTAssertEqual(replaced.value(forHTTPHeaderField: "Authorization"), authorization)
        XCTAssertFalse(replaced.value(forHTTPHeaderField: "Authorization")?.contains("Token=raw") == true)

        let badToken = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://media.example")),
            identity: ClientIdentity(deviceName: "Apple TV", deviceID: "device-1", version: "1", token: "ab\n")
        )
        XCTAssertThrowsError(try badToken.makeURLRequest(APIRequest(method: "GET", path: "/Users/Me"))) { error in
            XCTAssertEqual(error as? APIError, .headerRejected)
        }
    }

    /// T03-22. Every forbidden field is redacted, including a media URL.
    func testT03_22_loggerRedactsEveryForbiddenField() {
        let secret = "planted-token-value"
        let legacy = "api" + "_key"
        let samples = [
            "https://media.example/stream?ApiKey=\(secret)",
            "https://media.example/stream?\(legacy)=\(secret)",
            "https://media.example/stream?APIKEY=\(secret)",
            "https://media.example/stream?Token=\(secret)",
            "https://media.example/stream?secret=\(secret)",
            "https://media.example/stream?Pw=\(secret)",
            "Authorization: MediaBrowser Token=\"\(secret)\"",
            "{\"Pw\":\"\(secret)\",\"Token\":\"\(secret)\",\"secret\":\"\(secret)\"}",
        ]
        for sample in samples {
            let redacted = SensitiveRedactor.redact(sample)
            XCTAssertFalse(redacted.contains(secret), sample)
            XCTAssertTrue(redacted.contains("REDACTED"), sample)
            GlassfinLogger().warning(sample)
            GlassfinLogger().error(sample)
            GlassfinLogger().debug(sample)
        }
        GlassfinLogger().infoPublic("Glassfin 12.2.0")
    }
}

final class SecurityContentTests: XCTestCase {
    /// T03-14. Metadata is plain text, external links follow the platform rule, and search stays in the query.
    func testT03_14_plainTextLinksSubtitlesAndSearch() throws {
        let raw = "<script>alert(1)</script><b>Hello</b> Tom &amp; Jerry **bold** [x](http://e.test)"
        XCTAssertEqual(MetadataSanitizer.plainText(raw), raw)
        XCTAssertEqual(MetadataSanitizer.plainText("a < b"), "a < b")
        let dto = try JSONDecoder().decode(
            BaseItemDTO.self,
            from: Data(
                """
                {"Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Name":"<b>North</b>","Type":"Movie","Overview":"<p>A quiet film.</p>"}
                """.utf8
            )
        )
        let item = try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
        XCTAssertEqual(item.name, "<b>North</b>")
        XCTAssertEqual(item.overview, "<p>A quiet film.</p>")

        XCTAssertFalse(ExternalLinkPolicy.canOpen(try XCTUnwrap(URL(string: "https://example.com")), on: .tvOS))
        XCTAssertFalse(ExternalLinkPolicy.canOpen(try XCTUnwrap(URL(string: "http://example.com")), on: .tvOS))
        XCTAssertTrue(ExternalLinkPolicy.canOpen(try XCTUnwrap(URL(string: "https://example.com")), on: .iOS))
        XCTAssertTrue(ExternalLinkPolicy.canOpen(try XCTUnwrap(URL(string: "http://example.com/a")), on: .iOS))
        XCTAssertFalse(ExternalLinkPolicy.canOpen(try XCTUnwrap(URL(string: "javascript:alert(1)")), on: .iOS))
        XCTAssertFalse(ExternalLinkPolicy.canOpen(try XCTUnwrap(URL(string: "file:///etc/passwd")), on: .iOS))

        XCTAssertTrue(SubtitleFilePolicy.accept(byteCount: SubtitleFilePolicy.maxBytes, exceededDeadline: false))
        XCTAssertFalse(SubtitleFilePolicy.accept(byteCount: SubtitleFilePolicy.maxBytes + 1, exceededDeadline: false))
        XCTAssertFalse(SubtitleFilePolicy.accept(byteCount: 10, exceededDeadline: true))
        XCTAssertEqual(SubtitleFilePolicy.maxBytes, 10 * 1_024 * 1_024)

        let term = "../Admin?ApiKey=nope"
        let request = QueryTransport.searchHints(term: term, limit: 5)
        XCTAssertEqual(request.path, "/Search/Hints")
        XCTAssertFalse(request.path.contains(term))
        XCTAssertEqual(request.query.first?.value, term)
        let url = try HTTPJellyfinClient.url(
            server: XCTUnwrap(URL(string: "https://media.example/jellyfin")),
            path: request.path,
            query: request.query
        )
        XCTAssertTrue(url.path.hasSuffix("/Search/Hints"))
        XCTAssertFalse(url.path.contains("Admin"))
        XCTAssertTrue(url.query?.contains("searchTerm") == true)
    }

    /// T03-15. Admin UI follows IsAdministrator, and destructive dialogs default to cancel.
    func testT03_15_adminGateDefaultsToCancel() {
        XCTAssertTrue(AdminGate.showAdmin(isAdministrator: true))
        XCTAssertFalse(AdminGate.showAdmin(isAdministrator: false))
        for action in [DestructiveAdminAction.restartServer, .deleteUser, .deleteDevice] {
            XCTAssertTrue(DestructiveConfirmation.dialog(for: action).defaultFocusIsCancel)
            XCTAssertEqual(DestructiveConfirmation.dialog(for: action).action, action)
        }
    }

    /// T03-16. Download protection has a floor, and a GPL native build is not allowed.
    func testT03_16_downloadProtectionFloor() {
        XCTAssertEqual(
            DownloadProtection.minimumFileProtection, "NSFileProtectionCompleteUntilFirstUserAuthentication")
        XCTAssertTrue(DownloadProtection.excludeFromBackup)
        XCTAssertFalse(NativeMediaLibraryPolicy.gplBuildAllowed)
        XCTAssertEqual(NativeMediaLibraryPolicy.securityUpdateWindowDays, 14)
    }

    /// T03-12. The secret is not logged. Polling is every 5 seconds and stops at 5 minutes or on cancel.
    func testT03_12_quickConnectSecretIsNotLogged() async {
        let secretValue = "qc-secret-value"
        let secret = QuickConnectSecret(secretValue)
        XCTAssertFalse(String(describing: secret).contains(secretValue))
        XCTAssertFalse(String(reflecting: secret).contains(secretValue))
        XCTAssertEqual(QuickConnectSecurity.pollInterval, .seconds(5))
        XCTAssertEqual(QuickConnectSecurity.timeout, .seconds(300))

        let log = CapturingLog()
        let clock = ManualClock()
        let counter = PollCounter()
        let outcome = await QuickConnectMonitor(clock: clock).run(secret: secret, code: "123456", log: log) {
            revealed in
            _ = await counter.bump(revealed)
            return .pending
        }
        XCTAssertEqual(outcome, .expired)
        let polls = await counter.current()
        XCTAssertEqual(polls, 60)
        XCTAssertEqual(clock.sleeps.count, 60)
        XCTAssertTrue(clock.sleeps.allSatisfy { $0 == .seconds(5) })
        XCTAssertFalse(log.lines.isEmpty)
        for line in log.lines {
            XCTAssertFalse(line.contains(secretValue))
            XCTAssertTrue(line.contains("123456"))
        }
        let early = PollCounter()
        let authenticated = await QuickConnectMonitor(clock: ManualClock()).run(
            secret: secret, code: "123456", log: CapturingLog()
        ) { revealed in
            let count = await early.bump(revealed)
            return count == 2 ? .authenticated : .pending
        }
        XCTAssertEqual(authenticated, .authenticated)
        let earlyPolls = await early.current()
        XCTAssertEqual(earlyPolls, 2)

        let blocking = PollCounter()
        let task = Task {
            await QuickConnectMonitor(clock: ManualClock()).run(
                secret: secret, code: "123456", log: CapturingLog()
            ) { revealed in
                let count = await blocking.bump(revealed)
                if count >= 2 {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(20))
                    }
                }
                return .pending
            }
        }
        await waitUntil { await blocking.count >= 2 }
        task.cancel()
        let cancelled = await task.value
        XCTAssertEqual(cancelled, .cancelled)
        let blockedPolls = await blocking.current()
        XCTAssertLessThan(blockedPolls, 10)
    }

    private func waitUntil(timeoutSeconds: Double = 2, _ predicate: () async -> Bool) async {
        let clock = ContinuousClock()
        let start = clock.now
        while await !predicate() {
            if start.duration(to: .now) > .seconds(timeoutSeconds) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class AttributeSecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var written: [String: KeychainAttributes] = [:]

    func data(for account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func set(_ data: Data, account: String, attributes: KeychainAttributes) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = data
        written[account] = attributes
    }

    func remove(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = nil
    }

    func attributes(for account: String) -> KeychainAttributes? {
        lock.lock()
        defer { lock.unlock() }
        return written[account]
    }
}

private final class RecordingRequestTransport: RequestTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    func data(for request: URLRequest, maximumBytes: Int?) async throws -> (Data, URLResponse, Int?) {
        record(request)
        guard let url = request.url ?? URL(string: "http://invalid.example/"),
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw URLError(.badURL)
        }
        return (Data(), response, nil)
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        stored.append(request)
        lock.unlock()
    }

    func calls() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private final class RecordingAPIClient: JellyfinAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [APIRequest] = []
    private let error: APIError?

    init(error: APIError?) {
        self.error = error
    }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        record(request)
        if let error { throw error }
        return Data()
    }

    private func record(_ request: APIRequest) {
        lock.lock()
        stored.append(request)
        lock.unlock()
    }

    func calls() -> [APIRequest] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private final class CapturingLog: GlassfinLog, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func warning(_ message: String) { append(message) }
    func debug(_ message: String) { append(message) }
    func error(_ message: String) { append(message) }

    private func append(_ message: String) {
        lock.lock()
        stored.append(message)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private final class ManualClock: GlassfinClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration
    private var recorded: [Duration] = []

    init(_ now: Duration = .zero) {
        current = now
    }

    func now() -> Duration {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    var sleeps: [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func sleep(for duration: Duration) async throws {
        advance(duration)
    }

    private func advance(_ duration: Duration) {
        lock.lock()
        current += duration
        recorded.append(duration)
        lock.unlock()
    }
}

private actor PollCounter {
    private(set) var count = 0

    func bump(_ value: String) -> Int {
        count += 1
        _ = value
        return count
    }

    func current() -> Int { count }
}

private enum AuthorizationHeaderParts {
    static func parse(_ header: String) -> [String: String] {
        var result: [String: String] = [:]
        let prefix = "MediaBrowser "
        let body = header.hasPrefix(prefix) ? String(header.dropFirst(prefix.count)) : header
        var rest = Substring(body)
        while let equals = rest.firstIndex(of: "=") {
            let key = rest[..<equals].trimmingCharacters(in: .whitespaces)
            var valueStart = rest.index(after: equals)
            guard valueStart < rest.endIndex, rest[valueStart] == "\"" else { break }
            valueStart = rest.index(after: valueStart)
            guard let endQuote = rest[valueStart...].firstIndex(of: "\"") else { break }
            result[String(key)] = urlDecode(String(rest[valueStart..<endQuote]))
            let after = rest.index(after: endQuote)
            guard after < rest.endIndex else { break }
            rest = rest[rest.index(after: after)...]
        }
        return result
    }

    static func urlDecode(_ value: String) -> String {
        let plus = value.replacingOccurrences(of: "+", with: " ")
        return plus.removingPercentEncoding ?? plus
    }
}

private func repoRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    while url.path != "/" {
        url.deleteLastPathComponent()
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("project.yml").path) {
            return url
        }
    }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
}
