import CoreModels
import CoreNetworking
import Foundation
import XCTest

@testable import CoreAPI

final class ClientPinTests: XCTestCase {
    func testFactoryPreservesPinForBoundedRequests() throws {
        let server = URL(string: "https://media.example/jellyfin")!
        let pin = OriginCertificatePin(url: server, sha256: String(repeating: "ab", count: 32))
        let identity = ClientIdentity(deviceName: "Test", deviceID: "test-device", version: "0.1.0")
        let client = JellyfinClientFactory.make(server: server, identity: identity, certificatePin: pin)
        #if canImport(JellyfinAPI)
            let sdk = try XCTUnwrap(client as? SDKJellyfinAPIClient)
            let http = sdk.boundedClient
        #else
            let http = try XCTUnwrap(client as? HTTPJellyfinClient)
        #endif
        defer { http.session.invalidateAndCancel() }
        XCTAssertEqual(http.certificatePin, pin)
        XCTAssertEqual(http.identity, identity)
        XCTAssertEqual(http.server, server)
    }

    func testFactoryWithoutPinKeepsDefaultTrustForBoundedRequests() throws {
        let server = URL(string: "https://media.example")!
        let identity = ClientIdentity(deviceName: "Test", deviceID: "test-device", version: "0.1.0")
        let client = JellyfinClientFactory.make(server: server, identity: identity)
        #if canImport(JellyfinAPI)
            let sdk = try XCTUnwrap(client as? SDKJellyfinAPIClient)
            let http = sdk.boundedClient
        #else
            let http = try XCTUnwrap(client as? HTTPJellyfinClient)
        #endif
        defer { http.session.invalidateAndCancel() }
        XCTAssertNil(http.certificatePin)
        XCTAssertEqual(http.identity, identity)
        XCTAssertEqual(http.server, server)
    }
}
