import CoreModels
import Foundation

#if canImport(os)
    import os
#endif

public struct GlassfinLogger: GlassfinLog {
    #if canImport(os)
        private let logger: Logger
    #endif

    public init(subsystem: String = "org.glassfin.app", category: String = "core") {
        #if canImport(os)
            logger = Logger(subsystem: subsystem, category: category)
        #endif
    }

    public func warning(_ message: String) {
        emit(SensitiveRedactor.redact(message), level: "warning", publicPrivacy: false)
    }

    public func debug(_ message: String) {
        emit(SensitiveRedactor.redact(message), level: "debug", publicPrivacy: false)
    }

    public func error(_ message: String) {
        emit(SensitiveRedactor.redact(message), level: "error", publicPrivacy: false)
    }

    /// Server name and version may be public, but the text is still redacted first.
    public func infoPublic(_ message: String) {
        emit(SensitiveRedactor.redact(message), level: "info", publicPrivacy: true)
    }

    private func emit(_ redacted: String, level: String, publicPrivacy: Bool) {
        #if canImport(os)
            switch level {
            case "warning":
                logger.warning("\(redacted, privacy: .private)")
            case "debug":
                logger.debug("\(redacted, privacy: .private)")
            case "error":
                logger.error("\(redacted, privacy: .private)")
            default:
                if publicPrivacy {
                    logger.info("\(redacted, privacy: .public)")
                } else {
                    logger.info("\(redacted, privacy: .private)")
                }
            }
        #else
            // Unified logging is unavailable on Linux. Write the already-redacted line
            // to stderr so the CI source scan does not have to allow console dumps.
            let visibility = publicPrivacy ? "public" : "private"
            let line = "[\(level) \(visibility)] \(redacted)\n"
            FileHandle.standardError.write(Data(line.utf8))
        #endif
    }
}
