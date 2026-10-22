#if canImport(AVFoundation) && canImport(CryptoKit) && canImport(Security)
    import AVFoundation
    import CoreModels
    import CryptoKit
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
        private let allowedHost: String
        private let queue: DispatchQueue
        private let tasks = LoaderTasks()

        public init?(
            carrier: ResourceLoaderCarrier,
            origin: any MediaOriginClient,
            gate: PlaybackFetchGate = PlaybackFetchGate()
        ) {
            guard let host = carrier.originURL.host else { return nil }
            self.origin = origin
            self.authorizationHeader = carrier.authorizationHeader
            self.trust = carrier.trust
            self.allowedHost = host
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
                    allowedHost: allowedHost
                )
            else {
                loadingRequest.finishLoading(with: URLError(.badURL))
                return true
            }
            let boxed = LoaderBox(loadingRequest)
            let task = Task { [weak self] in
                guard let self else { return }
                if self.gate.isCancelled {
                    boxed.request.finishLoading(with: URLError(.cancelled))
                    return
                }
                do {
                    let response = try await self.origin.fetch(request)
                    self.finish(boxed.request, response: response, url: request.url)
                } catch {
                    boxed.request.finishLoading(with: error)
                }
            }
            tasks.store(task, for: ObjectIdentifier(loadingRequest))
            return true
        }

        public func resourceLoader(
            _ resourceLoader: AVAssetResourceLoader,
            didCancel loadingRequest: AVAssetResourceLoadingRequest
        ) {
            tasks.cancel(ObjectIdentifier(loadingRequest))
        }

        private func finish(_ loadingRequest: AVAssetResourceLoadingRequest, response: OriginMediaResponse, url: URL) {
            let decision = MediaStatusPolicy.decide(status: response.status)
            queue.async {
                switch decision {
                case .bytes:
                    guard let reply = PlayerResponseBuilder.build(origin: response, requestURL: url) else {
                        loadingRequest.finishLoading(with: URLError(.cannotDecodeContentData))
                        return
                    }
                    if let info = loadingRequest.contentInformationRequest {
                        info.contentType = reply.contentTypeUTI
                        info.contentLength = reply.contentLength
                        info.isByteRangeAccessSupported = reply.isByteRangeAccessSupported
                    }
                    loadingRequest.dataRequest?.respond(with: reply.data)
                    loadingRequest.finishLoading()
                case .checkCurrentUser, .failed:
                    loadingRequest.finishLoading(with: URLError(.badServerResponse))
                }
            }
        }

        private static func byteRange(_ dataRequest: AVAssetResourceLoadingDataRequest?) -> HTTPByteRange? {
            guard let dataRequest else { return nil }
            if dataRequest.requestedOffset == 0 && dataRequest.requestsAllDataToEndOfResource {
                return nil
            }
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
            let headers = ["Authorization": authorizationHeader]
            return AVURLAsset(url: url, options: [ResolvedMediaURL.httpHeaderFieldsKey: headers])
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
                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else { throw APIError.network }
                let location = http.value(forHTTPHeaderField: "Location").flatMap { raw in
                    URL(string: raw, relativeTo: request.url)?.absoluteURL
                }
                let total =
                    ContentRangeHeader.totalLength(of: http.value(forHTTPHeaderField: "Content-Range"))
                    ?? ((200..<300).contains(http.statusCode) ? Int64(data.count) : nil)
                return OriginMediaResponse(
                    status: http.statusCode,
                    location: location,
                    contentType: http.value(forHTTPHeaderField: "Content-Type"),
                    body: data,
                    totalLength: total
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
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }

    private final class LoaderBox: @unchecked Sendable {
        let request: AVAssetResourceLoadingRequest
        init(_ request: AVAssetResourceLoadingRequest) { self.request = request }
    }

    private final class LoaderTasks: @unchecked Sendable {
        private let lock = NSLock()
        private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

        func store(_ task: Task<Void, Never>, for id: ObjectIdentifier) {
            lock.lock()
            tasks[id] = task
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
