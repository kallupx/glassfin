#if canImport(AVFoundation) && canImport(Security)
    import AVFoundation
    import CoreModels
    import CoreNetworking
    import Foundation
    import Security

    public final class PlaybackFetchGate: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        public init() {}

        public func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        public var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    /// Resource-loader session. AVPlayer is given a `glassfin-media` URL and no credential query.
    public final class AVPlayerMediaSession: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
        public let asset: AVURLAsset
        public let gate: PlaybackFetchGate
        private let origin: any MediaOriginClient
        private let authorizationHeader: String
        private let trust: ServerTrustClass
        private let allowedOrigin: URL
        private let onFailure: (@Sendable (APIError) -> Void)?
        private let failures = LoaderFailures()
        private let queue: DispatchQueue
        private let tasks = LoaderTasks()

        public init?(
            carrier: ResourceLoaderCarrier,
            origin: any MediaOriginClient,
            gate: PlaybackFetchGate = PlaybackFetchGate(),
            onFailure: (@Sendable (APIError) -> Void)? = nil
        ) {
            guard MediaOrigin.hasSchemeHostAndPort(carrier.originURL) else { return nil }
            self.origin = origin
            self.authorizationHeader = carrier.authorizationHeader
            self.trust = carrier.trust
            self.allowedOrigin = carrier.originURL
            self.onFailure = onFailure
            self.gate = gate
            self.queue = DispatchQueue(label: "org.glassfin.media-loader")
            self.asset = AVURLAsset(url: carrier.assetURL)
            super.init()
            asset.resourceLoader.setDelegate(self, queue: queue)
        }

        public func cancel() {
            gate.cancel()
            tasks.cancelAll()
        }

        public func resourceLoader(
            _ resourceLoader: AVAssetResourceLoader,
            shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
        ) -> Bool {
            guard !gate.isCancelled, let url = loadingRequest.request.url else { return false }
            let range = Self.byteRange(loadingRequest.dataRequest)
            guard
                let request = ResourceLoadPlanner.originRequest(
                    assetURL: url,
                    authorizationHeader: authorizationHeader,
                    trust: trust,
                    range: range,
                    allowedOrigin: allowedOrigin
                )
            else {
                loadingRequest.finishLoading(with: URLError(.badURL))
                return true
            }
            let boxed = LoaderBox(loadingRequest)
            let id = ObjectIdentifier(loadingRequest)
            let task = Task { [weak self] in
                guard let self else { return }
                defer { self.tasks.remove(id) }
                await self.load(boxed, request: request, range: range)
            }
            tasks.store(task, for: id)
            return true
        }

        /// Q8-2-09: route `.unauthorized` through `MediaUnauthorizedPolicy` before deciding to log out.
        public var lastFailure: APIError? { failures.last }

        public func resourceLoader(
            _ resourceLoader: AVAssetResourceLoader,
            didCancel loadingRequest: AVAssetResourceLoadingRequest
        ) {
            tasks.cancel(ObjectIdentifier(loadingRequest))
        }

        // Internal seam for exercising the loader and completion with a request sink in Apple-platform tests.
        func load(_ boxed: any MediaLoadingRequest, request: OriginMediaRequest, range: HTTPByteRange?) async {
            do {
                try await ChunkedMediaLoader.load(
                    request: request,
                    range: range,
                    client: origin,
                    isCancelled: { self.gate.isCancelled },
                    receive: { (reply: PlayerByteReply) async throws(APIError) in
                        try await self.respond(boxed, reply: reply)
                    }
                )
                await complete(boxed, error: nil)
            } catch {
                await complete(boxed, error: error)
            }
        }

        private func respond(_ boxed: any MediaLoadingRequest, reply: PlayerByteReply) async throws(APIError) {
            let delivered = await withCheckedContinuation { continuation in
                queue.async {
                    guard !self.gate.isCancelled, !boxed.isCancelled else {
                        continuation.resume(returning: false)
                        return
                    }
                    boxed.respond(with: reply)
                    continuation.resume(returning: true)
                }
            }
            if !delivered { throw .cancelled }
        }

        private func complete(_ boxed: any MediaLoadingRequest, error: APIError?) async {
            await withCheckedContinuation { continuation in
                queue.async {
                    let failure = self.gate.isCancelled || boxed.isCancelled ? .cancelled : error
                    if let failure {
                        self.failures.record(failure)
                    }
                    boxed.finishLoading(with: failure)
                    if let failure { self.onFailure?(failure) }
                    continuation.resume()
                }
            }
        }

        private static func byteRange(_ dataRequest: AVAssetResourceLoadingDataRequest?) -> HTTPByteRange? {
            guard let dataRequest else { return HTTPByteRange(start: 0, end: 1) }
            let end: Int64?
            if dataRequest.requestsAllDataToEndOfResource {
                end = nil
            } else {
                let length = Int64(dataRequest.requestedLength)
                end = length > 0 ? dataRequest.requestedOffset + length - 1 : dataRequest.requestedOffset
            }
            return HTTPByteRange(start: dataRequest.requestedOffset, end: end)
        }
    }

    public enum AVPlayerLogForwarder {
        public static func forward(item: AVPlayerItem, log: any GlassfinLog) {
            let errors = item.errorLog()?.events.map(\.uri) ?? []
            let access = item.accessLog()?.events.map(\.uri) ?? []
            PlayerLogSink.record(errors + access, log: log)
        }
    }

    public enum AVPlayerAssetBuilder {
        /// Undocumented header key. Does not apply a certificate pin.
        public static func asset(url: URL, authorizationHeader: String) -> AVURLAsset {
            #if DEBUG
                let headers = ["Authorization": authorizationHeader]
                return AVURLAsset(url: url, options: [ResolvedMediaURL.httpHeaderFieldsKey: headers])
            #else
                return AVURLAsset(url: url)
            #endif
        }
    }

    public final class URLSessionOriginClient: MediaOriginClient, @unchecked Sendable {
        private let session: URLSession
        private let delegate: MediaTrustDelegate
        private let trust: ServerTrustClass

        public init(trust: ServerTrustClass) {
            let delegate = MediaTrustDelegate(trust: trust)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.delegate = delegate
            self.trust = trust
            self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }

        deinit {
            session.invalidateAndCancel()
        }

        public func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse {
            var urlRequest = URLRequest(url: request.url)
            urlRequest.httpMethod = request.method
            if let header = request.authorizationHeader {
                urlRequest.setValue(header, forHTTPHeaderField: "Authorization")
            }
            if let range = request.range {
                urlRequest.setValue(range.headerValue, forHTTPHeaderField: "Range")
            }
            do {
                let (bytes, response) = try await session.bytes(for: urlRequest, delegate: delegate)
                defer { bytes.task.cancel() }
                guard let http = response as? HTTPURLResponse else { throw APIError.network }
                let location = http.value(forHTTPHeaderField: "Location").flatMap { raw in
                    URL(string: raw, relativeTo: request.url)?.absoluteURL
                }
                let contentType = http.value(forHTTPHeaderField: "Content-Type")
                var body = BoundedMediaBody(contentType: contentType, url: request.url, range: request.range)
                if request.method != "HEAD", (200..<300).contains(http.statusCode) {
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        try body.append(byte)
                    }
                }
                let data = body.data
                let total =
                    ContentRangeHeader.totalLength(of: http.value(forHTTPHeaderField: "Content-Range"))
                    ?? (http.statusCode == 200
                        ? (request.method == "HEAD" ? http.expectedContentLength : Int64(data.count)) : nil)
                return OriginMediaResponse(
                    status: http.statusCode,
                    location: location,
                    contentType: contentType,
                    body: data,
                    totalLength: total.flatMap { $0 >= 0 ? $0 : nil }
                )
            } catch let error as APIError {
                throw error
            } catch let error as URLError {
                throw URLErrorMapper.map(error)
            } catch is CancellationError {
                throw APIError.cancelled
            } catch {
                throw APIError.network
            }
        }
    }

    private final class MediaTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
        let trust: ServerTrustClass

        init(trust: ServerTrustClass) {
            self.trust = trust
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            handleChallenge(challenge, completionHandler: completionHandler)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            handleChallenge(challenge, completionHandler: completionHandler)
        }

        private func handleChallenge(
            _ challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.previousFailureCount == 0,
                challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                let serverTrust = challenge.protectionSpace.serverTrust
            else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            let observed = CertificateLeafFingerprint.sha256Hex(serverTrust)
            switch PinnedTrustGate.decide(trust: trust, observedFingerprintSHA256: observed) {
            case .performDefaultHandling:
                completionHandler(.performDefaultHandling, nil)
            case .allowPinned:
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            case .cancel:
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            // The resolver applies S4.6. Leaving the redirect to URLSession would skip that.
            completionHandler(nil)
        }
    }

    private enum CertificateLeafFingerprint {
        static func sha256Hex(_ trust: SecTrust) -> String? {
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
                return nil
            }
            let data = SecCertificateCopyData(leaf) as Data
            let hex = CertificateFingerprint.sha256Hex(data)
            return CertificateFingerprint.isValid(hex) ? hex : nil
        }
    }

    /// The AVFoundation adapter is only accessed on the session's resource-loader queue.
    protocol MediaLoadingRequest: Sendable {
        var isCancelled: Bool { get }
        func respond(with reply: PlayerByteReply)
        func finishLoading(with error: APIError?)
    }

    private final class LoaderBox: MediaLoadingRequest, @unchecked Sendable {
        let request: AVAssetResourceLoadingRequest
        init(_ request: AVAssetResourceLoadingRequest) { self.request = request }

        var isCancelled: Bool { request.isCancelled }

        func respond(with reply: PlayerByteReply) {
            if let info = request.contentInformationRequest {
                info.contentType = reply.contentTypeUTI
                info.contentLength = reply.contentLength
                info.isByteRangeAccessSupported = reply.isByteRangeAccessSupported
            }
            request.dataRequest?.respond(with: reply.data)
        }

        func finishLoading(with error: APIError?) {
            if let error {
                request.finishLoading(with: error)
            } else {
                request.finishLoading()
            }
        }
    }

    private final class LoaderFailures: @unchecked Sendable {
        private let lock = NSLock()
        private var failure: APIError?

        var last: APIError? {
            lock.lock()
            defer { lock.unlock() }
            return failure
        }

        func record(_ error: APIError) {
            lock.lock()
            failure = MediaFailurePrecedence.recording(error, after: failure)
            lock.unlock()
        }
    }

    private final class LoaderTasks: @unchecked Sendable {
        private let lock = NSLock()
        private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

        func store(_ task: Task<Void, Never>, for id: ObjectIdentifier) {
            lock.lock()
            tasks[id] = task
            lock.unlock()
        }

        func remove(_ id: ObjectIdentifier) {
            lock.lock()
            tasks.removeValue(forKey: id)
            lock.unlock()
        }

        func cancel(_ id: ObjectIdentifier) {
            lock.lock()
            let task = tasks.removeValue(forKey: id)
            lock.unlock()
            task?.cancel()
        }

        func cancelAll() {
            lock.lock()
            let all = tasks.values
            tasks.removeAll()
            lock.unlock()
            for task in all { task.cancel() }
        }
    }
#else
    import Foundation

    /// Linux stand-in so cancellation tests do not import AVFoundation.
    public final class PlaybackFetchGate: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        public init() {}

        public func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        public var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }
#endif
