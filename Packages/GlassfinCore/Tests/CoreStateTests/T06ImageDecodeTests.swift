#if canImport(ImageIO) && canImport(CoreGraphics)
    import CoreGraphics
    import CoreModels
    import CoreState
    import Foundation
    import ImageIO
    import XCTest

    final class T06ImageDecodeTests: XCTestCase {
        func testT06_22_decoderDownsamplesToDisplayedPixelSize() async throws {
            let context = try XCTUnwrap(
                CGContext(
                    data: nil, width: 1600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            let source = try XCTUnwrap(context.makeImage())
            let bytes = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, source, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            XCTAssertLessThan(bytes.length, MetadataPolicy.imageMaxBytes)
            let thumbnail = try await HomeImageDecoder.downsample(bytes as Data, width: 200, height: 100)
            XCTAssertEqual(thumbnail.width, 200)
            XCTAssertEqual(thumbnail.height, 100)
        }
    }
#endif
