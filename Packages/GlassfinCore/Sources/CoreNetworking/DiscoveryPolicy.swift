import CoreModels
import Foundation

/// UDP 7359 announcements are untrusted. The user picks the server; nothing connects on its own (S4.7).
public struct DiscoveryPresentation: Sendable, Equatable {
    public var url: URL
    public var host: String
    public var port: Int
    public var name: String
    public var id: String
    public var autoConnect: Bool
    public var idMismatch: Bool
    public var storedURL: URL?
    public var transport: ServerTransportPolicy.Verdict

    public init(
        url: URL,
        host: String,
        port: Int,
        name: String,
        id: String,
        autoConnect: Bool,
        idMismatch: Bool,
        storedURL: URL?,
        transport: ServerTransportPolicy.Verdict
    ) {
        self.url = url
        self.host = host
        self.port = port
        self.name = name
        self.id = id
        self.autoConnect = autoConnect
        self.idMismatch = idMismatch
        self.storedURL = storedURL
        self.transport = transport
    }
}

public enum DiscoveryPolicy {
    public static let maximumNameLength = 64
    public static let maximumIDLength = 64

    public static func parse(_ data: Data, storedURL: URL?, publicInfoID: String?) -> DiscoveryPresentation? {
        struct Packet: Decodable {
            var Address: String?
            var Id: String?
            var Name: String?
        }
        guard let packet = try? JSONDecoder().decode(Packet.self, from: data),
            let address = packet.Address,
            let rawURL = URL(string: address),
            let url = try? ServerAddress.canonical(rawURL),
            let host = url.host?.lowercased(),
            !host.isEmpty
        else { return nil }
        let port = url.port ?? defaultPort(url.scheme)
        guard let port else { return nil }
        let name = displayName(packet.Name ?? "")
        let id = String(displayName(packet.Id ?? "").prefix(maximumIDLength))
        let mismatch = publicInfoID.map { $0 != id } ?? false
        return DiscoveryPresentation(
            url: url,
            host: host,
            port: port,
            name: name,
            id: id,
            autoConnect: false,
            idMismatch: mismatch,
            storedURL: storedURL,
            transport: ServerTransportPolicy.evaluate(url)
        )
    }

    /// A stored server keeps the address the user saved. Discovery never rewrites it.
    public static func storedAddress(afterDiscovery stored: URL, packet: Data) -> URL {
        _ = parse(packet, storedURL: stored, publicInfoID: nil)
        return stored
    }

    static func displayName(_ raw: String) -> String {
        MetadataSanitizer.displayText(MetadataSanitizer.plainText(raw), limit: maximumNameLength)
    }

    private static func defaultPort(_ scheme: String?) -> Int? {
        switch scheme?.lowercased() {
        case "https":
            return 443
        case "http":
            return 80
        default:
            return nil
        }
    }
}
