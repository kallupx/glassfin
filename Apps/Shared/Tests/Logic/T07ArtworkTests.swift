import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import Glassfin

@MainActor
final class T07ArtworkTests: XCTestCase {
    func testT07_25_artworkIsDownsampledToDisplayedPixels() async throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 2048, height: 2048, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2048, height: 2048))
        let source = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, source, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let decoded = await LibraryArtworkDecoder.downsample(bytes as Data, pixels: 250)
        let thumbnail = try XCTUnwrap(decoded?.value)
        XCTAssertLessThanOrEqual(thumbnail.width, 250)
        XCTAssertLessThanOrEqual(thumbnail.height, 250)
    }
}
