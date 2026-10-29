import CoreModels
import CoreNetworking
import Foundation
import XCTest

@testable import CorePlayback

final class LivePlaybackRegressionTests: XCTestCase {
    // Jellyfin 10.11 HLS negotiation: a slash-relative master, session/codec options,
    // and a server credential. All identifiers and credentials here are synthetic.
    private let transcodingURL =
        "/videos/00112233-4455-6677-8899-aabbccddeeff/master.m3u8?"
        + "DeviceId=synthetic-device&MediaSourceId=00112233445566778899aabbccddeeff"
        + "&VideoCodec=h264&AudioCodec=aac&AudioStreamIndex=1&SubtitleStreamIndex=-1"
        + "&PlaySessionId=synthetic-session"
        + "&SegmentContainer=mp4&MinSegments=2&BreakOnNonKeyFrames=True"
        + "&TranscodeReasons=ContainerNotSupported"
        + "&" + "api" + "_key=synthetic%2bcredential"

    func testNegotiatedMasterHasVisibleHLSExtensionAndRoundTripsQuery() throws {
        for basePath in ["", "/jellyfin", "/jellyfin/"] {
            let server = try XCTUnwrap(URL(string: "https://media.example" + basePath))
            let original = try XCTUnwrap(
                MediaURLBuilder.resolveTranscodingURL(server: server, transcodingURL: transcodingURL))
            XCTAssertEqual(
                original.path,
                (basePath.isEmpty ? "" : "/jellyfin") + "/videos/00112233-4455-6677-8899-aabbccddeeff/master.m3u8")
            let clean = try MediaURLBuilder.negotiatedHLS(server: server, transcodingURL: transcodingURL)
            let asset = try XCTUnwrap(MediaAssetScheme.wrap(clean))
            XCTAssertEqual(asset.pathExtension, "m3u8")
            XCTAssertEqual(MediaAssetScheme.unwrap(asset), clean)
            XCTAssertFalse(asset.absoluteString.contains("credential"))
            let credentials = try XCTUnwrap(ServerHLSCredentialQuery(transcodingURL: original))
            let request = try XCTUnwrap(
                ResourceLoadPlanner.originRequest(
                    assetURL: asset, authorizationHeader: "synthetic-header", trust: .publiclyTrusted,
                    range: HTTPByteRange(start: 0, end: 1), allowedOrigin: server,
                    playlistCredentials: credentials))
            XCTAssertEqual(request.url, original)
            XCTAssertNil(request.authorizationHeader)
            XCTAssertNil(request.range)
        }
    }

    func testRewrittenVariantHasVisibleHLSExtensionAndKeepsNegotiation() throws {
        let server = try XCTUnwrap(URL(string: "https://media.example/jellyfin"))
        let master = try XCTUnwrap(
            MediaURLBuilder.resolveTranscodingURL(server: server, transcodingURL: transcodingURL))
        let variant = try XCTUnwrap(URL(string: "main.m3u8?" + (master.query ?? ""), relativeTo: master)?.absoluteURL)
        let playlist = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000\n" + variant.absoluteString
        let rewrite = try HLSPlaylistRewriter.rewrite(playlist: playlist, baseURL: master).get()
        let asset = try XCTUnwrap(URL(string: try XCTUnwrap(rewrite.playlist.split(separator: "\n").last).description))
        XCTAssertEqual(asset.pathExtension, "m3u8")
        XCTAssertEqual(MediaAssetScheme.unwrap(asset), MediaCredentialQuery.stripping(variant))
        XCTAssertFalse(rewrite.playlist.contains("credential"))
        let credentials = try XCTUnwrap(ServerHLSCredentialQuery(transcodingURL: master))
        let request = try XCTUnwrap(
            ResourceLoadPlanner.originRequest(
                assetURL: asset, authorizationHeader: "synthetic-header", trust: .publiclyTrusted,
                range: nil, allowedOrigin: server, playlistCredentials: credentials))
        XCTAssertEqual(request.url, variant)
        XCTAssertNil(request.authorizationHeader)
    }

    func testPlaylistNamedKeyStillUsesHeaderAndProgressiveURLsRoundTrip() throws {
        for (path, isKey) in [("key.m3u8?x=1", true), ("stream.mp4?x=1", false)] {
            let url = try XCTUnwrap(URL(string: "https://media.example/" + path))
            let asset = try XCTUnwrap(MediaAssetScheme.wrap(url, isKey: isKey))
            XCTAssertEqual(MediaAssetScheme.unwrap(asset), url)
            XCTAssertEqual(MediaAssetScheme.isKey(asset), isKey)
        }
    }
}
