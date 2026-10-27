import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices

/// Production authentication calls. Quick Connect secrets stay inside ``QuickConnectSecret``
/// once ``AuthFlow`` receives them. This type does not log tokens or passwords.
public struct LiveAuthBackend: AuthBackend {
    public var secureStore: any SecureStore
    public var log: any GlassfinLog
    public var probeClient: any ServerCandidateClient
    public var clock: any GlassfinClock
    public var pins: (any CertificatePinStore)?
    private let clientOverride: (any JellyfinAPIClient)?

    public init(
        secureStore: any SecureStore,
        log: any GlassfinLog = SilentLog(),
        probeClient: any ServerCandidateClient = URLSessionPublicInfoClient(),
        clock: any GlassfinClock = SystemGlassfinClock(),
        client: (any JellyfinAPIClient)? = nil,
        pins: (any CertificatePinStore)? = nil
    ) {
        self.secureStore = secureStore
        self.log = log
        self.probeClient = probeClient
        self.clock = clock
        self.clientOverride = client
        self.pins = pins
    }

    public func probe(_ address: String, certificatePin: OriginCertificatePin? = nil) async -> ServerProbeOutcome {
        await ServerProbe(client: probeClient, clock: clock).run(address: address, certificatePin: certificatePin)
    }

    public func quickConnectEnabled(on server: ServerInfo) async throws(APIError) -> Bool {
        try await service(for: server, token: nil).quickConnectEnabled()
    }

    public func beginQuickConnect(on server: ServerInfo) async throws(APIError) -> QuickConnectChallenge {
        try await service(for: server, token: nil).initiateQuickConnect()
    }

    public func pollQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError) -> Bool {
        let challenge = try await service(for: server, token: nil).quickConnectState(secret: secret.reveal())
        return challenge.authenticated
    }

    public func signIn(on server: ServerInfo, username: String, password: String) async throws(APIError)
        -> AuthenticatedSession
    {
        let auth = try await service(for: server, token: nil).authenticate(username: username, password: password)
        return adopting(server, auth: auth)
    }

    public func finishQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError)
        -> AuthenticatedSession
    {
        let auth = try await service(for: server, token: nil).authenticate(quickConnectSecret: secret.reveal())
        return adopting(server, auth: auth)
    }

    public func currentUser(on server: ServerInfo, token: String) async throws(APIError) -> UserSession {
        try await service(for: server, token: token).currentUser()
    }

    public func publicUsers(on server: ServerInfo) async throws(APIError) -> [PublicUser] {
        try await service(for: server, token: nil).publicUsers()
    }

    public func postCapabilities(on server: ServerInfo, token: String) async throws(APIError) {
        try await service(for: server, token: token).postCapabilities(
            playableMediaTypes: ["Video", "Audio"],
            supportsMediaControl: false
        )
    }

    public func logout(on server: ServerInfo, token: String) async throws(APIError) {
        try await service(for: server, token: token).logout()
    }

    private func adopting(_ server: ServerInfo, auth: AuthenticatedSession) -> AuthenticatedSession {
        var session = auth.session
        session.server = server
        return AuthenticatedSession(session: session, accessToken: auth.accessToken)
    }

    private func service(for server: ServerInfo, token: String?) throws(APIError) -> JellyfinAuthenticationService {
        let client = try makeClient(for: server, token: token)
        return JellyfinAuthenticationService(
            client: client, server: server.url, serverName: server.name, knownServer: server)
    }

    func makeClient(for server: ServerInfo, token: String?) throws(APIError) -> any JellyfinAPIClient {
        let deviceID: String
        do {
            deviceID = try DeviceIdentityStore.loadOrCreate(secureStore: secureStore, reset: false)
        } catch {
            throw APIError.headerRejected
        }
        let identity = ClientIdentity(
            deviceName: "Apple TV", deviceID: deviceID, version: "0.1.0", token: token)
        return clientOverride
            ?? HTTPJellyfinClient(
                server: server.url, identity: identity, log: log,
                certificatePin: (try? pins?.fingerprint(for: server.id)).map {
                    OriginCertificatePin(url: server.url, sha256: $0)
                })
    }
}
