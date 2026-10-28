import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

final class HLSCredentialQueryTests: XCTestCase {
    private let master = URL(string: "https://media.example/master.m3u8")!
    private let header = "header-canary"

    /// T08P-101: both credential spellings and their original percent encoding survive only in playlist GETs.
    func testT08P_101_masterVariantAndKeyAuthentication() throws {
        for name in ["ApiKey", "aPiKeY", "api" + "_key", "API" + "_KEY"] {
            let raw = name + "=server%2bcanary%2F%3d"
            let serverURL = try XCTUnwrap(URL(string: master.absoluteString + "?PlaySessionId=keep&" + raw))
            let plan = MediaOpenPlanner.plan(
                delivery: .serverHLS, resolvedURL: serverURL, authorizationHeader: header,
                options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false))
            guard case .resourceLoader(let carrier) = plan.primary else { return XCTFail("No loader") }
            let credentials = try XCTUnwrap(carrier.playlistCredentials)
            for url in [carrier.assetURL, carrier.originURL] {
                XCTAssertFalse(url.absoluteString.contains("canary"))
                XCTAssertFalse(MediaCredentialQuery.contains(url))
            }
            XCTAssertNil(MediaAssetScheme.wrap(serverURL))
            for path in ["master.m3u8", "variant.m3u8"] {
                let clean = try XCTUnwrap(URL(string: "https://media.example/" + path + "?x=%2f"))
                let request = try XCTUnwrap(planRequest(clean, credentials: credentials))
                XCTAssertNil(request.authorizationHeader)
                XCTAssertTrue(request.url.absoluteString.hasSuffix("?x=%2f&" + raw))
                XCTAssertNil(request.range)
                XCTAssertFalse(request.description.contains("canary"))
                XCTAssertNil(
                    OriginMediaRequest(
                        method: "GET", url: request.url, authorizationHeader: header, trust: .publiclyTrusted))
            }
            let playlist = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.m3u8?" + raw + "\"\n"
            guard case .success(let rewrite) = HLSPlaylistRewriter.rewrite(playlist: playlist, baseURL: master) else {
                return XCTFail("Key rewrite failed")
            }
            let keyText = try XCTUnwrap(
                rewrite.playlist.components(separatedBy: "URI=\"").last?.split(separator: "\"").first)
            let keyAsset = try XCTUnwrap(URL(string: String(keyText)))
            XCTAssertFalse(keyAsset.absoluteString.contains("canary"))
            let key = try XCTUnwrap(
                ResourceLoadPlanner.originRequest(
                    assetURL: keyAsset, authorizationHeader: header, trust: .publiclyTrusted, range: nil,
                    allowedOrigin: master, playlistCredentials: credentials))
            XCTAssertEqual(key.authorizationHeader, header)
            XCTAssertFalse(MediaCredentialQuery.contains(key.url))
            for path in ["key", "file.mp4", "init.mp4", "segment.m4s"] {
                let request = try XCTUnwrap(
                    planRequest(
                        URL(string: "https://media.example/" + path)!, credentials: credentials))
                XCTAssertEqual(request.authorizationHeader, header)
                XCTAssertFalse(MediaCredentialQuery.contains(request.url))
            }
            for text in [
                plan.description, carrier.description, carrier.debugDescription,
                credentials.description, credentials.debugDescription,
            ] {
                XCTAssertFalse(text.contains("canary"))
            }
        }
    }

    func testT08P_101_duplicateNamesAndUnsafeOrigins() throws {
        let credentials = try XCTUnwrap(
            ServerHLSCredentialQuery(
                transcodingURL: URL(string: master.absoluteString + "?ApiKey=server%2bcanary")!))
        let duplicate = URL(string: master.absoluteString + "?aPiKeY=existing%2f&x=1")!
        XCTAssertTrue(credentials.appending(toPlaylist: duplicate)?.absoluteString == duplicate.absoluteString)
        XCTAssertNil(ServerHLSCredentialQuery(transcodingURL: master))
        XCTAssertNil(
            ServerHLSCredentialQuery(transcodingURL: URL(string: "https://user:pw@media.example/master.m3u8?ApiKey=x")!)
        )
        for uri in [
            "https://foreign.example/variant.m3u8", "http://media.example/variant.m3u8",
            "https://user:pw@media.example/variant.m3u8", "https://@media.example/variant.m3u8",
        ] {
            let url = try XCTUnwrap(URL(string: uri))
            XCTAssertNil(credentials.appending(toPlaylist: url))
            XCTAssertNil(planRequest(url, credentials: credentials))
        }
    }

    /// T08P-101: segments and EXT-X-MAP keep only the server-written token; no app-added query.
    func testT08P_101_mediaAndMapRemainServerWrittenAndValidated() throws {
        for name in ["ApiKey", "api" + "_key"] {
            let map = "https://media.example/init.mp4?" + name + "=server%2bcanary"
            let segment = "https://media.example/segment.m4s?" + name + "=server%2bcanary"
            let playlist = "#EXTM3U\n#EXT-X-MAP:URI=\"" + map + "\"\n#EXTINF:6,\n" + segment
            guard case .success(let rewrite) = HLSPlaylistRewriter.rewrite(playlist: playlist, baseURL: master) else {
                return XCTFail("Rewrite failed")
            }
            XCTAssertTrue(rewrite.playlist == playlist)
            XCTAssertFalse(rewrite.description.contains("canary"))
            for unsafe in ["https://foreign.example/x", "http://media.example/x", "https://user@media.example/x"] {
                for line in [unsafe, "#EXT-X-MAP:URI=\"" + unsafe + "\""] {
                    guard case .failure = HLSPlaylistRewriter.rewrite(playlist: "#EXTM3U\n" + line, baseURL: master)
                    else {
                        return XCTFail("Unsafe media accepted")
                    }
                }
            }
        }
    }

    /// T08P-101: the preparation master GET obeys the same rule as the native loader, including redirects.
    func testT08P_101_preparationCarriesVerbatimQueryAndRejectsForeignRedirect() async throws {
        let original = URL(string: master.absoluteString + "?ApiKey=server%2bcanary")!
        let credentials = try XCTUnwrap(ServerHLSCredentialQuery(transcodingURL: original))
        let client = MockPlaybackOrigin()
        await client.setResponses([
            OriginMediaResponse(status: 302, location: URL(string: "/resolved.m3u8")), OriginMediaResponse(status: 200),
        ])
        let result = try await PlaybackPreparation(client: client).prepare(
            delivery: .serverHLS, initialURL: master, authorizationHeader: header,
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false),
            playlistCredentials: credentials)
        guard case .open(let plan) = result, case .resourceLoader(let carrier) = plan.primary else {
            return XCTFail("Preparation failed")
        }
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(
            requests.allSatisfy {
                $0.authorizationHeader == nil && $0.url.absoluteString.hasSuffix("ApiKey=server%2bcanary")
            })
        XCTAssertFalse(carrier.assetURL.absoluteString.contains("canary"))
        XCTAssertNotNil(carrier.playlistCredentials)
        let resolution = try await PlaybackURLResolver(client: MockPlaybackOrigin()).resolve(
            start: master, method: "GET", authorizationHeader: header, trust: .publiclyTrusted,
            playlistCredentials: credentials)
        guard case .resolved(let resolved) = resolution else { return XCTFail("Resolution failed") }
        XCTAssertFalse(MediaCredentialQuery.contains(resolved))
        XCTAssertFalse(String(describing: resolution).contains("canary"))
        let foreign = MockPlaybackOrigin(
            response: OriginMediaResponse(
                status: 302, location: URL(string: "https://foreign.example/master.m3u8")))
        let rejected = try await PlaybackPreparation(client: foreign).prepare(
            delivery: .serverHLS, initialURL: master, authorizationHeader: header,
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false),
            playlistCredentials: credentials)
        XCTAssertEqual(rejected, .rejected(.insecureRedirect))
        let sent = await foreign.requests
        XCTAssertEqual(sent.count, 1)
    }

    func testT08P_101_logRedactsBothNamesIgnoringCase() {
        for name in ["ApiKey", "aPiKeY", "api" + "_key", "API" + "_KEY"] {
            for value in ["?\(name)=server-canary", "{\"\(name)\":\"server-canary\"}", "?\(name)%3Dserver-canary"] {
                let redacted = MediaLogRedactor.redact(value)
                XCTAssertFalse(redacted.contains("server-canary"))
                XCTAssertTrue(redacted.contains("<redacted>"))
            }
        }
    }

    private func planRequest(_ url: URL, credentials: ServerHLSCredentialQuery) -> OriginMediaRequest? {
        guard let asset = MediaAssetScheme.wrap(url) else { return nil }
        return ResourceLoadPlanner.originRequest(
            assetURL: asset, authorizationHeader: header, trust: .publiclyTrusted,
            range: HTTPByteRange(start: 0, end: 1), allowedOrigin: master, playlistCredentials: credentials)
    }
}
