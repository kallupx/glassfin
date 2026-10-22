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

    /// Two or more numeric components. A missing patch becomes 0, so `10.10` is `10.10.0`.
    /// One component, or a non-numeric component, is unparseable. Pre-release and build
    /// suffixes (`-rc1`, `+meta`) are ignored.
    public init?(parsing raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let head: Substring
        if let marker = trimmed.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            head = trimmed[..<marker]
        } else {
            head = Substring(trimmed)
        }
        let parts = head.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let taken = parts.prefix(3)
        guard
            taken.allSatisfy({ part in
                !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
            })
        else { return nil }
        let numbers = taken.compactMap { Int($0) }
        guard numbers.count == taken.count, let major = numbers.first else { return nil }
        self.major = major
        self.minor = numbers.count > 1 ? numbers[1] : 0
        self.patch = numbers.count > 2 ? numbers[2] : 0
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// Lowest supported Jellyfin release. Compared on the numeric triple only.
    public static let minimumJellyfin = SemVer(major: 10, minor: 10, patch: 0)

    public var meetsMinimumServer: Bool { self >= .minimumJellyfin }
}
