#if canImport(ImageIO) && canImport(CoreGraphics)
    import CoreGraphics
    import CoreModels
    import CoreNetworking
    import CorePlayback
    import Foundation
    import ImageIO
    import XCTest

    final class TrickplayImageDecoderTests: XCTestCase {
        func testSpriteIsDownsampledAndCachedAndMemoryWarningEvictsIt() async throws {
            let decoder = TrickplayImageDecoder()
            let layout = try makeLayout()
            let resource = TrickplayTileResource(
                itemID: "11111111111111111111111111111111",
                mediaSourceID: "22222222222222222222222222222222", width: 256, index: 0)
            let bytes = try sprite(width: 512, height: 512)
            let image = try await decoder.image(data: bytes, resource: resource, layout: layout)
            XCTAssertEqual(image.width, 512)
            XCTAssertEqual(image.height, 512)
            XCTAssertEqual(image.cropping(to: CGRect(x: 256, y: 256, width: 256, height: 256))?.width, 256)
            // A hit does not reparse bytes. Clearing the cache must force validation again.
            let cached = try await decoder.image(data: Data(), resource: resource, layout: layout)
            XCTAssertTrue(image === cached)
            await decoder.removeAll()
            do {
                _ = try await decoder.image(data: Data(), resource: resource, layout: layout)
                XCTFail("Expected image validation after eviction")
            } catch {
                XCTAssertEqual(error as? ImageDataError, .invalidImage)
            }
        }

        func testWrongSpriteDimensionsAreRejectedBeforeThumbnailCreation() async throws {
            let decoder = TrickplayImageDecoder()
            let resource = TrickplayTileResource(
                itemID: "11111111111111111111111111111111",
                mediaSourceID: "22222222222222222222222222222222", width: 256, index: 0)
            do {
                _ = try await decoder.image(
                    data: sprite(width: 1024, height: 512), resource: resource, layout: makeLayout())
                XCTFail("Expected metadata dimension mismatch")
            } catch {
                XCTAssertEqual(error as? ImageDataError, .invalidImage)
            }
        }

        private func makeLayout() throws -> TrickplayLayout {
            let json = Data(
                "{\"Width\":256,\"Height\":256,\"TileWidth\":2,\"TileHeight\":2,\"ThumbnailCount\":4,\"Interval\":1000}"
                    .utf8)
            return try XCTUnwrap(TrickplayLayout(JSONDecoder().decode(TrickplayInfoDTO.self, from: json)))
        }

        private func sprite(width: Int, height: Int) throws -> Data {
            let context = try XCTUnwrap(
                CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            let image = try XCTUnwrap(context.makeImage())
            let bytes = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return bytes as Data
        }
    }
#endif
