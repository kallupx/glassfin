import CoreModels
import Foundation
import XCTest

final class T09MVPCardTests: XCTestCase {
    /// T09-35: movie and series posters include the release year when supplied.
    func testT09_35_posterTitleIncludesYearAndHandlesMissingYear() {
        for kind in [MediaKind.movie, .series] {
            var item = MediaItem(id: "poster", kind: kind, name: "<b>Star</b>", productionYear: 2026)
            XCTAssertEqual(item.searchCardTitle, "<b>Star</b> (2026)")
            item.productionYear = nil
            XCTAssertEqual(item.searchCardTitle, "<b>Star</b>")
        }
    }

    /// T09-36: SeriesName survives the API mapper and reaches the episode card label.
    func testT09_36_episodeTitleIncludesSeriesSeasonEpisodeAndName() throws {
        let data = Data(
            """
            {"Id":"episode","Type":"Episode","Name":"The arrival","SeriesName":"Star voyagers",
             "ParentIndexNumber":2,"IndexNumber":3}
            """.utf8)
        let dto = try JSONDecoder().decode(BaseItemDTO.self, from: data)
        let item = try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
        XCTAssertEqual(item.seriesName, "Star voyagers")
        XCTAssertEqual(item.searchCardTitle, "Star voyagers · S2E3 · The arrival")
        let restored = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored.searchCardTitle, item.searchCardTitle)
    }

    /// T09-36: absent episode metadata does not invent a season, episode or series.
    func testT09_36_missingEpisodeMetadataKeepsTheEpisodeName() {
        var item = MediaItem(id: "episode", kind: .episode, name: "Arrival")
        XCTAssertEqual(item.searchCardTitle, "Arrival")
        item.seriesName = "Voyagers"
        item.indexNumber = 3
        XCTAssertEqual(item.searchCardTitle, "Voyagers · Arrival")
        item.parentIndexNumber = 0
        XCTAssertEqual(item.searchCardTitle, "Voyagers · S0E3 · Arrival")
    }

    /// T09-64: newly displayed SeriesName obeys S6.1 at both DTO and cached-item boundaries.
    func testT09_64_seriesNameIsLiteralCleanedAndBoundedByGraphemes() throws {
        for length in [MetadataPolicy.nameMax - 1, MetadataPolicy.nameMax, MetadataPolicy.nameMax + 1] {
            let raw = "\u{202E}\u{0000}" + String(repeating: "👩🏽‍🚀", count: length)
            let expected = String(repeating: "👩🏽‍🚀", count: min(length, MetadataPolicy.nameMax))
            let data = try JSONSerialization.data(withJSONObject: [
                "Id": "episode", "Type": "Episode", "Name": "**Arrival**", "SeriesName": raw,
            ])
            let dto = try JSONDecoder().decode(BaseItemDTO.self, from: data)
            let mapped = try XCTUnwrap(DTOMapper.mediaItem(dto, log: SilentLog()))
            XCTAssertEqual(mapped.seriesName, expected)
            let cached = MediaItem(id: "episode", kind: .episode, name: "**Arrival**", seriesName: raw)
            XCTAssertEqual(cached.searchDisplayItem.seriesName, expected)
        }
        let literal = MediaItem(
            id: "episode", kind: .episode, name: "**Arrival**", seriesName: "<b>Voyagers</b> &amp; [link](x)")
        XCTAssertEqual(literal.searchCardTitle, "<b>Voyagers</b> &amp; [link](x) · **Arrival**")
    }
}
