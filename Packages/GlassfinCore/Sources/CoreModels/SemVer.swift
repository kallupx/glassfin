import Foundation

public struct SemVer: Sendable, Hashable, Comparable, Codable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(parsing raw: String) {
        let parts = raw.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
        let numbers = parts.prefix(3).compactMap { Int($0) }
        guard let major = numbers.first else { return nil }
        self.major = major
        self.minor = numbers.count > 1 ? numbers[1] : 0
        self.patch = numbers.count > 2 ? numbers[2] : 0
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// Assumed server floor until the user confirms 10.10 versus 10.11. 10.10.7 is the practical default.
    public static let minimumJellyfin = SemVer(major: 10, minor: 10, patch: 7)

    public var meetsMinimumServer: Bool { self >= .minimumJellyfin }
}
