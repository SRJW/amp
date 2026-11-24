import XCTest
import UIKit

final class LibraryInteractionTests: XCTestCase {
    @MainActor func testArtistPortraitScrollReturnsWithoutMovingNavigationOrBlockingActions() {
        let app = launch("artist")
        let page = app.scrollViews["artistPage"]
        let title = app.staticTexts["collectionHeroTitle"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let baseline = title.frame.midY
        let navigation = app.buttons["appSection.library"].frame
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(title.frame.midY - baseline) < 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
        page.swipeUp()
        page.swipeDown()
        page.swipeDown()
        XCTAssertTrue(app.buttons["artistInfo"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["appSection.library"].frame.midY, navigation.midY, accuracy: 0.5)
        app.buttons["artistInfo"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["artistPlayPause"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Artist portrait after scrolling and rubber-band return"
        shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testGlassContactKeepsButtonActionsAndCancelsVerticalExit() {
        for mode in ["light", "dark"] {
            let app = launch("player-" + mode)
            let library = app.buttons["appSection.library"]
            let equalizer = app.buttons["appSection.equalizer"]
            XCTAssertTrue(library.waitForExistence(timeout: 30))
            equalizer.press(forDuration: 0.30)
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in equalizer.isSelected }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed,
                           "Observing a hold must not consume the button's actual action")
            library.tap()
            XCTAssertTrue(library.isSelected)
            let start = library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.10, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)))
            XCTAssertTrue(library.isSelected, "Leaving vertically must cancel the lens without changing section")
            let play = app.buttons["miniPlayerPlayPause"]
            XCTAssertTrue(play.waitForExistence(timeout: 10))
            let oldLabel = play.label
            play.tap()
            let toggled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in play.label != oldLabel }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [toggled], timeout: 10), .completed,
                           "The bar's window observer must not intercept mini-player controls")
            XCTAssertFalse(app.buttons["nowPlayingTitle"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Glass controls in " + mode; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    @MainActor func testNativeMenuSettingsWorksAfterWifiTransferWithoutSwitchingTabs() {
        let app = launch("player-light")
        let menu = app.buttons["appMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        for _ in 0..<2 {
            menu.tap()
            let wifi = app.buttons["appMenu.wifiTransfer"]
            XCTAssertTrue(wifi.waitForExistence(timeout: 5))
            wifi.tap()
            XCTAssertTrue(app.buttons["Start transfer"].waitForExistence(timeout: 10))
            menu.tap()
            let settings = app.buttons["appMenu.settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
            XCTAssertTrue(app.buttons["settingsMusicLibrary"].waitForExistence(timeout: 10),
                          "A menu row over the navigation bar must open Settings, not feed the glass lens")
            XCTAssertFalse(app.textFields["librarySearchField"].exists)
        }
    }

    @MainActor func testMissingArtworkHasReadableTitleInLightAndDarkMode() {
        for mode in ["light", "dark"] {
            let app = launch("player-" + mode)
            let mini = app.buttons["openNowPlaying"]
            XCTAssertTrue(mini.waitForExistence(timeout: 30))
            mini.tap()
            let title = app.buttons["nowPlayingTitle"]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.contrastingPixelCount(title.screenshot().image, lightBackground: mode == "light") > 20
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed,
                           "The title must contrast with the flat missing-artwork background")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Full player without artwork - " + mode; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    private func contrastingPixelCount(_ image: UIImage, lightBackground: Bool) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let width = 200, height = 30
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        return (0..<(width * height)).filter { index in
            let luminance = (Int(bytes[index * 4]) + Int(bytes[index * 4 + 1]) + Int(bytes[index * 4 + 2])) / 3
            return lightBackground ? luminance < 100 : luminance > 155
        }.count
    }

    @MainActor func testIntroductionShowsSixFeaturePagesAndFinishes() {
        let app = launch("introduction")
        let next = app.buttons["introductionPrimaryAction"]
        XCTAssertTrue(next.waitForExistence(timeout: 30))
        for page in 0..<6 {
            XCTAssertTrue(app.staticTexts["introductionTitle"].exists)
            if page == 0 || page == 5 {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "amp introduction page \(page + 1)"; shot.lifetime = .keepAlways
                add(shot)
            }
            XCTAssertEqual(next.label, page == 5 ? "Start listening" : "Continue")
            next.tap()
        }
        XCTAssertTrue(app.staticTexts["introductionFinished"].waitForExistence(timeout: 10))
    }

    @MainActor func testLibraryAndPlayerNavigationShareScreenCoordinates() {
        let app = launch("player")
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 30))
        let identifiers = ["appSection.library", "appSection.equalizer", "appSection.search", "appMenu"]
        func navigationFrames() -> [String: CGRect] {
            // One AX snapshot keeps all four measurements from the same frame.
            // Re-resolving each element separately can exceed the waiter's entire
            // timeout on a busy simulator before reaching the fourth button.
            guard let snapshot = try? app.snapshot() else { return [:] }
            var frames: [String: CGRect] = [:]
            func collect(_ item: XCUIElementSnapshot) {
                if item.elementType == .button, identifiers.contains(item.identifier) { frames[item.identifier] = item.frame }
                item.children.forEach(collect)
            }
            collect(snapshot)
            return frames
        }
        let initialFrames = navigationFrames()
        XCTAssertEqual(Set(initialFrames.keys), Set(identifiers))
        let libraryFrames = identifiers.map { initialFrames[$0] ?? .zero }
        for identifier in identifiers { XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1) }
        func navigationMatchesLibrary() -> Bool {
            let measured = navigationFrames()
            return zip(identifiers, libraryFrames).allSatisfy { identifier, expected in
                guard let actual = measured[identifier] else { return false }
                return abs(actual.midX - expected.midX) < 0.5 && abs(actual.midY - expected.midY) < 0.5
                    && abs(actual.width - expected.width) < 0.5 && abs(actual.height - expected.height) < 0.5
            }
        }
        mini.tap()
        XCTAssertTrue(app.buttons["nowPlayingTitle"].waitForExistence(timeout: 10))
        for identifier in identifiers { XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1,
                                                       "The transition must reuse one persistent navigation row") }
        let aligned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in navigationMatchesLibrary() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [aligned], timeout: 20), .completed,
                       "The full player must preserve every Library navigation button's screen coordinates and size")
        for (identifier, expected) in zip(identifiers, libraryFrames) {
            let actual = app.buttons[identifier].frame
            XCTAssertEqual(actual.midX, expected.midX, accuracy: 0.5, identifier)
            XCTAssertEqual(actual.midY, expected.midY, accuracy: 0.5, identifier)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, identifier)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, identifier)
        }
        let playerScreenshot = XCTAttachment(screenshot: app.screenshot())
        playerScreenshot.name = "Player navigation without capsule or labels"; playerScreenshot.lifetime = .keepAlways
        add(playerScreenshot)
        // Test actual navigation separately from measuring accessibility frame geometry.
        app.buttons["appSection.search"].tap()
        XCTAssertTrue(app.textFields["librarySearchField"].waitForExistence(timeout: 10))
        // Search focuses its field automatically; navigation is intentionally hidden
        // while the keyboard is visible. Close it through the real search control.
        app.buttons["searchCloseButton"].tap()
        app.buttons["appSection.library"].tap()
        XCTAssertTrue(mini.waitForExistence(timeout: 10))
        XCTAssertTrue(navigationMatchesLibrary(), "Returning to Library must leave its capsule and mini player in place")
        app.buttons["appMenu"].tap()
        app.buttons["appMenu.settings"].tap()
        let librarySettings = app.buttons["settingsMusicLibrary"]
        XCTAssertTrue(librarySettings.waitForExistence(timeout: 10))
        for _ in 0..<5 {
            if librarySettings.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        librarySettings.tap()
        XCTAssertTrue(app.staticTexts["On My iPhone › amp"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["On My iPhone › Amp"].exists)
        app.buttons["appSection.library"].tap()
        let libraryScreenshot = XCTAttachment(screenshot: app.screenshot())
        libraryScreenshot.name = "Library navigation with Liquid Glass and icon-only selection"; libraryScreenshot.lifetime = .keepAlways
        add(libraryScreenshot)
        app.buttons["appSection.library"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.buttons["appSection.search"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertTrue(app.textFields["librarySearchField"].waitForExistence(timeout: 10), "Dragging the selection capsule must activate the destination section")
    }

    @MainActor func testLibraryVisibilityPersistsAndPlayerTitleRevealsUnfilteredAllSongs() {
        let app = launch("songs")
        let page = app.tables["songsPage"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        app.buttons["appSection.library"].tap()
        app.buttons["Library options"].tap()
        app.buttons["customizeLibrary"].tap()
        let hideAlbums = app.buttons["Hide Albums"]
        let showAlbums = app.buttons["Show Albums"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            hideAlbums.exists || showAlbums.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                       "The editor must show its sections immediately, without Reset")
        if showAlbums.exists { showAlbums.tap() }
        hideAlbums.tap()
        XCTAssertTrue(showAlbums.waitForExistence(timeout: 5), "The eye action must update before closing the editor")
        XCTAssertEqual(showAlbums.value as? String, "Hidden")
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["libraryCategory.albums"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        app.buttons["appSection.library"].tap()
        XCTAssertFalse(app.buttons["libraryCategory.albums"].exists, "Hidden sections survive a full relaunch")
        app.buttons["libraryCategory.songs"].tap()
        let song = page.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "History fixture one")).firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 20))
        song.tap()
        let openedTitle = app.buttons["nowPlayingTitle"]
        XCTAssertTrue(openedTitle.waitForExistence(timeout: 10), "Tapping a song opens the existing full player")
        openedTitle.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        page.buttons["sectionSearchButton"].tap()
        let field = page.textFields["sectionSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        dismissKeyboardIntroduction(in: app)
        field.tap(); field.typeText("No matching track\n")
        app.buttons["openNowPlaying"].tap()
        let title = app.buttons["nowPlayingTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let currentTitle = title.label
        title.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let revealed = page.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", currentTitle)).firstMatch
        XCTAssertTrue(revealed.waitForExistence(timeout: 10))
        XCTAssertTrue(revealed.isHittable, "The title clears existing filters and scrolls to its row in All Songs")
        XCTAssertFalse(page.textFields["sectionSearchField"].exists)
    }

    @MainActor func testPlayerTitleScrollsToAnOffscreenSong() {
        let app = launch("songs-reveal")
        let page = app.tables["songsPage"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        let target = page.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ZZZ offscreen song")).firstMatch
        let alphabet = app.descendants(matching: .any).matching(identifier: "songAlphabetIndex").firstMatch
        XCTAssertTrue(alphabet.waitForExistence(timeout: 10))
        print("Alphabet frame before drag: \(alphabet.frame); value: \(String(describing: alphabet.value))")
        alphabet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            .press(forDuration: 0.05, thenDragTo: alphabet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        print("Alphabet frame after drag: \(alphabet.frame); value: \(String(describing: alphabet.value))")
        let atEnd = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && target.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [atEnd], timeout: 10), .completed)
        target.tap()
        let title = app.buttons["nowPlayingTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "A library row opens the full player directly")
        XCTAssertEqual(title.label, "ZZZ offscreen song")
        title.tap()
        XCTAssertTrue(alphabet.waitForExistence(timeout: 10))
        alphabet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
            .press(forDuration: 0.05, thenDragTo: alphabet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)))
        let atStart = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !(target.exists && target.isHittable)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [atStart], timeout: 10), .completed)
        XCTAssertFalse(target.exists && target.isHittable, "The song starts outside the visible viewport")
        app.buttons["openNowPlaying"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "ZZZ offscreen song")
        title.tap()
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            target.exists && target.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 15), .completed,
                       "Opening All Songs must scroll down to the exact current file")
        let miniProgress = app.otherElements["miniPlayerProgress"]
        miniProgress.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: miniProgress.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        target.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let elapsed = app.staticTexts["nowPlayingElapsed"]
        let uninterrupted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let parts = elapsed.label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] >= 65
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [uninterrupted], timeout: 10), .completed,
                       "Opening the currently playing row must preserve its position instead of restarting")
        title.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "all-songs-revealed-offscreen-track"; screenshot.lifetime = .keepAlways; add(screenshot)

        func openLibrarySettings() {
            app.buttons["appMenu"].tap()
            app.buttons["appMenu.settings"].tap()
            let librarySettings = app.buttons["settingsMusicLibrary"]
            XCTAssertTrue(librarySettings.waitForExistence(timeout: 10))
            for _ in 0..<5 {
                if librarySettings.isHittable { break }
                app.scrollViews.firstMatch.swipeUp()
            }
            librarySettings.tap()
        }
        openLibrarySettings()
        let haptics = app.switches["Alphabet scrolling haptics"]
        XCTAssertTrue(haptics.waitForExistence(timeout: 10))
        if haptics.value as? String != "1" { haptics.tap() }
        haptics.tap()
        XCTAssertEqual(haptics.value as? String, "0")
        app.terminate(); app.launch()
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        openLibrarySettings()
        XCTAssertTrue(haptics.waitForExistence(timeout: 10))
        XCTAssertEqual(haptics.value as? String, "0", "Disabling alphabet haptics survives a full relaunch")
        haptics.tap()
        XCTAssertEqual(haptics.value as? String, "1")
    }

    @MainActor func testMiniPlayerScrubsAndSwipesWithoutOpeningThePlayer() {
        let app = launch("player")
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 30))
        let progress = app.otherElements["miniPlayerProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        let artwork = app.buttons["openNowPlayingArtwork"]
        let playPause = app.buttons["miniPlayerPlayPause"]
        XCTAssertTrue(artwork.exists && playPause.exists)
        XCTAssertGreaterThan(progress.frame.minX, artwork.frame.maxX, "Progress belongs under the text, beside the cover")
        XCTAssertLessThan(progress.frame.maxX, playPause.frame.minX)
        XCTAssertGreaterThanOrEqual(progress.frame.minY, mini.frame.maxY)
        let initialPlayLabel = playPause.label
        playPause.tap()
        let toggled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label != initialPlayLabel }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [toggled], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["nowPlayingTitle"].exists, "Play/pause must not open the player")
        playPause.tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label == initialPlayLabel }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
        let reference = XCTAttachment(screenshot: app.screenshot())
        reference.name = "mini-player-reference-layout"; reference.lifetime = .keepAlways; add(reference)
        progress.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: progress.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = progress.value as? String, let elapsed = value.components(separatedBy: " of ").first else { return false }
            let parts = elapsed.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] >= 65
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [sought], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["nowPlayingTitle"].exists)
        mini.swipeLeft()
        let next = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (mini.value as? String)?.hasPrefix("Second player track,") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["nowPlayingTitle"].exists)
        mini.swipeRight()
        let previous = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (mini.value as? String)?.hasPrefix("Player presentation regression,") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [previous], timeout: 10), .completed)
        mini.tap()
        XCTAssertTrue(app.buttons["nowPlayingTitle"].waitForExistence(timeout: 10))
        app.buttons["appSection.library"].tap()
        XCTAssertTrue(artwork.waitForExistence(timeout: 10))
        artwork.tap()
        XCTAssertTrue(app.buttons["nowPlayingTitle"].waitForExistence(timeout: 10), "The cover opens the same player")
        app.buttons["appSection.library"].tap()
        XCTAssertTrue(mini.waitForExistence(timeout: 10))
        let upwardStart = mini.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        upwardStart.press(forDuration: 0.05, thenDragTo: upwardStart.withOffset(CGVector(dx: 0, dy: -100)))
        XCTAssertTrue(app.buttons["nowPlayingTitle"].waitForExistence(timeout: 10), "Swipe up still opens the player")
    }

    /// The fresh iOS simulator can show its one-time QuickPath introduction over the keyboard.
    @MainActor private func dismissKeyboardIntroduction(in app: XCUIApplication) {
        let proceed = app.buttons["Continue"]
        if proceed.waitForExistence(timeout: 2) { proceed.tap() }
    }

    @MainActor func testUnifiedNavigationKeepsSearchWhenToolsCloseAndAppReturns() {
        let app = launch("player")
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 30))
        app.buttons["appSection.search"].tap()
        let field = app.textFields["librarySearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        dismissKeyboardIntroduction(in: app)
        field.tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            let keyboardTop = app.keyboards.firstMatch.frame.minY
            let artworkBottom = app.buttons["openNowPlayingArtwork"].frame.maxY
            // AX's keyboard frame excludes iOS's predictive row on some runtimes.
            // Allow that system-owned row, then assert the app's entire nav is absent.
            let keyHeight = app.keyboards.firstMatch.buttons["a"].frame.height
            XCTAssertLessThan(keyboardTop - artworkBottom, 30 + keyHeight,
                              "Only the native predictive row may separate mini player and keyboard")
            XCTAssertFalse(app.buttons["appSection.library"].exists, "Hide the entire navigation row, including its surface, while typing")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Search keyboard without empty navigation capsule"; shot.lifetime = .keepAlways
            add(shot)
        }
        field.typeText("Local fixture\n")
        app.buttons["appMenu"].tap()
        XCTAssertTrue(app.buttons["appMenu.settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "appMenu.equalizer").count, 1)
        XCTAssertFalse(app.staticTexts["VYBE"].exists)
        app.buttons["appMenu.settings"].tap()
        let close = app.buttons["closeTool"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Local fixture")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "Local fixture")
        let playerTitle = app.buttons["nowPlayingTitle"]
        XCTAssertFalse(playerTitle.exists && playerTitle.isHittable)
        app.buttons["appSection.equalizer"].tap()
        XCTAssertTrue(app.buttons["appSection.equalizer"].isSelected)
        app.buttons["appSection.library"].tap()
        XCTAssertTrue(app.buttons["libraryCategory.songs"].waitForExistence(timeout: 10))
        mini.tap()
        XCTAssertTrue(app.buttons["nowPlayingTitle"].waitForExistence(timeout: 10))
        XCTAssertFalse(mini.exists && mini.isHittable, "The redundant song strip stays hidden inside the full player")
        XCTAssertEqual(app.buttons.matching(identifier: "appMenu").count, 1,
                       "The full player must expose only its own Menu control")
        app.buttons["appMenu"].tap()
        XCTAssertTrue(app.buttons["appMenu.soundCapsule"].waitForExistence(timeout: 5))
        app.buttons["appMenu.soundCapsule"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "appSection.library").count, 1,
                       "Only the tool's shared bar is accessible while it covers the player")
        close.tap()
        XCTAssertTrue(app.buttons["nowPlayingTitle"].isHittable, "Closing a tool returns to the full player that opened it")
        app.buttons["appSection.library"].tap()
        XCTAssertTrue(app.buttons["libraryCategory.songs"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "unified-library-and-bottom-navigation"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor private func launch(_ page: String, waveform: String = "scrolling") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--amp-interaction-probe=" + page, "-amp.player.waveformMode", waveform]
        app.launch()
        return app
    }

    @MainActor func testFullPlayerOpensClosesAndReopensWithoutArtwork() {
        checkPlayerPresentation(page: "player")
    }

    @MainActor func testFullPlayerOpensClosesAndReopensWithReducedMotion() {
        checkPlayerPresentation(page: "player-reduced-motion")
    }

    @MainActor private func checkPlayerPresentation(page: String) {
        let app = launch(page)
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20), "The local fixture must load into the real mini player")
        let title = app.buttons["nowPlayingTitle"]
        let transport = app.buttons["nowPlayingPlayPause"]
        let close = app.buttons["closeNowPlaying"]
        func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                element.exists && element.isHittable
            }, object: nil)
            let result = XCTWaiter.wait(for: [visible], timeout: timeout)
            if result != .completed {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = page + "-unavailable-control"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = page + "-unavailable-control"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            XCTAssertEqual(result, .completed,
                           "Timed out waiting for \(element.identifier) to become hittable on \(page)")
        }
        for cycle in 0..<2 {
            // On a cold simulator the mini player can enter accessibility before
            // launch and initial library layout finish. Later presentation checks
            // retain their shorter deadline to catch close/reopen regressions.
            waitUntilHittable(mini, timeout: cycle == 0 ? 30 : 10)
            mini.tap()
            waitUntilHittable(title)
            XCTAssertEqual(title.label, "Player presentation regression")
            waitUntilHittable(transport)
            // Playback is exercised through the full-screen controls, rather than
            // just checking that an invisible overlay exists in accessibility.
            let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                transport.label == "Pause"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 10), .completed)
            transport.tap()
            let play = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                transport.label == "Play"
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [play], timeout: 5), .completed)
            transport.tap()
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = page + "-full-player"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons["nowPlayingMenu"].tap()
            waitUntilHittable(close)
            close.tap()
            waitUntilHittable(mini)
            XCTAssertFalse(title.exists)
        }
        mini.tap()
        waitUntilHittable(title)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80)))
        waitUntilHittable(mini)
        mini.tap()
        waitUntilHittable(title)
        XCTAssertTrue(transport.isHittable)
    }

    @MainActor func testLargeTransportChangesTracksAndSmallTransportSeeksWithinTheTrack() {
        let app = launch("player")
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20))
        mini.tap()
        let title = app.buttons["nowPlayingTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let next = app.buttons["nowPlayingNextTrack"]
        let previous = app.buttons["nowPlayingPreviousTrack"]
        let forward = app.buttons["nowPlayingForward"]
        let rewind = app.buttons["nowPlayingRewind"]
        XCTAssertGreaterThan(next.frame.width, forward.frame.width)
        XCTAssertGreaterThan(previous.frame.width, rewind.frame.width)
        next.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            title.label == "Second player track"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        let playPause = app.buttons["nowPlayingPlayPause"]
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label == "Pause" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
        playPause.tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label == "Play" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 5), .completed)
        let elapsed = app.staticTexts["nowPlayingElapsed"]
        func seconds() -> Int {
            let parts = elapsed.label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
        }
        let initialSeconds = seconds()
        XCTAssertGreaterThanOrEqual(initialSeconds, 0)
        forward.tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in seconds() >= initialSeconds + 9 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
        XCTAssertEqual(title.label, "Second player track")
        rewind.tap()
        let rewound = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            seconds() >= 0 && abs(seconds() - initialSeconds) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rewound], timeout: 5), .completed)
        XCTAssertEqual(title.label, "Second player track")
        previous.tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            title.label == "Player presentation regression"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
    }

    @MainActor func testStaticWaveformUsesFullSongCoordinatesAndRestoresControls() {
        let app = launch("player", waveform: "fullTrack")
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20))
        mini.tap()
        let transport = app.buttons["nowPlayingPlayPause"]
        XCTAssertTrue(transport.waitForExistence(timeout: 10))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in transport.label == "Pause" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
        transport.tap()
        let waveform = app.descendants(matching: .any)["nowPlayingWaveform"]
        XCTAssertTrue(waveform.waitForExistence(timeout: 5))
        let elapsed = app.staticTexts["nowPlayingElapsed"]
        func seconds() -> Int {
            let parts = elapsed.label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
        }
        waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
        let tapped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (89...91).contains(seconds()) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [tapped], timeout: 5), .completed)
        waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.12)))
        let dragged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (29...31).contains(seconds()) && transport.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dragged], timeout: 5), .completed)
        XCTAssertEqual(transport.label, "Play", "Seeking while paused must not start playback")
        transport.tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in transport.label == "Pause" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 10), .completed, "The actual play button works after a static scrub")
    }

    @MainActor func testWaveformDragSeeksInBothDirectionsAndNewTrackStartsFresh() {
        let app = launch("player")
        let mini = app.buttons["openNowPlaying"]
        XCTAssertTrue(mini.waitForExistence(timeout: 20))
        mini.tap()
        let playPause = app.buttons["nowPlayingPlayPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 10))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label == "Pause" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 10), .completed)
        playPause.tap()
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label == "Play" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 5), .completed)
        let elapsed = app.staticTexts["nowPlayingElapsed"]
        func seconds() -> Int {
            let parts = elapsed.label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
        }
        let waveform = app.descendants(matching: .any)["nowPlayingWaveform"]
        XCTAssertTrue(waveform.waitForExistence(timeout: 5))
        let initial = seconds()
        // Above the transport circles: an actual drag on the waveform, across their x positions.
        waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12)))
        let forward = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in seconds() >= initial + 27 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [forward], timeout: 5), .completed)
        let controlsReturned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            playPause.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [controlsReturned], timeout: 3), .completed,
                       "Controls return after scrubbing")
        waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.12)))
        let backward = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(seconds() - initial) <= 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [backward], timeout: 5), .completed)
        app.buttons["nowPlayingNextTrack"].tap()
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["nowPlayingTitle"].label == "Second player track" && (0...2).contains(seconds())
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 10), .completed)
        playPause.tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in playPause.label == "Pause" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 10), .completed, "The actual play button works after scrolling scrubs")
    }

    @MainActor func testSongsHistoryPersistsAndSelectionAddsToPlaylistAndConfirmsDeletion() {
        let app = launch("songs")
        let page = app.tables["songsPage"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        let search = page.buttons["sectionSearchButton"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        XCTAssertTrue(page.buttons["songsPlayAll"].exists)
        XCTAssertTrue(page.buttons["songsShuffle"].exists)
        let first = page.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "History fixture one")).firstMatch
        let second = page.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "History fixture two")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        XCTAssertTrue(first.label.contains("Fixture artist"))
        XCTAssertTrue(first.label.contains("0:02 |") && first.label.contains("m4a"), "Songs expose duration and real container format")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "songs-layout-and-file-information"; screenshot.lifetime = .keepAlways; add(screenshot)
        search.tap()
        let field = page.textFields["sectionSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        dismissKeyboardIntroduction(in: app)
        field.tap(); field.typeText("History fixture\n")
        // Commit through the real Clear control and verify the query has reached
        // history before force-terminating the process.
        let clear = page.buttons["searchClearButton"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(page.buttons["recentSearch.History fixture"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        search.tap()
        let recent = page.buttons["recentSearch.History fixture"]
        XCTAssertTrue(recent.waitForExistence(timeout: 10), "Search text survives a full app relaunch")
        recent.tap()
        field.tap(); field.typeText("\n")
        page.buttons["songsSelect"].tap()
        first.tap()
        XCTAssertTrue(page.staticTexts["1 selected"].waitForExistence(timeout: 5))
        XCTAssertFalse(page.buttons["songsPlayAll"].isEnabled, "Select is reserved for playlist and deletion actions")
        page.buttons["songsAddToPlaylist"].tap()
        let playlist = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Songs UI playlist")).firstMatch
        XCTAssertTrue(playlist.waitForExistence(timeout: 10))
        playlist.tap()
        page.buttons["songsAddToPlaylist"].tap()
        XCTAssertTrue(playlist.waitForExistence(timeout: 10))
        XCTAssertTrue(playlist.label.contains("1 song"), "The selected song was actually added")
        app.buttons["Cancel"].tap()
        page.buttons["songsDeleteSelected"].tap()
        let deletion = app.alerts.firstMatch
        XCTAssertTrue(deletion.waitForExistence(timeout: 10), "Deletion must present an explicit confirmation")
        deletion.buttons["Cancel"].tap()
        XCTAssertTrue(first.exists, "Cancel must preserve the selected file and row")
        page.buttons["songsDeleteSelected"].tap()
        XCTAssertTrue(deletion.waitForExistence(timeout: 10))
        deletion.buttons["Delete from device"].tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !first.exists && second.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed, "Only the confirmed selection is removed")
    }

    @MainActor func testSearchClearAndCloseAreTappableWithKeyboardVisible() {
        let app = launch("search")
        app.buttons["openSearchProbe"].tap()
        let field = app.textFields["librarySearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("needle")
        let clear = app.buttons["searchClearButton"]
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !clear.exists && (field.value as? String) != "needle"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 3), .completed)
        field.typeText("again")
        let close = app.buttons["searchCloseButton"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(app.buttons["openSearchProbe"].waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
    }

    @MainActor func testBrowseControlsAndRevealedSearchScrollOutOfTheViewport() {
        let app = launch("browse")
        let search = app.buttons["sectionSearchButton"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let field = app.textFields["sectionSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Album")
        // Begin on page content above the keyboard: scrolling up collapses search and
        // dismisses editing while keeping the query, as in the pull-down drawer.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.17)))
        let keyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 5), .completed)
        // A text field can expose its own scroll view. Drag the page content itself.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
        start.press(forDuration: 0.05, thenDragTo: end)
        let sort = app.staticTexts["sortProbe"]
        func frame(_ element: XCUIElement) -> String { element.exists ? String(describing: element.frame) : "hidden" }
        let details = "search=\(frame(search)), field=\(frame(field)), sort=\(frame(sort)), keyboard=\(app.keyboards.firstMatch.exists)"
        XCTAssertFalse(search.isHittable, details)
        XCTAssertFalse(field.isHittable, details)
        XCTAssertFalse(sort.isHittable, details)
    }

    @MainActor func testPullRevealsSearchBetweenTheTitleAndControlsAndUpwardSwipeCollapsesIt() {
        let app = launch("browse")
        let searchButton = app.buttons["sectionSearchButton"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10))
        let field = app.textFields["sectionSearchField"]
        let pageReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // A collapsed field leaves the accessibility tree; checking `exists` first avoids the
            // multi-second lookup retries of `isHittable` on a missing element.
            searchButton.isHittable && !(field.exists && field.isHittable)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pageReady], timeout: 3), .completed)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // The accessibility element exists before the scroll/bounce animation has
        // finished. Require a usable hit target before checking its final layout.
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            field.exists && field.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 3), .completed)
        XCTAssertLessThan(app.staticTexts["sectionBrowseTitle"].frame.maxY, field.frame.minY)
        XCTAssertGreaterThan(app.staticTexts["sortProbe"].frame.minY, field.frame.maxY)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Pulling reveals search without beginning editing")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !(field.exists && field.isHittable)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
    }


    #if AMP_ANIMATED_ART
    @MainActor func testAnimatedCoverSearchStaysInTheTopNavigationDrawer() {
        let app = launch("animated-covers")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        XCTAssertLessThan(field.frame.maxY, app.frame.height / 2, "Animated-cover search belongs above the list, away from bottom playback/navigation controls")
    }
    #endif

    @MainActor func testFixTagsScrollingCompactsTheSharedBottomChrome() {
        let app = launch("tools")
        let fraction = app.staticTexts["chromeFraction"]
        XCTAssertTrue(fraction.waitForExistence(timeout: 10))
        // Drag the list gutter so the confidence slider cannot capture the gesture.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
        start.press(forDuration: 0.05, thenDragTo: end)
        let compact = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(fraction.label) ?? 0) > 0.5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [compact], timeout: 3), .completed,
                       "Chrome fraction after list scrolling: \(fraction.label)")
    }

    @MainActor func testCoverSwipesChangeTracksAndVerticalPullClosesPlayer() {
        let app = launch("player-artwork")
        let mini = app.buttons["openNowPlaying"]
        guard mini.waitForExistence(timeout: 20) else {
            let failure = app.staticTexts["playerProbeFailure"]
            XCTFail(failure.exists ? failure.label : "Player fixture did not become ready")
            return
        }
        mini.tap()
        let cover = app.otherElements["nowPlayingArtwork"]
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        func swipe(from: CGFloat, to: CGFloat) {
            cover.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: cover.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5)))
        }
        swipe(from: 0.8, to: 0.2)
        let next = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["nowPlayingTitle"].label == "Second player track"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 10), .completed)
        swipe(from: 0.2, to: 0.8)
        let previous = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["nowPlayingTitle"].label == "Player presentation regression"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [previous], timeout: 10), .completed)
        cover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !cover.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        XCTAssertTrue(mini.isHittable)
    }

    @MainActor func testTransitionRowHasOnlyItsTitleSummaryAndSwitch() {
        let app = launch("transitions")
        XCTAssertTrue(app.buttons["transitionStudioOpen"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Enable transitions for this album"].exists)
        let wrapper = app.switches.matching(identifier: "collectionTransitionToggle").firstMatch
        XCTAssertTrue(wrapper.exists)
        // SwiftUI exposes both a wrapper and the underlying UISwitch. Use the
        // smallest hittable switch with a native binary value, rather than a
        // coordinate in the wrapper, whose frame can include non-control space.
        let candidates = app.switches.allElementsBoundByIndex.filter {
            ["0", "1"].contains($0.value as? String ?? "") && $0.isHittable
        }
        guard let toggle = candidates.min(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }), let initialValue = toggle.value as? String else {
            XCTFail("The transition row must expose a hittable native switch: \(app.debugDescription)")
            return
        }
        let row = app.buttons["transitionStudioOpen"]
        for expectedValue in [initialValue == "1" ? "0" : "1", initialValue] {
            toggle.tap()
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", expectedValue), object: toggle)
            guard XCTWaiter.wait(for: [changed], timeout: 10) == .completed else {
                XCTFail("The native switch must change to \(expectedValue): \(toggle.debugDescription)")
                return
            }
            let summary = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: expectedValue == "0" ? "label CONTAINS %@" : "NOT (label CONTAINS %@)",
                                       "Off for this album"), object: row)
            guard XCTWaiter.wait(for: [summary], timeout: 10) == .completed else {
                XCTFail("The collection summary must reflect switch value \(expectedValue): \(row.label)")
                return
            }
        }
    }
}
