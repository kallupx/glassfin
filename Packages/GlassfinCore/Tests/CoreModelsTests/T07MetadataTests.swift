import CoreModels
import Foundation
import XCTest

final class T07MetadataTests: XCTestCase {
    func testT07_20_metadataKeepsMarkupLiteralAndStripsControlsAndBidi() throws {
        let dto = try JSONDecoder().decode(
            BaseItemDTO.self,
            from: Data(#"{"Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Name":"<b>x</b>\u202e\u0007","Overview":"&amp; **x** <a href='x'>x</a>\u2066","People":[{"Name":"A\u202e","Role":"R\u0000"}],"Studios":[{"Name":"S\u202e"}]}"#.utf8))
        let item = try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
        XCTAssertEqual(item.name, "<b>x</b>")
        XCTAssertEqual(item.overview, "&amp; **x** <a href='x'>x</a>")
        XCTAssertEqual(item.detail?.people.first?.name, "A")
        XCTAssertEqual(item.detail?.people.first?.role, "R")
        XCTAssertEqual(item.detail?.studios.first, "S")
    }

    func testT07_21_limitsCountExtendedGraphemesAfterCleaning() {
        let glyph = "👩‍👩‍👧‍👦e\u{0301}"
        let long = String(repeating: glyph + "\u{202E}\u{0007}", count: MetadataPolicy.overviewMax)
        let item = MediaItem(
            id: "a", kind: .movie, name: long, overview: long,
            detail: ItemMetadata(
                taglines: Array(repeating: long, count: MetadataPolicy.taglinesMax + 1),
                genres: Array(repeating: long, count: MetadataPolicy.genresMax + 1),
                people: [ItemPerson(name: long, role: long)], studios: [long]))
            .cleanedForDisplay()
        XCTAssertEqual(item.name.count, MetadataPolicy.nameMax)
        XCTAssertEqual(item.overview?.count, MetadataPolicy.overviewMax)
        XCTAssertEqual(item.detail?.taglines.count, MetadataPolicy.taglinesMax)
        XCTAssertEqual(item.detail?.taglines.first?.count, MetadataPolicy.taglineMax)
        XCTAssertEqual(item.detail?.genres.count, MetadataPolicy.genresMax)
        XCTAssertEqual(item.detail?.genres.first?.count, MetadataPolicy.genreMax)
        XCTAssertEqual(item.detail?.people.first?.name.count, MetadataPolicy.nameMax)
        XCTAssertEqual(item.detail?.studios.first?.count, MetadataPolicy.nameMax)
        XCTAssertEqual(item.name, String(String(repeating: glyph, count: MetadataPolicy.nameMax).prefix(MetadataPolicy.nameMax)))
        XCTAssertEqual(MetadataPolicy.clean(long, limit: 0), "")
    }

    func testT07_17_technicalFixtureShowsHDRDVAndLosslessAudio() throws {
        let dto = try JSONDecoder().decode(
            BaseItemDTO.self,
            from: Data(#"{"Id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Name":"Film","MediaStreams":[{"Index":0,"Type":"Video","Width":3840,"Height":2160,"VideoRangeType":"HDR10","DvProfile":8},{"Index":1,"Type":"Audio","Codec":"DTS-HD MA","Channels":8},{"Index":2,"Type":"Subtitle","Language":"fin"}]}"#.utf8))
        let item = try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
        XCTAssertEqual(item.detail?.streams.map(\.technicalValue), ["3840 × 2160 · HDR10 · DV P8", "DTS-HD MA · 7.1", "fin"])
    }
}
