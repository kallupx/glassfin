import XCTest

#if os(tvOS)
    /// PoC acceptance journeys J3 for the M08a AVPlayer path (spec/TESTPLAN-PoC-ACCEPTANCE.md).
    ///
    /// These run against the seeded native macOS Jellyfin server, never the in-app mock server, because
    /// TPOC-16 and TPOC-17 assert what the server reports in `/Sessions`. Without the live-server
    /// environment (see PoCLiveServerConfiguration) each test is skipped, so default CI stays green.
    /// docs/POC-ACCEPTANCE-F3-F4.md maps every step to the test plan rows.
    @MainActor
    final class TPOCPlaybackAcceptanceUITests: XCTestCase {
        /// The app reports both F3 (remux) and F4 (audio-only transcode) as DirectStream.
        private static let directStream = "DirectStream"
        /// Ten-second progress reports plus slack (T08P-25).
        private static let progressWindow: TimeInterval = 25
        private static let ticksPerSecond: Int64 = 10_000_000
        /// The playback failure strings from the catalog; neither may appear for F3 or F4.
        private static let failureTexts = ["This file could not be played", "This video format isn't supported yet"]

        override func setUp() async throws {
            continueAfterFailure = false
        }

        // TPOC-16: canonical spec/TESTPLAN-PoC-ACCEPTANCE.md.
        func testTPOC_16_f3RemuxPlaysAsDirectStreamWithOnlyContainerReason() async throws {
            let server = try await liveServer()
            let movie = try await server.movie(container: "mkv", videoCodec: "h264", audioCodec: "aac")
            try await server.resetUserData(itemID: movie.id)
            let app = launchSignedIn(server.configuration)
            startPlayback(of: movie, in: app)

            // T08P-08: the server remuxes; video and audio are both copied.
            let session = try await waitForTranscodingSession(server, itemID: movie.id, app: app)
            XCTAssertEqual(session.playMethod, Self.directStream, "F3 PlayMethod (T08P-08)")
            XCTAssertEqual(session.isVideoDirect, true, "F3 IsVideoDirect (T08P-08)")
            XCTAssertEqual(session.isAudioDirect, true, "F3 IsAudioDirect (T08P-08)")
            // T08P-81: ContainerNotSupported is the only reason.
            XCTAssertEqual(session.transcodeReasons, ["ContainerNotSupported"], "F3 TranscodeReasons (T08P-81)")
            save(app.screenshot(), name: "tpoc-16-f3-playing")

            // T08P-09: the item actually plays; the reported position advances.
            try await assertPositionAdvances(server, itemID: movie.id, from: session.positionTicks, app: app)
            assertNoPlaybackFailure(in: app)

            // Menu leaves the player and returns to the detail screen.
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(element("detail.root", in: app).waitForExistence(timeout: 10), "Menu returns to detail")
            assertNoPlaybackFailure(in: app)
        }

        // TPOC-17: canonical spec/TESTPLAN-PoC-ACCEPTANCE.md.
        func testTPOC_17_f4DtsPlaysWithAudioOnlyTranscodeAndNoError() async throws {
            let server = try await liveServer()
            let movie = try await server.movie(container: "mkv", videoCodec: "h264", audioCodec: "dts")
            try await server.resetUserData(itemID: movie.id)
            let app = launchSignedIn(server.configuration)
            startPlayback(of: movie, in: app)

            // T08P-10: video is copied, audio is transcoded to AAC or E-AC-3.
            let session = try await waitForTranscodingSession(server, itemID: movie.id, app: app)
            XCTAssertEqual(session.playMethod, Self.directStream, "F4 PlayMethod (T08P-10)")
            XCTAssertEqual(session.isVideoDirect, true, "F4 IsVideoDirect (T08P-10)")
            XCTAssertEqual(session.isAudioDirect, false, "F4 IsAudioDirect (T08P-10)")
            XCTAssertTrue(["aac", "eac3"].contains(session.audioCodec ?? ""), "F4 AudioCodec (TESTPLAN-M08a App. A)")
            // T08P-80: no Q8P-05 video reason, at least one Audio* reason; nothing else besides the container.
            XCTAssertEqual(session.videoTranscodeReasons, [], "F4 has no video transcode reason (T08P-80)")
            XCTAssertTrue(session.transcodeReasons.contains { $0.hasPrefix("Audio") }, "F4 Audio* reason (T08P-80)")
            let unexpected = session.transcodeReasons.filter { $0 != "ContainerNotSupported" && !$0.hasPrefix("Audio") }
            XCTAssertEqual(unexpected, [], "F4 TranscodeReasons are container and Audio* only (TPOC-17)")
            save(app.screenshot(), name: "tpoc-17-f4-playing")
            assertNoPlaybackFailure(in: app)

            // T08P-11: F4 is about six seconds long. It must play to the end with no error at any point:
            // the player closes itself on .ended and the server marks the item played.
            let deadline = Date().addingTimeInterval(Self.progressWindow)
            var played = false
            while Date() < deadline && !played {
                assertNoPlaybackFailure(in: app)
                played = try await server.isPlayed(itemID: movie.id)
                if !played { try await Task.sleep(for: .milliseconds(500)) }
            }
            XCTAssertTrue(played, "F4 played to the end (T08P-11)")
            XCTAssertTrue(element("detail.root", in: app).waitForExistence(timeout: 10), "Player closed at end")
            assertNoPlaybackFailure(in: app)
            save(app.screenshot(), name: "tpoc-17-f4-ended")
        }

        // MARK: - Journey steps

        private func liveServer() async throws -> PoCLiveServer {
            guard let configuration = PoCLiveServerConfiguration.fromEnvironment() else {
                throw XCTSkip(PoCLiveServerConfiguration.skipReason)
            }
            return try await PoCLiveServer.connect(configuration)
        }

        /// Launches without any `-uitest-*` flag (they switch the app to the mock server) and signs in
        /// with the non-admin test user through the real UI (TPOC-07 path), unless already signed in.
        private func launchSignedIn(_ configuration: PoCLiveServerConfiguration) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments.append(contentsOf: ["-AppleLanguages", "(en)"])
            app.launch()
            let home = element("home.root", in: app)
            let connect = element(WelcomeCopy.Key.connect.rawValue, in: app)
            let appeared = home.waitForExistence(timeout: 20) || connect.exists
            XCTAssertTrue(appeared, "The app shows Welcome or Home after launch")
            if home.exists { return app }

            activate(connect, in: app)
            let address = element("address.field", in: app)
            XCTAssertTrue(address.waitForExistence(timeout: 10))
            typeText(configuration.serverURL.absoluteString, into: address, in: app)
            activate(element("address.continue", in: app), in: app)
            // A loopback HTTP server shows the cleartext warning (T04-25); accept it explicitly.
            let accept = element("cleartext.accept", in: app)
            let password = element("login.password", in: app)
            if accept.waitForExistence(timeout: 10) { activate(accept, in: app) }
            XCTAssertTrue(password.waitForExistence(timeout: 15), "Login method screen")
            activate(password, in: app)
            typeText(configuration.username, into: element("credentials.username", in: app), in: app)
            typeText(configuration.password, into: app.secureTextFields["credentials.password"], in: app)
            activate(element("credentials.signIn", in: app), in: app)
            XCTAssertTrue(home.waitForExistence(timeout: 20), "Sign-in reaches Home")
            return app
        }

        /// Movies tab → grid item → detail → Play (TPOC-13 path). The library grid and detail identifiers come
        /// from M07 (#23); the player presentation comes from the M08 adapter.
        private func startPlayback(of movie: PoCSeedMovie, in app: XCUIApplication) {
            activate(element("design.tab.library.\(movie.libraryID)", in: app), in: app)
            let item = element("library.item.\(movie.id)", in: app)
            XCTAssertTrue(
                item.waitForExistence(timeout: 20),
                "Movies grid item library.item.<id> is missing; needs the M07 library grid (#23)")
            activate(item, in: app)
            let play = element("detail.play", in: app)
            XCTAssertTrue(
                play.waitForExistence(timeout: 15), "detail.play is missing; needs the M07 detail screen (#23)")
            activate(play, in: app)
            for placeholder in ["detail.playback.pending", "library.playback.pending", "home.playback"]
            where element(placeholder, in: app).waitForExistence(timeout: 2) {
                XCTFail("Play opened the placeholder '\(placeholder)': the M08 player adapter is not wired (TODO(M08))")
            }
        }

        // MARK: - Server-side checks

        private func waitForTranscodingSession(
            _ server: PoCLiveServer, itemID: String, app: XCUIApplication
        ) async throws -> PoCPlaybackSession {
            let deadline = Date().addingTimeInterval(30)
            var last: PoCPlaybackSession?
            while Date() < deadline {
                assertNoPlaybackFailure(in: app)
                last = try await server.playbackSession(itemID: itemID)
                if let last, last.hasTranscodingInfo { return last }
                try await Task.sleep(for: .milliseconds(500))
            }
            let state = last.map { "PlayMethod=\($0.playMethod ?? "nil"), TranscodingInfo missing" } ?? "no session"
            throw PoCLiveServerError.noPlaybackSession(state)
        }

        private func assertPositionAdvances(
            _ server: PoCLiveServer, itemID: String, from start: Int64, app: XCUIApplication
        ) async throws {
            let deadline = Date().addingTimeInterval(Self.progressWindow)
            var position = start
            while Date() < deadline && position - start < 2 * Self.ticksPerSecond {
                assertNoPlaybackFailure(in: app)
                try await Task.sleep(for: .seconds(1))
                position = try await server.playbackSession(itemID: itemID)?.positionTicks ?? position
            }
            XCTAssertGreaterThanOrEqual(position - start, 2 * Self.ticksPerSecond, "Reported position advances")
        }

        // MARK: - UI helpers

        private func assertNoPlaybackFailure(in app: XCUIApplication, line: UInt = #line) {
            XCTAssertEqual(app.alerts.count, 0, "A playback alert appeared", line: line)
            for text in Self.failureTexts {
                let shown = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
                XCTAssertFalse(shown.exists, "Playback failure text appeared: \(text)", line: line)
            }
        }

        private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
            app.descendants(matching: .any)[identifier]
        }

        /// Screenshots are taken only on playback screens, never on the credentials form (TPOC-80).
        private func save(_ shot: XCUIScreenshot, name: String) {
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let directory = ProcessInfo.processInfo.environment["GLASSFIN_SCREENSHOT_DIR"], !directory.isEmpty {
                let folder = URL(fileURLWithPath: directory, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
    }
#endif
