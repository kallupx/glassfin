import CoreGraphics
import Foundation

/// BlurHash decoder (Wolt algorithm). Used as the opaque poster placeholder.
enum BlurHash {
    private static let alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
    )

    static func image(from hash: String, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else {
            return nil
        }
        guard let factors = factors(from: hash) else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let numX = factors.numX
        let numY = factors.numY
        for y in 0..<height {
            for x in 0..<width {
                var red = 0.0
                var green = 0.0
                var blue = 0.0
                for j in 0..<numY {
                    for i in 0..<numX {
                        let basis = cos(Double.pi * Double(x) * Double(i) / Double(width))
                            * cos(Double.pi * Double(y) * Double(j) / Double(height))
                        let color = factors.colors[i + j * numX]
                        red += color.r * basis
                        green += color.g * basis
                        blue += color.b * basis
                    }
                }
                let offset = (y * width + x) * 4
                pixels[offset] = quantize(red)
                pixels[offset + 1] = quantize(green)
                pixels[offset + 2] = quantize(blue)
                pixels[offset + 3] = 255
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private struct Factors {
        var numX: Int
        var numY: Int
        var colors: [(r: Double, g: Double, b: Double)]
    }

    private static func factors(from hash: String) -> Factors? {
        let characters = Array(hash)
        guard characters.count >= 6, let sizeFlag = decode83(characters, 0, 1) else {
            return nil
        }
        let numY = sizeFlag / 9 + 1
        let numX = sizeFlag % 9 + 1
        let expected = 4 + 2 * numX * numY
        guard characters.count == expected, let quantisedMaximum = decode83(characters, 1, 1) else {
            return nil
        }
        let maximumValue = Double(quantisedMaximum + 1) / 166
        guard let dc = decode83(characters, 2, 4) else {
            return nil
        }
        var colors: [(r: Double, g: Double, b: Double)] = [decodeDC(dc)]
        for index in 1..<(numX * numY) {
            let start = 4 + index * 2
            guard let ac = decode83(characters, start, 2) else {
                return nil
            }
            colors.append(decodeAC(ac, maximumValue: maximumValue))
        }
        return Factors(numX: numX, numY: numY, colors: colors)
    }

    private static func decode83(_ characters: [Character], _ start: Int, _ length: Int) -> Int? {
        guard start >= 0, length > 0, start + length <= characters.count else {
            return nil
        }
        var value = 0
        for offset in 0..<length {
            guard let digit = alphabet.firstIndex(of: characters[start + offset]) else {
                return nil
            }
            value = value * 83 + digit
        }
        return value
    }

    private static func decodeDC(_ value: Int) -> (r: Double, g: Double, b: Double) {
        let red = Double((value >> 16) & 255) / 255
        let green = Double((value >> 8) & 255) / 255
        let blue = Double(value & 255) / 255
        return (sRGBToLinear(red), sRGBToLinear(green), sRGBToLinear(blue))
    }

    private static func decodeAC(_ value: Int, maximumValue: Double) -> (r: Double, g: Double, b: Double) {
        let quantR = value / (19 * 19)
        let quantG = (value / 19) % 19
        let quantB = value % 19
        return (
            signPow((Double(quantR) - 9) / 9, 2) * maximumValue,
            signPow((Double(quantG) - 9) / 9, 2) * maximumValue,
            signPow((Double(quantB) - 9) / 9, 2) * maximumValue
        )
    }

    private static func signPow(_ value: Double, _ exponent: Double) -> Double {
        let magnitude = pow(abs(value), exponent)
        return value < 0 ? -magnitude : magnitude
    }

    private static func sRGBToLinear(_ value: Double) -> Double {
        if value <= 0.04045 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }

    private static func linearToSRGB(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        if clamped <= 0.0031308 {
            return clamped * 12.92
        }
        return 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    private static func quantize(_ linear: Double) -> UInt8 {
        UInt8(min(255, max(0, linearToSRGB(linear) * 255 + 0.5)))
    }
}
