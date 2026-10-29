#if canImport(AVFoundation) && canImport(Security)
    import AVFoundation
    import CoreModels
    import Foundation
    import XCTest

    @testable import CorePlayback

    final class HLSAssetRecognitionTests: XCTestCase {
        /// Exercise AVFoundation itself, rather than a substituted loading-request sink.
        /// A recognized master must reach its variant; that request ends at our mock.
        @MainActor
        func testNativePlayerRecognizesWrappedMasterAndRequestsVariant() async throws {
            let variantFetched = XCTestExpectation(description: "AVFoundation requested the HLS variant")
            let origin = RecognitionOrigin(variantFetched: variantFetched)
            let master = try XCTUnwrap(
                URL(string: "https://media.invalid/videos/item/master.m3u8?VideoCodec=h264&ApiKey=synthetic"))
            let plan = MediaOpenPlanner.plan(
                delivery: .serverHLS, resolvedURL: master, authorizationHeader: "synthetic-header",
                options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false))
            guard case .resourceLoader(let carrier) = plan.primary else { return XCTFail("Expected loader") }
            let session = try XCTUnwrap(AVPlayerMediaSession(carrier: carrier, origin: origin))
            let player = AVPlayer(playerItem: AVPlayerItem(asset: session.asset))
            defer {
                session.cancel()
                player.replaceCurrentItem(with: nil)
            }
            player.play()
            let result = await XCTWaiter.fulfillment(of: [variantFetched], timeout: 10)
            XCTAssertEqual(result, .completed)
            let requests = await origin.requests
            XCTAssertTrue(requests.contains { $0.url.lastPathComponent == "main.m3u8" })
            XCTAssertTrue(requests.allSatisfy { $0.authorizationHeader == nil })
            XCTAssertTrue(requests.allSatisfy { MediaCredentialQuery.contains($0.url) })
        }
    }

    private actor RecognitionOrigin: MediaOriginClient {
        let variantFetched: XCTestExpectation
        private(set) var requests: [OriginMediaRequest] = []

        init(variantFetched: XCTestExpectation) { self.variantFetched = variantFetched }

        func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse {
            requests.append(request)
            if request.url.lastPathComponent == "master.m3u8" {
                let playlist = """
                    #EXTM3U
                    #EXT-X-VERSION:7
                    #EXT-X-STREAM-INF:BANDWIDTH=2000000,CODECS="avc1.64001f,mp4a.40.2",RESOLUTION=1280x720
                    main.m3u8?VideoCodec=h264&ApiKey=synthetic
                    """
                return OriginMediaResponse(
                    status: 200, contentType: "application/vnd.apple.mpegurl", body: Data(playlist.utf8))
            }
            if request.url.lastPathComponent == "main.m3u8" { variantFetched.fulfill() }
            // Never offer a segment URL: this test cannot escape the in-memory origin.
            return OriginMediaResponse(status: 404)
        }
    }
#endif
