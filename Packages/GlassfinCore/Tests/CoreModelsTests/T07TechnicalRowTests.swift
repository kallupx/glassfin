import CoreModels
import Foundation
import XCTest

final class T07TechnicalRowTests: XCTestCase {
    /// T07-32/Q7-22: the first default video wins; range names are mapped to display labels.
    func testT07_32_defaultVideoResolutionAndHDRLabels() throws {
        for (name, resolution, hdr) in [
            ("video-hdr10", "4K", "HDR10"),
            ("video-hdr10plus", "1080p", "HDR10+"),
            ("video-dolby-vision", "4K", "Dolby Vision"),
            ("video-hlg", "1080p", "HLG"),
            ("video-sdr", "1080p", nil),
            ("video-unknown", "4K", nil),
        ] {
            let metadata = try metadata(named: name)
            let video = try XCTUnwrap(metadata.technicalStreams.first { $0.kind == "Video" })
            XCTAssertEqual(video.id, 2, name)
            XCTAssertEqual(video.resolutionLabel, resolution, name)
            XCTAssertEqual(video.hdrLabel, hdr, name)
            XCTAssertEqual(video.technicalLabel, [resolution, hdr].compactMap { $0 }.joined(separator: " · "), name)
            XCTAssertEqual(metadata.technicalStreams.filter { $0.kind == "Video" }.count, 1, name)
        }
        let fallback = try metadata(named: "video-fallback").technicalStreams.first { $0.kind == "Video" }
        XCTAssertEqual(fallback?.id, 1)
        XCTAssertEqual(fallback?.technicalLabel, "1080p")
    }

    /// T07-33: select default audio, falling back to the first audio when no default is flagged.
    func testT07_33_defaultAudioCodecAndChannelLabels() throws {
        for (name, label) in [
            ("audio-dts", "DTS-HD MA · 7.1"), ("audio-atmos", "Dolby Atmos"), ("audio-aac", "AAC · 2.0"),
        ] {
            let metadata = try metadata(named: name)
            let audio = try XCTUnwrap(metadata.technicalStreams.first { $0.kind == "Audio" })
            XCTAssertEqual(audio.id, 2, name)
            XCTAssertEqual(audio.technicalLabel, label, name)
            XCTAssertEqual(metadata.technicalStreams.filter { $0.kind == "Audio" }.count, 1, name)
            XCTAssertEqual(metadata.streams.filter { $0.kind == "Audio" }.count, 3, name)
        }
        let fallback = try metadata(named: "audio-fallback").technicalStreams.first { $0.kind == "Audio" }
        XCTAssertEqual(fallback?.id, 1)
        XCTAssertEqual(fallback?.technicalLabel, "AAC · 2.0")
    }

    /// T07-36/Q7-06: only the first source is projected, even with conflicting top-level streams.
    func testT07_36_multipleMediaSourcesUseOnlyTheFirstSourcesTechRow() throws {
        let dto = try fixture(named: "multiple-sources")
        XCTAssertEqual(dto.MediaSources?.count, 2)
        var firstOnly = dto
        firstOnly.MediaSources = dto.MediaSources.map { Array($0.prefix(1)) }
        // Additional versions introduce no version-selection state in the P0 presentation model.
        XCTAssertEqual(DTOMapper.mediaItem(dto, log: SilentLog()), DTOMapper.mediaItem(firstOnly, log: SilentLog()))
        let metadata = try metadata(named: "multiple-sources")
        XCTAssertEqual(metadata.streams.map(\.id), [10, 11, 12])
        XCTAssertEqual(metadata.technicalStreams.map(\.technicalLabel), ["1080p", "AAC · 2.0", "fin"])
        XCTAssertEqual(metadata.technicalStreams.map(\.id), [10, 11, 12])
    }

    private func metadata(named name: String) throws -> ItemMetadata {
        return try XCTUnwrap(DTOMapper.mediaItem(fixture(named: name), log: SilentLog())?.detail)
    }

    private func fixture(named name: String) throws -> BaseItemDTO {
        let fixtures = try JSONDecoder().decode([BaseItemDTO].self, from: Fixtures.data("m07-technical-items.json"))
        return try XCTUnwrap(fixtures.first { $0.Name == name })
    }
}
