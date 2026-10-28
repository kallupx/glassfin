import CoreModels
import Foundation
import XCTest

final class T06MetadataTests: XCTestCase {
    // T06-73: canonical spec/TESTPLAN-M06.md.
    func testT06_73_displayTextCaps500GraphemesWithoutSplittingEmojiOrCombiningMarks() {
        let raw = String(repeating: "👩‍👩‍👧‍👦a\u{0308}", count: 250)
        let expected = String(repeating: "👩‍👩‍👧‍👦a\u{0308}", count: 100)
        XCTAssertEqual(raw.count, 500)
        let cleaned = MetadataSanitizer.displayText(raw, limit: MetadataPolicy.nameMax)
        XCTAssertEqual(cleaned.count, 200)
        XCTAssertEqual(cleaned, expected)
        XCTAssertGreaterThan(cleaned.unicodeScalars.count, cleaned.count)
        XCTAssertEqual(MetadataSanitizer.displayText(raw, limit: 0), "")
        XCTAssertEqual(MetadataSanitizer.displayText(raw, limit: .max), raw)
    }

    // T06-73: canonical spec/TESTPLAN-M06.md.
    func testT06_73_displayTextStripsEveryControlAndBidiScalarBeforeCapping() {
        let controls = Array(0x00...0x1F) + Array(0x7F...0x9F)
        let bidi = [0x061C, 0x200E, 0x200F] + Array(0x202A...0x202E) + Array(0x2066...0x2069)
        let removed = (controls + bidi).compactMap(Unicode.Scalar.init).map(String.init).joined()
        let literal = "<b>x</b>&amp;&#x202e;**x**"
        XCTAssertEqual(
            MetadataSanitizer.displayText(removed + literal + removed, limit: MetadataPolicy.nameMax), literal)
        XCTAssertEqual(MetadataSanitizer.displayText(removed + "a\u{0308}👩‍👩‍👧‍👦x", limit: 2), "a\u{0308}👩‍👩‍👧‍👦")
    }

    // T06-73: canonical spec/TESTPLAN-M06.md.
    func testT06_73_allMappedNamesAreCappedAndKeepLiteralMarkup() throws {
        let literal = "<b>x</b>&amp;"
        let payloads = [literal, String(repeating: "👩‍👩‍👧‍👦a\u{0308}", count: 250)]
        for payload in payloads {
            let raw = "\u{061c}\u{200f}\u{202e}\u{2066}\u{0000}" + payload + "\u{0007}"
            let expected = String(payload.prefix(MetadataPolicy.nameMax))
            for kind in ["Movie", "Series", "Season", "Episode", "Person", "Studio", "MusicAlbum", "Audio"] {
                let dto = try decode(
                    BaseItemDTO.self,
                    ["Id": "item", "Type": kind, "Name": raw, "OfficialRating": raw, "Chapters": [["Name": raw]]])
                let item = try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
                XCTAssertEqual(item.name, expected, kind)
                XCTAssertEqual(item.officialRating, expected, kind)
                XCTAssertEqual(item.chapters.first?.name, expected, kind)
            }
            let library = try decode(BaseItemDTO.self, ["Id": "library", "Name": raw])
            XCTAssertEqual(DTOMapper.library(library)?.name, expected)
            let hints = try ResilientItemDecoder.searchHints(
                from: JSONSerialization.data(withJSONObject: ["SearchHints": [["ItemId": "hint", "Name": raw]]]),
                log: SilentLog())
            XCTAssertEqual(hints.first?.name, expected)

            let stream: [String: Any] = ["Type": "Audio", "DisplayTitle": raw, "Language": raw, "Codec": raw]
            let subtitle = stream.merging(["Type": "Subtitle"]) { _, value in value }
            var transcodingURL = URLComponents()
            transcodingURL.path = "/master.m3u8"
            transcodingURL.queryItems = [URLQueryItem(name: "TranscodeReasons", value: raw)]
            let playback = try decode(
                PlaybackInfoResponseDTO.self,
                [
                    "MediaSources": [
                        [
                            "Id": "source", "MediaStreams": [stream, subtitle],
                            "TranscodingUrl": try XCTUnwrap(transcodingURL.string),
                        ]
                    ]
                ])
            let source = try XCTUnwrap(
                DTOMapper.playbackSource(playback, server: URL(string: "https://media.example")!))
            XCTAssertEqual(source.audioTracks.first?.displayTitle, expected)
            XCTAssertEqual(source.subtitleTracks.first?.displayTitle, expected)
            XCTAssertEqual(source.audioTracks.first?.language, expected)
            XCTAssertEqual(source.audioTracks.first?.codec, expected)
            XCTAssertEqual(source.transcodeReasons, [expected])

            let server = ServerInfo(
                id: "server", name: "Home", url: URL(string: "https://media.example")!,
                version: SemVer(major: 10, minor: 11, patch: 0))
            let user = try decode(UserDTO.self, ["Id": "user", "Name": raw])
            XCTAssertEqual(DTOMapper.userSession(user, server: server)?.userName, expected)
            let auth = try decode(
                AuthenticationResultDTO.self, ["AccessToken": "token", "User": ["Id": "user", "Name": raw]])
            XCTAssertEqual(
                DTOMapper.session(auth: auth, serverURL: server.url, fallbackServerName: server.name)?.session.userName,
                expected)
        }
    }

    // T06-73: canonical spec/TESTPLAN-M06.md.
    func testT06_73_metadataPreservesLiteralMarkupAndEntities() {
        let literal = "<b>x</b>&amp;<script>x</script>**x**[x](https://example.invalid)"
        let source = "\u{202e}\u{200f}\u{0000}" + literal + "\u{0007}"
        XCTAssertEqual(MetadataPolicy.clean(source, limit: MetadataPolicy.nameMax), literal)
        XCTAssertEqual(MetadataSanitizer.plainText(source), literal)
    }

    // T06-73: canonical spec/TESTPLAN-M06.md.
    func testT06_73_limitsCountCleanedGraphemeClusters() {
        let pair = "👩‍👩‍👧‍👦e\u{0301}"
        for limit in [
            MetadataPolicy.nameMax, MetadataPolicy.overviewMax, MetadataPolicy.taglineMax,
            MetadataPolicy.genreMax, MetadataPolicy.displayNameMax,
        ] {
            for count in [limit - 1, limit, limit + 1] {
                let payload = String(String(repeating: pair, count: count).prefix(count))
                let source = "\u{202e}\u{0007}" + payload
                let cleaned = MetadataPolicy.clean(source, limit: limit)
                XCTAssertEqual(cleaned.count, min(count, limit))
                XCTAssertEqual(cleaned, String(payload.prefix(limit)))
            }
        }
        XCTAssertEqual(MetadataPolicy.overviewMax, 2000)
        XCTAssertEqual(MetadataPolicy.taglineMax, 200)
        XCTAssertEqual(MetadataPolicy.genreMax, 64)
        XCTAssertEqual(MetadataPolicy.nameMax, 200)
        XCTAssertEqual(MetadataPolicy.displayNameMax, 64)
        XCTAssertEqual(MetadataPolicy.imageMaxBytes, 20 * 1024 * 1024)
        XCTAssertEqual(MetadataPolicy.taglinesMax, 3)
        XCTAssertEqual(MetadataPolicy.genresMax, 10)
        XCTAssertEqual(MetadataPolicy.recentSearchesMax, 20)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
}
