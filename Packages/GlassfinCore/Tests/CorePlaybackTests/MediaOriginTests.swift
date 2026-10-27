import CorePlayback
import Foundation
import XCTest

final class MediaOriginTests: XCTestCase {
    /// T08-2-33. Scheme and host comparisons are case insensitive.
    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertTrue(matches("HTTPS://EXAMPLE.com/a", "https://example.COM/b"))
    }

    /// T08-2-50. IPv6 origins retain their host and port identity.
    func testIPv6Origins() {
        XCTAssertTrue(matches("http://[::1]:8096", "http://[::1]:8096"))
        XCTAssertFalse(matches("http://[::1]:8096", "http://[::1]:8097"))
        XCTAssertFalse(matches("http://[::1]:8096", "http://127.0.0.1:8096"))
    }

    /// T08-2-50. Current host comparison preserves a trailing dot, so these origins differ.
    func testTrailingDotIsNotNormalized() {
        XCTAssertFalse(matches("https://example.com./", "https://example.com/"))
    }

    /// T08-2-50. URL.host excludes userinfo; current origin comparison therefore accepts it.
    func testUserinfoDoesNotChangeOrigin() {
        XCTAssertTrue(matches("https://user:pw@example.com/", "https://example.com/"))
    }

    /// T08-2-33. Omitted ports match scheme defaults, but an explicit nondefault port differs.
    func testDefaultPorts() {
        XCTAssertTrue(matches("https://h", "https://h:443"))
        XCTAssertTrue(matches("http://h", "http://h:80"))
        XCTAssertFalse(matches("https://h:80", "https://h"))
    }

    /// T08-2-34. HTTP and HTTPS are different origins even with an identical explicit port.
    func testDifferentSchemesDoNotMatch() {
        XCTAssertFalse(matches("http://h", "https://h"))
        XCTAssertFalse(matches("http://h:443", "https://h:443"))
    }

    /// T08-2-31. HTTPS supplies the default port when validating a carrier origin.
    func testHTTPSHostHasSchemeHostAndPort() {
        XCTAssertTrue(MediaOrigin.hasSchemeHostAndPort(URL(string: "https://h")!))
    }

    /// T08-2-31. HTTP origins with an explicit port are valid carrier origins.
    func testHTTPWithPortHasSchemeHostAndPort() {
        XCTAssertTrue(MediaOrigin.hasSchemeHostAndPort(URL(string: "http://h:8096")!))
    }

    /// T08-2-31. Carrier validation requires a nonempty host.
    func testMissingHostIsRejected() {
        XCTAssertFalse(MediaOrigin.hasSchemeHostAndPort(URL(string: "https:///video")!))
        XCTAssertFalse(MediaOrigin.hasSchemeHostAndPort(URL(string: "/video")!))
    }

    /// T08-2-31. An unknown scheme cannot supply a default port.
    func testUnknownSchemeWithoutPortIsRejected() {
        XCTAssertFalse(MediaOrigin.hasSchemeHostAndPort(URL(string: "custom://h/video")!))
        // This helper uses the existing parts() logic; an explicit port is sufficient.
        XCTAssertTrue(MediaOrigin.hasSchemeHostAndPort(URL(string: "custom://h:123/video")!))
    }

    /// T08-2-31. A file URL is not a carrier origin, even when it has a host.
    func testFileURLIsRejected() {
        XCTAssertFalse(MediaOrigin.hasSchemeHostAndPort(URL(fileURLWithPath: "/video")))
        XCTAssertFalse(MediaOrigin.hasSchemeHostAndPort(URL(string: "file://h/video")!))
    }

    private func matches(_ lhs: String, _ rhs: String) -> Bool {
        MediaOrigin.matches(URL(string: lhs)!, URL(string: rhs)!)
    }
}
