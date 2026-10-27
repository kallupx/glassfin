import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T04ProbeTests: XCTestCase {
    func testT04_06_schemelessHostTriesHTTPSPortsOnly() async {
        let script = ScriptedCandidates()
        script.sequence = [.timedOut, .timedOut]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "jellyfin.example.com")
        XCTAssertEqual(script.schemesAndPorts(), ["https:443", "https:8920"])
        XCTAssertFalse(script.urls.contains { $0.scheme == "http" })
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverNotFound)
        XCTAssertTrue(ProbeErrorCopy.httpSkippedByPolicy(outcome))
        if case .publicHTTPRejected = outcome {
            XCTFail("schemeless public host is not the explicit http rejection")
        }
    }

    func testT04_07_explicitPortIsTheOnlyCandidate() async {
        let script = ScriptedCandidates()
        script.sequence = [.timedOut]
        _ = await ServerProbe(client: script, clock: StillClock()).run(address: "https://host.example:8096/jellyfin")
        XCTAssertEqual(script.urls.count, 1)
        let parts = urlParts(script.urls[0])
        XCTAssertEqual(parts?.scheme, "https")
        XCTAssertEqual(parts?.port, 8096)
        XCTAssertEqual(parts?.path, "/jellyfin")
    }

    func testT04_08_reverseProxySubpathIsKept() {
        for raw in ["https://host.example/jellyfin", "https://host.example/jellyfin/"] {
            let plan = ServerAddressCandidates.expand(raw)
            XCTAssertFalse(plan.invalid, raw)
            for candidate in plan.candidates where candidate.mayConnect {
                let joined = ServerAddressCandidates.appendingAPIPath(candidate.url, path: "/System/Info/Public")
                XCTAssertEqual(joined?.path, "/jellyfin/System/Info/Public", raw)
            }
        }
    }

    func testT04_09_forbiddenSchemesMakeNoRequests() async {
        let script = ScriptedCandidates()
        for raw in ["ftp://h", "file:///x", "javascript:x", "glassfin-media://x"] {
            let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: raw)
            XCTAssertEqual(outcome, .invalidAddress, raw)
            XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .invalidAddress, raw)
        }
        XCTAssertTrue(script.urls.isEmpty)
    }

    func testT04_10_userinfoIsRejectedBeforeAnyCandidate() async {
        let script = ScriptedCandidates()
        for input in [
            "https://user:pass@example.com/jellyfin", "user:pass@example.com/jellyfin",
            "https://user@example.com", "http://user:pass@192.168.1.10:8096",
        ] {
            let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: input)
            XCTAssertEqual(outcome, .userinfoRejected)
            XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .userinfoRejected)
        }
        XCTAssertTrue(script.urls.isEmpty)
    }

    func testT04_11_explicitPublicHTTPIsRejectedWithNoRequest() async {
        let script = ScriptedCandidates()
        for raw in ["http://203.0.113.5:8096", "http://8.8.8.8", "http://jellyfin.example.com"] {
            let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: raw)
            XCTAssertEqual(outcome, .publicHTTPRejected, raw)
            XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .publicAddressRequiresHTTPS, raw)
            XCTAssertFalse(ProbeErrorCopy.httpSkippedByPolicy(outcome), raw)
        }
        XCTAssertTrue(script.urls.isEmpty)
    }

    /// Q4-20: a schemeless public IP does not fall back to HTTP and is not `publicHTTPRejected`.
    func testT04_12_schemelessPublicIPDoesNotRequestHTTP() async {
        let script = ScriptedCandidates()
        script.sequence = [.timedOut, .refused]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "203.0.113.5")
        XCTAssertEqual(script.schemesAndPorts(), ["https:443", "https:8920"])
        XCTAssertFalse(script.urls.contains { $0.scheme == "http" })
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverNotFound)
        XCTAssertTrue(ProbeErrorCopy.httpSkippedByPolicy(outcome))
        guard case .notFound(let detail) = outcome else { return XCTFail("expected not found") }
        XCTAssertTrue(detail.httpSkippedByPolicy)
    }

    /// Q4-20: a schemeless public multi-label name does not fall back to HTTP.
    func testT04_13_schemelessPublicHostnameDoesNotRequestHTTP() async {
        let script = ScriptedCandidates()
        script.sequence = [.refused, .timedOut]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "jellyfin.example.com")
        XCTAssertEqual(script.schemesAndPorts(), ["https:443", "https:8920"])
        XCTAssertFalse(script.urls.contains { $0.scheme == "http" })
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverNotFound)
        XCTAssertTrue(ProbeErrorCopy.httpSkippedByPolicy(outcome))
    }

    func testT04_14_tlsStopsAndDoesNotTryHTTP() async {
        let leaf = sampleLeaf()
        let script = ScriptedCandidates()
        script.sequence = [.tls(leaf), .jellyfin(sampleServer(), startupComplete: true)]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "jellyfin.example.com")
        XCTAssertEqual(script.urls.count, 1)
        XCTAssertEqual(script.urls.first?.scheme, "https")
        guard case .needsCertificate(let presented, _) = outcome else { return XCTFail("expected certificate") }
        XCTAssertEqual(presented, leaf)
    }

    func testT04_17_dnsStopsWhileRefusalContinues() async {
        let dns = ScriptedCandidates()
        dns.sequence = [.dnsFailure, .jellyfin(sampleServer(), startupComplete: true)]
        let dnsOutcome = await ServerProbe(client: dns, clock: StillClock()).run(address: "jellyfin.example.com")
        XCTAssertEqual(dns.urls.count, 1)
        XCTAssertEqual(ProbeErrorCopy.key(for: dnsOutcome), .serverNotFound)
        XCTAssertTrue(ProbeErrorCopy.httpSkippedByPolicy(dnsOutcome))

        let refused = ScriptedCandidates()
        let server = sampleServer(url: "https://media.example:8920")
        refused.sequence = [.refused, .jellyfin(server, startupComplete: true)]
        let refusedOutcome = await ServerProbe(client: refused, clock: StillClock()).run(address: "media.example")
        XCTAssertEqual(refused.urls.count, 2)
        guard case .ready = refusedOutcome else { return XCTFail("expected the second HTTPS port") }
    }

    func testT04_18_nonJellyfinResponseTriesTheNextAllowedCandidate() async {
        let portal = ScriptedCandidates()
        portal.sequence = [.notJellyfin, .notJellyfin]
        let publicOutcome = await ServerProbe(client: portal, clock: StillClock()).run(address: "captive.example.com")
        XCTAssertEqual(portal.schemesAndPorts(), ["https:443", "https:8920"])
        XCTAssertFalse(portal.urls.contains { $0.scheme == "http" })
        XCTAssertEqual(ProbeErrorCopy.key(for: publicOutcome), .notJellyfin)
        XCTAssertTrue(ProbeErrorCopy.httpSkippedByPolicy(publicOutcome))

        let local = ScriptedCandidates()
        let server = sampleServer(url: "http://192.168.1.10:8096")
        local.sequence = [.notJellyfin, .notJellyfin, .jellyfin(server, startupComplete: true)]
        let localOutcome = await ServerProbe(client: local, clock: StillClock()).run(address: "192.168.1.10")
        XCTAssertTrue(local.urls.contains { $0.scheme == "http" })
        guard case .needsCleartext = localOutcome else { return XCTFail("expected cleartext after HTML on HTTPS") }
        XCTAssertFalse(ProbeErrorCopy.httpSkippedByPolicy(localOutcome))
    }

    func testT04_19_oldServerStopsAsUnsupported() async {
        let script = ScriptedCandidates()
        let server = sampleServer(version: SemVer(major: 10, minor: 9, patch: 11))
        script.sequence = [.jellyfin(server, startupComplete: true)]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "https://media.example")
        guard case .unsupported(let version, _) = outcome else { return XCTFail("expected unsupported") }
        XCTAssertEqual(version, "10.9.11")
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .unsupportedServer)
        XCTAssertEqual(script.urls.count, 1)
    }

    func testT04_22_cancelledCandidateDoesNotBecomeReady() async {
        let script = ScriptedCandidates()
        script.sequence = [.cancelled]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "https://media.example")
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertNil(ProbeErrorCopy.key(for: outcome))
        XCTAssertEqual(script.urls.count, 1)
    }

    func testT04_23_attemptAndOverallBudgets() async {
        XCTAssertEqual(ServerAddressCandidates.attemptTimeout, .seconds(5))
        XCTAssertEqual(ServerAddressCandidates.overallTimeout, .seconds(20))
        let clock = AdvancingClock()
        let script = ScriptedCandidates()
        script.clock = clock
        script.advance = .seconds(15)
        script.sequence = [.timedOut, .timedOut, .timedOut, .timedOut]
        _ = await ServerProbe(client: script, clock: clock).run(address: "10.0.0.8")
        XCTAssertEqual(script.timeouts.first, .seconds(5))
        XCTAssertLessThan(script.urls.count, 4)
    }

    func testWizardIncompleteStopsWithoutAnotherCandidate() async {
        let script = ScriptedCandidates()
        script.sequence = [
            .jellyfin(sampleServer(), startupComplete: false),
            .jellyfin(sampleServer(), startupComplete: true),
        ]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "https://media.example")
        guard case .setupIncomplete(let address) = outcome else { return XCTFail("expected setup") }
        XCTAssertEqual(address.host, "media.example")
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .setupIncomplete)
        XCTAssertEqual(script.urls.count, 1)
    }

    func testPrivateHTTPIsAllowedByPolicy() throws {
        let url = try XCTUnwrap(URL(string: "http://192.168.1.10:8096"))
        XCTAssertEqual(ServerTransportPolicy.evaluate(url), .unencryptedLocal)
        let plan = ServerAddressCandidates.expand("http://192.168.1.10:8096")
        XCTAssertEqual(plan.candidates.count, 1)
        XCTAssertTrue(plan.candidates[0].mayConnect)
        XCTAssertFalse(plan.explicitPublicHTTP)
    }

    func testRemovedLocalSuffixesArePublicHTTP() {
        for raw in ["http://nas.lan", "http://files.internal", "http://media.home.arpa"] {
            let plan = ServerAddressCandidates.expand(raw)
            XCTAssertTrue(plan.explicitPublicHTTP, raw)
            XCTAssertTrue(plan.candidates.allSatisfy { !$0.mayConnect }, raw)
        }
    }

    func testInterpreterRequiresJellyfinProductName() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example/jellyfin"))
        let html = Data("<html>portal</html>".utf8)
        XCTAssertEqual(PublicInfoInterpreter.interpret(html, url: url), .notJellyfin)
        let missing = Data(#"{"ServerName":"Home","Version":"10.11.0","Id":"abc"}"#.utf8)
        XCTAssertEqual(PublicInfoInterpreter.interpret(missing, url: url), .notJellyfin)
        let wizard = Data(
            """
            {"ProductName":"Jellyfin Server","ServerName":"Home","Version":"10.11.0",\
            "Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","StartupWizardCompleted":false}
            """.utf8)
        guard case .jellyfin(_, let startup) = PublicInfoInterpreter.interpret(wizard, url: url) else {
            return XCTFail("expected a jellyfin record")
        }
        XCTAssertFalse(startup)
        let twoPart = Data(
            """
            {"ProductName":"Jellyfin Server","ServerName":"<b>Home</b>","Version":"10.10",\
            "Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
            """.utf8)
        guard case .jellyfin(let info, let complete) = PublicInfoInterpreter.interpret(twoPart, url: url) else {
            return XCTFail("expected 10.10")
        }
        XCTAssertTrue(complete)
        XCTAssertEqual(info.version, SemVer(major: 10, minor: 10, patch: 0))
    }

    func testATSErrorMapsToThePublicHTTPKey() {
        let error = URLError(.appTransportSecurityRequiresSecureConnection)
        XCTAssertEqual(URLErrorMapper.map(error), .transportSecurity)
        let mapped = AppErrorMapping.map(.transportSecurity, context: .anonymous, deviceOffline: false)
        XCTAssertEqual(mapped, .publicHTTPRejected)
        XCTAssertEqual(AuthCopy.key(for: mapped), .publicAddressRequiresHTTPS)
        XCTAssertFalse(LogoutPolicy.shouldLogOut(.transportSecurity))
    }

    func testT04_29_coordinatorStoresOnlyPinToStore() throws {
        let leafHex = String(repeating: "ab", count: 32)
        let leaf = CertificatePresentation(
            sha256: leafHex, subject: "CN=media", notBefore: Date(timeIntervalSince1970: 10),
            notAfter: Date(timeIntervalSince1970: 20))
        let store = RecordingPins()
        let coordinator = CertificateAcceptanceCoordinator(pins: store)
        let grouped = leafHex.enumerated().map { index, character in
            index.isMultiple(of: 2) && index > 0 ? ":\(character)" : String(character)
        }.joined().uppercased()
        let accepted = try coordinator.apply(
            isSystemTrusted: false, leaf: leaf, pinnedSHA256: nil, userAcceptedFingerprint: grouped,
            serverID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(accepted.pinToStore, leafHex)
        XCTAssertEqual(store.saved, [leafHex])
        XCTAssertFalse(store.saved.contains(grouped))

        let wrong = String(repeating: "cd", count: 32)
        let stored = String(repeating: "ef", count: 32)
        let mismatch = try coordinator.apply(
            isSystemTrusted: false, leaf: leaf, pinnedSHA256: stored, userAcceptedFingerprint: wrong,
            serverID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertNil(mismatch.pinToStore)
        XCTAssertEqual(store.saved, [leafHex])
        XCTAssertFalse(store.saved.contains(wrong))
        if case .cancelPinMismatch(let previous, _) = mismatch.decision {
            XCTAssertEqual(previous, stored)
        } else {
            XCTFail("expected a pin mismatch")
        }
    }

    func testT04_30_rejectWritesNothing() throws {
        let store = RecordingPins()
        let coordinator = CertificateAcceptanceCoordinator(pins: store)
        let outcome = try coordinator.apply(
            isSystemTrusted: false, leaf: sampleLeaf(), pinnedSHA256: nil, userAcceptedFingerprint: nil,
            serverID: "server")
        XCTAssertNil(outcome.pinToStore)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testT04_32_systemTrustedLeafIsNotPinned() throws {
        let store = RecordingPins()
        let coordinator = CertificateAcceptanceCoordinator(pins: store)
        let outcome = try coordinator.apply(
            isSystemTrusted: true, leaf: sampleLeaf(), pinnedSHA256: nil, userAcceptedFingerprint: sampleLeaf().sha256,
            serverID: "server")
        XCTAssertEqual(outcome.decision, .performDefaultHandling)
        XCTAssertNil(outcome.pinToStore)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testT04_53_vaultAttributesAndWritePlan() throws {
        let store = AttributeSecureStore()
        let settings = InMemorySettingsStore()
        let server = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let user = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let vault = CredentialVault(
            secureStore: store, settings: settings, accessGroup: "TEAMID.org.glassfin.app")
        let profile = StoredSessionProfile(
            serverID: server, serverName: "Home", serverURL: "https://media.example", userID: user, userName: "Ada",
            isAdministrator: false)
        try vault.save(token: "token-value", serverID: server, userID: user, profile: profile)
        let account = try CredentialVault.tokenAccount(serverID: server, userID: user)
        let attributes = try XCTUnwrap(store.attributes(for: account))
        XCTAssertEqual(attributes.accessibility, "AfterFirstUnlockThisDeviceOnly")
        XCTAssertFalse(attributes.synchronizable)
        XCTAssertEqual(attributes.accessGroup, "TEAMID.org.glassfin.app")
        XCTAssertNotEqual(account, DeviceIdentityStore.account)
        XCTAssertEqual(KeychainWritePlan.afterUpdate(status: KeychainWritePlan.success), .updated)
        XCTAssertEqual(KeychainWritePlan.afterUpdate(status: KeychainWritePlan.itemNotFound), .add)
        let settingsText = settings.allValues().values.joined()
        XCTAssertFalse(settingsText.contains("token-value"))
    }

    func testT04_56_authorizationHeaderOmitsTokenUntilLogin() async throws {
        let transport = RecordingRequestTransport()
        let anonymous = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://media.example")),
            identity: ClientIdentity(deviceName: "TV", deviceID: "device-1", version: "0.1.0"),
            transport: transport
        )
        _ = try await anonymous.send(APIRequest(method: "POST", path: "/Users/AuthenticateByName"))
        let before = try XCTUnwrap(transport.calls().first)
        let beforeHeader = try XCTUnwrap(before.value(forHTTPHeaderField: "Authorization"))
        let authorizationCount = before.allHTTPHeaderFields?.keys.filter {
            $0.caseInsensitiveCompare("Authorization") == .orderedSame
        }.count
        XCTAssertEqual(authorizationCount, 1)
        XCTAssertFalse(beforeHeader.contains("Token="))
        XCTAssertFalse(before.url?.query?.contains("ApiKey") ?? false)
        XCTAssertFalse(before.url?.absoluteString.contains("Token=") ?? false)

        transport.reset()
        let signedIn = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://media.example")),
            identity: ClientIdentity(deviceName: "TV", deviceID: "device-1", version: "0.1.0", token: "secret-token"),
            transport: transport
        )
        _ = try await signedIn.send(APIRequest(method: "GET", path: "/Users/Me"))
        let after = try XCTUnwrap(transport.calls().first)
        let afterHeader = try XCTUnwrap(after.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(afterHeader.contains("Token=\"secret-token\""))
        let signedInCount = after.allHTTPHeaderFields?.keys.filter {
            $0.caseInsensitiveCompare("Authorization") == .orderedSame
        }.count
        XCTAssertEqual(signedInCount, 1)
        XCTAssertFalse(after.url?.absoluteString.contains("secret-token") ?? true)
    }

    func testT04_71_discoveryDoesNotAutoConnect() throws {
        let packet = Data(
            #"{"Address":"http://192.168.1.10:8096","Id":"id-1","Name":"Kotipalvelin"}"#.utf8)
        let parsed = try XCTUnwrap(DiscoveryPolicy.parse(packet, storedURL: nil, publicInfoID: nil))
        XCTAssertFalse(parsed.autoConnect)
        XCTAssertEqual(parsed.name, "Kotipalvelin")
        XCTAssertEqual(parsed.url.host, "192.168.1.10")
        XCTAssertEqual(parsed.port, 8096)
    }

    func testT04_72_discoveryNameIsPlainAndCapped() throws {
        let long = String(repeating: "n", count: 80)
        let packet = Data(
            #"{"Address":"http://192.168.1.10:8096","Id":"id-1","Name":"<b>\#(long)</b>"}"#.utf8)
        let parsed = try XCTUnwrap(DiscoveryPolicy.parse(packet, storedURL: nil, publicInfoID: nil))
        XCTAssertFalse(parsed.name.contains("<"))
        XCTAssertLessThanOrEqual(parsed.name.count, DiscoveryPolicy.maximumNameLength)
    }

    func testT04_73_discoveryIDMismatchIsFlagged() throws {
        let packet = Data(#"{"Address":"http://192.168.1.10:8096","Id":"one","Name":"Home"}"#.utf8)
        let parsed = try XCTUnwrap(DiscoveryPolicy.parse(packet, storedURL: nil, publicInfoID: "two"))
        XCTAssertTrue(parsed.idMismatch)
    }

    func testT04_74_discoveryDoesNotRewriteAStoredURL() throws {
        let stored = try XCTUnwrap(URL(string: "https://saved.example/jellyfin"))
        let packet = Data(#"{"Address":"http://192.168.1.10:8096","Id":"one","Name":"Home"}"#.utf8)
        XCTAssertEqual(DiscoveryPolicy.storedAddress(afterDiscovery: stored, packet: packet), stored)
    }

    func testT04_plistAllowsLocalNetworkingWithoutExceptions() throws {
        let root = repoRoot()
        let arbitrary = "NSAllows" + "ArbitraryLoads"
        for platform in ["tvOS", "iOS"] {
            let url = root.appendingPathComponent("Apps/\(platform)/Info.plist")
            let data = try Data(contentsOf: url)
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let ats = try XCTUnwrap(plist["NSAppTransportSecurity"] as? [String: Any])
            XCTAssertEqual(ats["NSAllowsLocalNetworking"] as? Bool, true, platform)
            XCTAssertNil(ats[arbitrary], platform)
            XCTAssertNil(ats["NSException" + "Domains"], platform)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(arbitrary), platform)
        }
    }

    func testT04_06_localSchemelessProbeUsesAllFourPortsInOrder() async {
        let script = ScriptedCandidates()
        script.sequence = [.refused, .timedOut, .refused, .timedOut]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "nas/jellyfin/")
        XCTAssertEqual(script.schemesAndPorts(), ["https:443", "https:8920", "http:8096", "http:80"])
        XCTAssertEqual(script.timeouts, Array(repeating: .seconds(5), count: 4))
        XCTAssertTrue(script.urls.allSatisfy { $0.path == "/jellyfin" })
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverNotFound)
        XCTAssertFalse(ProbeErrorCopy.httpSkippedByPolicy(outcome))
    }

    func testT04_07_schemelessExplicitPortNeverTriesOtherPorts() async {
        let script = ScriptedCandidates()
        _ = await ServerProbe(client: script, clock: StillClock()).run(address: "nas:9443/jellyfin")
        XCTAssertEqual(script.schemesAndPorts(), ["https:9443", "http:9443"])
    }

    func testT04_10_queryAndFragmentAreRemovedFromEveryCandidateAndStoredURL() throws {
        for address in ["https://example.com/jellyfin?x=1#fragment", "nas/jellyfin?x=1#fragment", "nas?x=1#fragment"] {
            let plan = ServerAddressCandidates.expand(address)
            XCTAssertFalse(plan.invalid)
            for candidate in plan.candidates {
                XCTAssertNil(candidate.url.query)
                XCTAssertNil(candidate.url.fragment)
                XCTAssertNil(candidate.url.user)
            }
        }
    }

    func testT04_20_invalidVersionResponsesAreNotJellyfin() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        for raw in ["10", "10.ten", "unknown", "10.10.beta"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "Id": "server", "ProductName": "Jellyfin Server", "ServerName": "Home", "Version": raw,
            ])
            XCTAssertEqual(PublicInfoInterpreter.interpret(data, url: url), .notJellyfin)
        }
        for raw in ["10.10", "10.10.0-rc1", "10.10.7", "10.11.11", "12.2"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "Id": "server", "ProductName": "Jellyfin Server", "ServerName": "Home", "Version": raw,
            ])
            guard case .jellyfin(let info, _) = PublicInfoInterpreter.interpret(data, url: url) else {
                XCTFail("expected a supported version")
                continue
            }
            XCTAssertTrue(info.version.meetsMinimumServer)
        }
    }

    func testT04_23_fourTimeoutsHaveATwentySecondOverallBudget() async {
        let clock = AdvancingClock()
        let script = ScriptedCandidates()
        script.clock = clock
        script.advance = .seconds(5)
        script.sequence = Array(repeating: .timedOut, count: 4)
        let outcome = await ServerProbe(client: script, clock: clock).run(address: "nas")
        XCTAssertEqual(script.timeouts, Array(repeating: .seconds(5), count: 4))
        XCTAssertEqual(clock.now(), .seconds(20))
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverNotFound)
    }

    func testT04_29_coordinatorReuseNeverPersistsUserInputWithoutPinToStore() throws {
        let store = RecordingPins()
        let coordinator = CertificateAcceptanceCoordinator(pins: store)
        let leaf = sampleLeaf()
        let typed = leaf.sha256.uppercased()
        let first = try coordinator.apply(
            isSystemTrusted: false, leaf: leaf, pinnedSHA256: nil,
            userAcceptedFingerprint: typed, serverID: "server")
        XCTAssertEqual(store.saved, [try XCTUnwrap(first.pinToStore)])
        XCTAssertFalse(store.saved.contains(typed))
        let reused = try coordinator.apply(
            isSystemTrusted: false, leaf: leaf, pinnedSHA256: leaf.sha256,
            userAcceptedFingerprint: "untrusted-input", serverID: "server")
        XCTAssertEqual(reused.decision, .usePinnedCredential)
        XCTAssertNil(reused.pinToStore)
        XCTAssertEqual(store.saved, [leaf.sha256])
    }

    func testT04_84_dnsStopsEvenAfterANonJellyfinResponse() async {
        let script = ScriptedCandidates()
        script.sequence = [.notJellyfin, .dnsFailure, .jellyfin(sampleServer(), startupComplete: true)]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "nas")
        XCTAssertEqual(script.urls.count, 2)
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverNotFound)
    }

    func testT04_85_removedLocalSuffixesNeverRequestHTTP() async {
        for host in ["nas.lan", "nas.internal", "nas.home.arpa"] {
            let script = ScriptedCandidates()
            let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: host)
            XCTAssertEqual(script.schemesAndPorts(), ["https:443", "https:8920"])
            XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverNotFound)
            XCTAssertTrue(ProbeErrorCopy.httpSkippedByPolicy(outcome))
        }
    }

    func testT04_86_mixedNonJellyfinAndTimeoutEndsAsNotJellyfin() async {
        let script = ScriptedCandidates()
        script.sequence = [.notJellyfin, .timedOut, .refused, .timedOut]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "nas")
        XCTAssertEqual(script.urls.count, 4)
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .notJellyfin)
    }

    func testT04_90_bareHexIsAnOrdinaryLocalHostname() throws {
        for host in ["deadbeef", "c0a80001", "7f000001"] {
            let url = try XCTUnwrap(URL(string: "http://\(host)"))
            XCTAssertEqual(ServerTransportPolicy.evaluate(url), .unencryptedLocal)
            XCTAssertEqual(ServerAddressCandidates.expand(host).candidates.filter(\.mayConnect).count, 4)
        }
    }

    func testT04_94_transportSecurityDoesNotMasqueradeAsExplicitPublicHTTP() async {
        let script = ScriptedCandidates()
        script.sequence = [.transportSecurity]
        let outcome = await ServerProbe(client: script, clock: StillClock()).run(address: "example.com")
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverNotFound)
        XCTAssertTrue(ProbeErrorCopy.httpSkippedByPolicy(outcome))
        XCTAssertEqual(script.urls.count, 1)
    }

    private func urlParts(_ url: URL) -> (scheme: String, port: Int, path: String)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme
        else { return nil }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        return (scheme, port, components.path)
    }
}

private func sampleServer(
    url: String = "https://media.example",
    version: SemVer = SemVer(major: 10, minor: 11, patch: 0)
) -> ServerInfo {
    ServerInfo(
        id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", name: "Home", url: URL(string: url)!, version: version)
}

private func sampleLeaf() -> CertificatePresentation {
    CertificatePresentation(
        sha256: String(repeating: "ab", count: 32),
        subject: "CN=media",
        notBefore: Date(timeIntervalSince1970: 1),
        notAfter: Date(timeIntervalSince1970: 2)
    )
}

private final class ScriptedCandidates: ServerCandidateClient, @unchecked Sendable {
    var sequence: [ServerCandidateResult] = []
    var urls: [URL] = []
    var timeouts: [Duration] = []
    var clock: AdvancingClock?
    var advance: Duration = .zero
    var hold = false
    private var continuation: CheckedContinuation<ServerCandidateResult, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func fetchPublicInfo(url: URL, timeout: Duration) async -> ServerCandidateResult {
        urls.append(url)
        timeouts.append(timeout)
        if let clock, advance > .zero {
            clock.advance(by: advance)
        }
        if hold {
            started?.resume()
            started = nil
            return await withCheckedContinuation { continuation = $0 }
        }
        if !sequence.isEmpty { return sequence.removeFirst() }
        return .refused
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { started = $0 }
    }

    func release(_ result: ServerCandidateResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func schemesAndPorts() -> [String] {
        urls.map { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let scheme = components?.scheme ?? ""
            let port = components?.port ?? (scheme == "https" ? 443 : 80)
            return "\(scheme):\(port)"
        }
    }
}

private final class StillClock: GlassfinClock, @unchecked Sendable {
    func now() -> Duration { .zero }
    func sleep(for duration: Duration) async throws { _ = duration }
}

private final class AdvancingClock: GlassfinClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero

    func now() -> Duration {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by delta: Duration) {
        lock.lock()
        current += delta
        lock.unlock()
    }

    func sleep(for duration: Duration) async throws {
        advance(by: duration)
    }
}

private final class RecordingPins: CertificatePinStore, @unchecked Sendable {
    var saved: [String] = []
    private var values: [String: String] = [:]

    func fingerprint(for serverID: String) throws -> String? { values[serverID] }
    func save(fingerprint: String, serverID: String) throws {
        saved.append(fingerprint)
        values[serverID] = fingerprint
    }
    func remove(serverID: String) throws { values[serverID] = nil }
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
        values[account] = data
        written[account] = attributes
        lock.unlock()
    }

    func remove(account: String) throws {
        lock.lock()
        values[account] = nil
        lock.unlock()
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

    func data(for request: URLRequest) async throws -> (Data, URLResponse, Int?) {
        record(request)
        let url = request.url ?? URL(string: "https://media.example")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("ok".utf8), response, nil)
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

    func reset() {
        lock.lock()
        stored.removeAll()
        lock.unlock()
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
    return URL(fileURLWithPath: #filePath)
}
