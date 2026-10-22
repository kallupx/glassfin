import CoreModels
import Foundation
import XCTest

final class CountingLog: GlassfinLog, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var warnings: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func warning(_ message: String) {
        lock.lock()
        stored.append(message)
        lock.unlock()
    }

    func debug(_ message: String) {}
    func error(_ message: String) {}
}

enum Fixtures {
    static func data(_ name: String, sourceFile: String = #filePath) throws -> Data {
        var url = URL(fileURLWithPath: sourceFile).deletingLastPathComponent()
        let manager = FileManager.default
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("Tests/Fixtures/\(name)")
            if manager.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            url.deleteLastPathComponent()
        }
        XCTFail("Missing fixture \(name)")
        return Data()
    }
}

final class TicksTests: XCTestCase {
    func testPositionAndRuntimeEdges() {
        let log = CountingLog()
        XCTAssertEqual(Ticks.positionDuration(from: 0, log: log), .zero)
        XCTAssertEqual(
            Ticks.positionDuration(from: 1, log: log),
            Duration(secondsComponent: 0, attosecondsComponent: 100_000_000_000)
        )
        XCTAssertEqual(Ticks.positionDuration(from: Ticks.perSecond, log: log), .seconds(1))

        let overDay = Ticks.perSecond * 60 * 60 * 25
        let long = Ticks.positionDuration(from: overDay, log: log)
        XCTAssertEqual(long, .seconds(25 * 60 * 60))
        XCTAssertEqual(Ticks.ticks(from: long), overDay)

        let maximum = Ticks.positionDuration(from: Int64.max, log: log)
        XCTAssertEqual(Ticks.ticks(from: maximum), Int64.max)

        XCTAssertEqual(Ticks.positionDuration(from: -8, log: log), .zero)
        XCTAssertEqual(log.warnings.count, 1)

        XCTAssertNil(Ticks.runtimeDuration(from: nil))
        XCTAssertNil(Ticks.runtimeDuration(from: 0))
        XCTAssertNil(Ticks.runtimeDuration(from: -1))
        XCTAssertEqual(Ticks.runtimeDuration(from: Ticks.perSecond), .seconds(1))
        XCTAssertEqual(Ticks.outboundPositionTicks(from: .seconds(-4)), 0)
        XCTAssertEqual(Ticks.ticks(from: .seconds(-2)), 0)
    }
}

final class SemVerTests: XCTestCase {
    func testMinimumServerFloor() {
        XCTAssertEqual(SemVer(parsing: "10.10.0"), SemVer.minimumJellyfin)
        XCTAssertEqual(SemVer(parsing: "10.10"), SemVer.minimumJellyfin)
        XCTAssertEqual(SemVer(parsing: "10.10.7")?.meetsMinimumServer, true)
        XCTAssertEqual(SemVer(parsing: "12.2.0+meta")?.meetsMinimumServer, true)
        XCTAssertEqual(SemVer(parsing: "10.11.11")?.meetsMinimumServer, true)
        XCTAssertEqual(SemVer(parsing: "12.2.0-rc1")?.meetsMinimumServer, true)
        XCTAssertEqual(SemVer(parsing: "10.10.6")?.meetsMinimumServer, true)
        XCTAssertEqual(SemVer(parsing: "10.9.11")?.meetsMinimumServer, false)
        XCTAssertNil(SemVer(parsing: "10"))
        XCTAssertNil(SemVer(parsing: "abc"))
        XCTAssertNil(SemVer(parsing: ""))
        XCTAssertNil(SemVer(parsing: "not-a-version"))
    }
}

final class APIErrorTests: XCTestCase {
    func testOnlyUnauthorizedLogsOut() {
        XCTAssertTrue(LogoutPolicy.shouldLogOut(.unauthorized))
        let kept: [APIError] = [
            .forbidden,
            .notFound,
            .server(status: 500),
            .server(status: 503),
            .timeout,
            .network,
            .tls,
            .decoding,
            .cancelled,
            .redirectRejected(.httpsDowngrade),
            .invalidURL,
            .headerRejected,
            .transportSecurity,
        ]
        for error in kept {
            XCTAssertFalse(LogoutPolicy.shouldLogOut(error), "\(error)")
        }
        XCTAssertEqual(HTTPStatusMapper.failure(for: 200), nil)
        XCTAssertEqual(HTTPStatusMapper.failure(for: 401), .unauthorized)
        XCTAssertEqual(HTTPStatusMapper.failure(for: 403), .forbidden)
        XCTAssertEqual(HTTPStatusMapper.failure(for: 404), .notFound)
        XCTAssertEqual(HTTPStatusMapper.failure(for: 500), .server(status: 500))
        XCTAssertNotEqual(URLErrorMapper.map(URLError(.notConnectedToInternet)), .unauthorized)
        XCTAssertEqual(URLErrorMapper.map(URLError(.timedOut)), .timeout)
        XCTAssertEqual(URLErrorMapper.map(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(URLErrorMapper.map(URLError(.secureConnectionFailed)), .tls)
        XCTAssertEqual(URLErrorMapper.map(URLError(.cannotConnectToHost)), .network)
    }
}

final class UserSessionTests: XCTestCase {
    func testUserSessionDoesNotCarryTheAccessToken() {
        let session = UserSession(
            server: ServerInfo(
                id: "server",
                name: "Home",
                url: URL(string: "https://media.example")!,
                version: SemVer(major: 12, minor: 2, patch: 0)
            ),
            userID: "user-1",
            userName: "Ada",
            isAdministrator: false
        )
        let labels = Mirror(reflecting: session).children.compactMap(\.label)
        XCTAssertFalse(labels.contains { $0.lowercased().contains("token") })
        XCTAssertFalse(String(describing: session).contains("secret-token"))
        let authenticated = AuthenticatedSession(session: session, accessToken: "secret-token")
        XCTAssertFalse(String(describing: authenticated.session).contains("secret-token"))
    }
}

final class MapperTests: XCTestCase {
    func testMovieFixturesFromBothServerGenerations() throws {
        let current = try decodeItem("movie-12.json")
        XCTAssertEqual(current.kind, .movie)
        XCTAssertEqual(current.overview, "A quiet film.")
        XCTAssertEqual(current.runtime, .seconds(7200))
        XCTAssertEqual(current.images.primaryTag, "primary-tag")
        XCTAssertEqual(current.images.primaryBlurHash, "LGF5]+Yk^6#M@-5c,1J5@[or[Q6.")
        XCTAssertEqual(current.userData.playbackPosition, .seconds(1))
        XCTAssertEqual(current.trickplay?[320]?.width, 320)
        XCTAssertEqual(current.chapters.first?.name, "Opening")

        let old = try decodeItem("movie-10.10.json")
        XCTAssertNil(old.overview)
        XCTAssertNil(old.runtime)
        XCTAssertNil(old.images.primaryTag)
        XCTAssertNil(old.trickplay)
        XCTAssertTrue(old.chapters.isEmpty)

        let unknown = try decodeItem("unknown-type.json")
        XCTAssertEqual(unknown.kind, .other("Plugin"))
    }

    func testSegmentsAndPlaybackInfo() throws {
        let segments = try JSONDecoder().decode([MediaSegmentDTO].self, from: Fixtures.data("segments.json"))
        let mapped = segments.compactMap(DTOMapper.segment)
        XCTAssertEqual(mapped.count, 2)
        XCTAssertEqual(mapped[0].kind, .intro)
        XCTAssertEqual(mapped[1].kind, .unknown)

        let playback = try JSONDecoder().decode(PlaybackInfoResponseDTO.self, from: Fixtures.data("playback-12.json"))
        let source = try XCTUnwrap(
            DTOMapper.playbackSource(playback, server: URL(string: "https://media.example/jellyfin")!)
        )
        XCTAssertEqual(source.method, .directStream)
        XCTAssertEqual(source.playSessionID, "play-1")
        XCTAssertEqual(source.audioTracks.first?.language, "eng")
        XCTAssertEqual(source.subtitleTracks.first?.displayTitle, "Finnish")
        XCTAssertEqual(source.url?.path, "/jellyfin/Videos/movie-12/stream")
    }

    func testPublicSystemInfo() throws {
        let current = try JSONDecoder().decode(PublicSystemInfoDTO.self, from: Fixtures.data("system-public-12.json"))
        let info = try XCTUnwrap(DTOMapper.serverInfo(current, url: URL(string: "https://media.example")!))
        XCTAssertEqual(info.version, SemVer(major: 12, minor: 2, patch: 0))
        XCTAssertTrue(info.version.meetsMinimumServer)

        let old = try JSONDecoder().decode(PublicSystemInfoDTO.self, from: Fixtures.data("system-public-10.10.json"))
        XCTAssertEqual(DTOMapper.serverInfo(old, url: URL(string: "http://old.example")!)?.version.patch, 7)
    }

    func testItemIDAcceptsGUIDsAndRejectsPathText() throws {
        let plain = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let dashed = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        XCTAssertEqual(ItemID(plain)?.value, plain)
        XCTAssertEqual(ItemID(dashed)?.value, dashed)
        XCTAssertNil(ItemID("item"))
        XCTAssertNil(ItemID("../Admin"))
        XCTAssertNil(ItemID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
        XCTAssertNil(ItemID(plain + "/Extra"))
        XCTAssertEqual(try ItemID.require(plain).value, plain)
        do {
            _ = try ItemID.require("item/../../etc")
            XCTFail("Expected invalidItemID")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalidItemID)
            XCTAssertFalse(LogoutPolicy.shouldLogOut(error))
        }
    }

    func testT04_20_versionMatrixUsesTheSingleParser() throws {
        let supported = ["10.10.0", "10.10", "10.10.7", "10.11.11", "12.2.0", "12.2.0-rc1", "10.10.0-beta.1"]
        for raw in supported {
            let version = SemVer(parsing: raw)
            XCTAssertEqual(version?.meetsMinimumServer, true, raw)
            XCTAssertNil(ServerVersionGate.failure(for: try XCTUnwrap(version)), raw)
        }
        XCTAssertEqual(
            ServerVersionGate.failure(for: try XCTUnwrap(SemVer(parsing: "10.9.11"))),
            .unsupportedServer(version: "10.9.11")
        )
        for raw in ["10", "abc", "", "not-a-version"] {
            XCTAssertNil(SemVer(parsing: raw), raw)
        }
    }

    func testAuthCatalogHasEnglishAndFinnishForEveryKey() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CoreModels/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(StringCatalogFile.self, from: data)
        XCTAssertEqual(catalog.sourceLanguage, "en")
        for key in AuthCopy.Key.allCases {
            let entry = try XCTUnwrap(catalog.strings[key.rawValue], key.rawValue)
            XCTAssertFalse(entry.value(for: "en")?.isEmpty ?? true, key.rawValue)
            XCTAssertFalse(entry.value(for: "fi")?.isEmpty ?? true, key.rawValue)
        }
    }

    private func decodeItem(_ name: String) throws -> MediaItem {
        let dto = try JSONDecoder().decode(BaseItemDTO.self, from: Fixtures.data(name))
        return try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
    }
}

private struct StringCatalogFile: Decodable {
    var sourceLanguage: String
    var strings: [String: Entry]

    struct Entry: Decodable {
        var localizations: [String: Localization]?

        func value(for language: String) -> String? {
            localizations?[language]?.stringUnit?.value
        }
    }

    struct Localization: Decodable {
        var stringUnit: Unit?
    }

    struct Unit: Decodable {
        var value: String
    }
}
