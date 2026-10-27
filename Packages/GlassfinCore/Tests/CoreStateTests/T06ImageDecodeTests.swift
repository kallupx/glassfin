import CoreModels
import CoreState
import Foundation
import XCTest

final class T06ImageOptionsTests: XCTestCase {
    // T06-80: the production option dictionary uses displayed pixels and all thumbnail safety flags.
    func testT06_80_thumbnailOptionsUseDisplayedPixelsOnEveryPlatform() {
        for (width, height) in [(3840, 2160), (2000, 3000), (250, 375), (500, 750), (0, -1)] {
            let options = HomeImageDecoder.thumbnailOptions(width: width, height: height)
            XCTAssertEqual(options["kCGImageSourceThumbnailMaxPixelSize"] as? Int, max(1, max(width, height)))
            for key in [
                "kCGImageSourceCreateThumbnailFromImageAlways",
                "kCGImageSourceCreateThumbnailWithTransform",
                "kCGImageSourceShouldCacheImmediately",
            ] {
                XCTAssertEqual(options[key] as? Bool, true)
            }
            XCTAssertEqual(options.count, 4)
        }
    }
}

#if canImport(ImageIO) && canImport(CoreGraphics)
    import CoreGraphics
    import ImageIO

    final class T06ImageDecodeTests: XCTestCase {
        // T06-80: canonical spec/TESTPLAN-M06.md.
        func testT06_80_decoderDownsamplesToDisplayedPixelSize() async throws {
            for (width, height, displayedWidth, displayedHeight) in [(3840, 2160, 384, 216), (2000, 3000, 200, 300)] {
                let options = HomeImageDecoder.thumbnailOptions(width: displayedWidth, height: displayedHeight)
                XCTAssertEqual(
                    options[kCGImageSourceThumbnailMaxPixelSize as String] as? Int, max(displayedWidth, displayedHeight)
                )
                for key in [
                    kCGImageSourceCreateThumbnailFromImageAlways,
                    kCGImageSourceCreateThumbnailWithTransform,
                    kCGImageSourceShouldCacheImmediately,
                ] {
                    XCTAssertEqual(options[key as String] as? Bool, true)
                }
                let context = try XCTUnwrap(
                    CGContext(
                        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
                let source = try XCTUnwrap(context.makeImage())
                let bytes = NSMutableData()
                let destination = try XCTUnwrap(
                    CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
                CGImageDestinationAddImage(destination, source, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
                XCTAssertLessThan(bytes.length, MetadataPolicy.imageMaxBytes)
                let thumbnail = try await HomeImageDecoder.downsample(
                    bytes as Data, width: displayedWidth, height: displayedHeight)
                XCTAssertEqual(thumbnail.width, displayedWidth)
                XCTAssertEqual(thumbnail.height, displayedHeight)
            }
        }

        // T06-82: invalid compressed bytes fail without publishing a decoded image.
        func testT06_82_invalidImageFailsBeforePublishingBitmap() async {
            do {
                _ = try await HomeImageDecoder.downsample(Data([0, 1, 2]), width: 200, height: 300)
                XCTFail("Expected invalid image")
            } catch {
                XCTAssertEqual(error as? ImageDataError, .invalidImage)
            }
        }
    }
#endif
