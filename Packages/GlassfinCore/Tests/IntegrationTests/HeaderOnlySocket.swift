import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Minimal WebSocket client for the header-only Jellyfin `/socket` check.
/// Linux has no `URLSessionWebSocketTask`. The request URL must already carry the
/// Authorization header and must not carry an ApiKey query.
enum HeaderOnlySocket {
    struct Outcome: Equatable {
        var status: Int
        var frameCount: Int
        var sawKeepAlive: Bool
    }

    enum Failure: Error {
        case invalidURL
        case tlsUnsupported
        case system(Int32)
        case timeout
        case closed
    }

    static func open(_ request: URLRequest, wait: TimeInterval = 10) throws -> Outcome {
        guard let url = request.url, let host = url.host else { throw Failure.invalidURL }
        guard url.scheme == "ws" || url.scheme == "http" else { throw Failure.tlsUnsupported }
        let port = UInt16(url.port ?? 80)
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let path = (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?\($0)" } ?? "")
        let fd = try connectIPv4(host: host, port: port, timeout: wait)
        defer { close(fd) }
        let deadline = Date().addingTimeInterval(wait)
        var lines = [
            "GET \(path) HTTP/1.1",
            "Host: \(host):\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
            "Sec-WebSocket-Version: 13",
        ]
        if !authorization.isEmpty {
            lines.append("Authorization: \(authorization)")
        }
        let handshake = lines.joined(separator: "\r\n") + "\r\n\r\n"
        try sendAll(fd, Data(handshake.utf8), deadline: deadline)
        let (status, rest) = try readStatus(fd, deadline: deadline)
        if status != 101 {
            return Outcome(status: status, frameCount: 0, sawKeepAlive: false)
        }
        var buffer = rest
        var frames = 0
        while Date() < deadline && frames < 16 {
            let frame: Frame
            do {
                frame = try readFrame(fd, buffer: &buffer, deadline: deadline)
            } catch Failure.closed {
                break
            }
            frames += 1
            switch frame.opcode {
            case 0x1, 0x0:
                if let text = String(data: frame.payload, encoding: .utf8),
                    text.contains("KeepAlive")
                {
                    return Outcome(status: status, frameCount: frames, sawKeepAlive: true)
                }
            case 0x8:
                return Outcome(status: status, frameCount: frames, sawKeepAlive: false)
            case 0x9:
                try sendFrame(fd, opcode: 0xA, payload: frame.payload, deadline: deadline)
            default:
                break
            }
        }
        return Outcome(status: status, frameCount: frames, sawKeepAlive: false)
    }

    private struct Frame {
        var opcode: UInt8
        var payload: Data
    }

    private static func connectIPv4(host: String, port: UInt16, timeout: TimeInterval) throws -> Int32 {
        #if os(Linux)
            let streamType = Int32(SOCK_STREAM.rawValue)
        #else
            let streamType = SOCK_STREAM
        #endif
        let fd = socket(AF_INET, streamType, 0)
        if fd < 0 { throw Failure.system(errno) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        let parsed = host.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        if parsed != 1 {
            close(fd)
            throw Failure.invalidURL
        }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc < 0 && errno != EINPROGRESS {
            let error = errno
            close(fd)
            throw Failure.system(error)
        }
        let deadline = Date().addingTimeInterval(timeout)
        do {
            try waitIO(fd, events: Int16(POLLOUT), deadline: deadline)
        } catch {
            close(fd)
            throw error
        }
        var soError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        _ = withUnsafeMutablePointer(to: &soError) {
            getsockopt(fd, SOL_SOCKET, SO_ERROR, $0, &length)
        }
        if soError != 0 {
            close(fd)
            throw Failure.system(soError)
        }
        return fd
    }

    private static func readStatus(_ fd: Int32, deadline: Date) throws -> (Int, Data) {
        var buffer = Data()
        while Date() < deadline {
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = buffer[..<range.lowerBound]
                let rest = buffer[range.upperBound...]
                let text = String(decoding: head, as: UTF8.self)
                let line = text.split(separator: "\r\n", maxSplits: 1).first ?? ""
                let parts = line.split(separator: " ")
                let status = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                return (status, Data(rest))
            }
            buffer.append(try readSome(fd, deadline: deadline))
        }
        throw Failure.timeout
    }

    private static func readFrame(_ fd: Int32, buffer: inout Data, deadline: Date) throws -> Frame {
        let header = try readExact(fd, buffer: &buffer, count: 2, deadline: deadline)
        let opcode = header[0] & 0x0F
        let masked = (header[1] & 0x80) != 0
        var length = Int(header[1] & 0x7F)
        if length == 126 {
            let ext = try readExact(fd, buffer: &buffer, count: 2, deadline: deadline)
            length = (Int(ext[0]) << 8) | Int(ext[1])
        } else if length == 127 {
            let ext = try readExact(fd, buffer: &buffer, count: 8, deadline: deadline)
            length = 0
            for byte in ext { length = (length << 8) | Int(byte) }
        }
        var maskKey = Data()
        if masked {
            maskKey = try readExact(fd, buffer: &buffer, count: 4, deadline: deadline)
        }
        var payload = try readExact(fd, buffer: &buffer, count: length, deadline: deadline)
        if masked {
            for index in payload.indices {
                payload[index] ^= maskKey[payload.distance(from: payload.startIndex, to: index) % 4]
            }
        }
        return Frame(opcode: opcode, payload: payload)
    }

    private static func sendFrame(_ fd: Int32, opcode: UInt8, payload: Data, deadline: Date) throws {
        var packet = Data([0x80 | opcode])
        let mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        if payload.count < 126 {
            packet.append(0x80 | UInt8(payload.count))
        } else {
            packet.append(0x80 | 126)
            packet.append(UInt8((payload.count >> 8) & 0xFF))
            packet.append(UInt8(payload.count & 0xFF))
        }
        packet.append(contentsOf: mask)
        for (index, byte) in payload.enumerated() {
            packet.append(byte ^ mask[index % 4])
        }
        try sendAll(fd, packet, deadline: deadline)
    }

    private static func readExact(_ fd: Int32, buffer: inout Data, count: Int, deadline: Date) throws -> Data {
        while buffer.count < count {
            buffer.append(try readSome(fd, deadline: deadline))
        }
        let chunk = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(chunk)
    }

    private static func readSome(_ fd: Int32, deadline: Date) throws -> Data {
        try waitIO(fd, events: Int16(POLLIN), deadline: deadline)
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = bytes.withUnsafeMutableBytes { recv(fd, $0.baseAddress, 4096, 0) }
        if count == 0 { throw Failure.closed }
        if count < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK { return Data() }
            throw Failure.system(errno)
        }
        return Data(bytes.prefix(count))
    }

    private static func sendAll(_ fd: Int32, _ data: Data, deadline: Date) throws {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            try waitIO(fd, events: Int16(POLLOUT), deadline: deadline)
            let sent = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return send(fd, base.advanced(by: offset), bytes.count - offset, 0)
            }
            if sent < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { continue }
                throw Failure.system(errno)
            }
            if sent == 0 { throw Failure.closed }
            offset += sent
        }
    }

    private static func waitIO(_ fd: Int32, events: Int16, deadline: Date) throws {
        let remain = deadline.timeIntervalSinceNow
        if remain <= 0 { throw Failure.timeout }
        var state = pollfd(fd: fd, events: events, revents: 0)
        let milliseconds = Int32(min(remain * 1000, Double(Int32.max)))
        let ready = poll(&state, 1, milliseconds)
        if ready == 0 { throw Failure.timeout }
        if ready < 0 { throw Failure.system(errno) }
    }
}
