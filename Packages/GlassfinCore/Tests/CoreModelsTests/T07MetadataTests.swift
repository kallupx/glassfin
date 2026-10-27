import CoreModels
import Foundation
import XCTest

final class T07MetadataTests: XCTestCase {
    /// T07-77: clean before truncating at limit-1, limit and limit+1, in grapheme clusters.
    func testT07_77_metadataBoundariesAndDisplayNamesUseTheSharedConstants() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example"))
        let version = SemVer(major: 12, minor: 2, patch: 0)
        for glyph in ["👩‍👩‍👧‍👦", "e\u{0301}"] {
            for limit in [
                MetadataPolicy.overviewMax, MetadataPolicy.taglineMax, MetadataPolicy.genreMax, MetadataPolicy.nameMax,
                MetadataPolicy.displayNameMax,
            ] {
                for count in [limit - 1, limit, limit + 1] {
                    let raw = String(repeating: glyph + "\u{0000}\u{202E}\u{200F}", count: count)
                    let expected = String(repeating: glyph, count: min(count, limit))
                    XCTAssertEqual(MetadataPolicy.clean(raw, limit: limit), expected)
                    if limit == MetadataPolicy.displayNameMax {
                        XCTAssertEqual(ServerInfo(id: "s", name: raw, url: url, version: version).name, expected)
                        XCTAssertEqual(PublicUser(id: "u", name: raw).name, expected)
                    }
                    if limit == MetadataPolicy.nameMax {
                        let item = MediaItem(id: "item", kind: .episode, name: raw, officialRating: raw)
                            .cleanedForDisplay()
                        XCTAssertEqual(item.name, expected)
                        XCTAssertEqual(item.officialRating, expected)
                        XCTAssertEqual(ItemPerson(name: raw, role: raw).role, expected)
                        XCTAssertEqual(ItemMetadata(studios: [raw]).studios, [expected])
                        XCTAssertEqual(ItemStream(id: 0, kind: "Video", title: raw).title, expected)
                    }
                }
            }
        }
        let literal = "<b>x</b> <script>y</script> &amp; **x** [x](https://example.com)"
        let metadata = ItemMetadata(
            taglines: Array(repeating: literal, count: 15), genres: Array(repeating: literal, count: 40))
        XCTAssertEqual(metadata.taglines, Array(repeating: literal, count: MetadataPolicy.taglinesMax))
        XCTAssertEqual(metadata.genres, Array(repeating: literal, count: MetadataPolicy.genresMax))
        XCTAssertEqual(MetadataSanitizer.plainText(literal), literal)
        XCTAssertEqual(MetadataPolicy.recentSearchesMax, 20)
        XCTAssertEqual(MetadataPolicy.imageMaxBytes, 20 * 1024 * 1024)
    }

    /// T07-77: canonical spec/TESTPLAN-M07.md.
    func testT07_77_metadataKeepsMarkupLiteralAndStripsControlsAndBidi() throws {
        let dto = try JSONDecoder().decode(
            BaseItemDTO.self,
            from: Data(
                #"{"Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Name":"<b>x</b>\u202e\u0007","Overview":"&amp; **x** <a href='x'>x</a>\u2066","People":[{"Name":"A\u202e","Role":"R\u0000"}],"Studios":[{"Name":"S\u202e"}]}"#
                    .utf8))
        let item = try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
        XCTAssertEqual(item.name, "<b>x</b>")
        XCTAssertEqual(item.overview, "&amp; **x** <a href='x'>x</a>")
        XCTAssertEqual(item.detail?.people.first?.name, "A")
        XCTAssertEqual(item.detail?.people.first?.role, "R")
        XCTAssertEqual(item.detail?.studios.first, "S")
    }

    /// T07-77: canonical spec/TESTPLAN-M07.md.
    func testT07_77_limitsCountExtendedGraphemesAfterCleaning() {
        let glyph = "👩‍👩‍👧‍👦e\u{0301}"
        let long = String(repeating: glyph + "\u{202E}\u{0007}", count: MetadataPolicy.overviewMax)
        let item = MediaItem(
            id: "a", kind: .movie, name: long, overview: long,
            detail: ItemMetadata(
                taglines: Array(repeating: long, count: MetadataPolicy.taglinesMax + 1),
                genres: Array(repeating: long, count: MetadataPolicy.genresMax + 1),
                people: [ItemPerson(name: long, role: long)], studios: [long])
        )
        .cleanedForDisplay()
        XCTAssertEqual(item.name.count, MetadataPolicy.nameMax)
        XCTAssertEqual(item.overview?.count, MetadataPolicy.overviewMax)
        XCTAssertEqual(item.detail?.taglines.count, MetadataPolicy.taglinesMax)
        XCTAssertEqual(item.detail?.taglines.first?.count, MetadataPolicy.taglineMax)
        XCTAssertEqual(item.detail?.genres.count, MetadataPolicy.genresMax)
        XCTAssertEqual(item.detail?.genres.first?.count, MetadataPolicy.genreMax)
        XCTAssertEqual(item.detail?.people.first?.name.count, MetadataPolicy.nameMax)
        XCTAssertEqual(item.detail?.studios.first?.count, MetadataPolicy.nameMax)
        XCTAssertEqual(
            item.name, String(String(repeating: glyph, count: MetadataPolicy.nameMax).prefix(MetadataPolicy.nameMax)))
        XCTAssertEqual(MetadataPolicy.clean(long, limit: 0), "")
    }

    /// T07-35: canonical spec/TESTPLAN-M07.md.
    func testT07_35_technicalFixtureShowsHDRDVAndLosslessAudio() throws {
        let dto = try JSONDecoder().decode(
            BaseItemDTO.self,
            from: Data(
                #"{"Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Name":"Film","MediaStreams":[{"Index":0,"Type":"Video","Width":3840,"Height":2160,"VideoRangeType":"HDR10","DvProfile":8},{"Index":1,"Type":"Audio","Codec":"dts","Profile":"DTS-HD MA","Channels":8},{"Index":2,"Type":"Subtitle","Language":"fin"}]}"#
                    .utf8))
        let item = try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
        XCTAssertEqual(
            item.detail?.streams.map(\.technicalValue), ["3840 × 2160 · HDR10 · DV P8", "DTS-HD MA · 7.1", "fin"])
    }
}
