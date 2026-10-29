import XCTest

/// End-to-end tests against a local OpenSSH server (see TEST_RUNNER_* variables passed by xcodebuild).
final class PuTTYUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var port: String { env["SSH_PORT"] ?? "2222" }
    private var user: String { env["SSH_USER"] ?? "testuser" }

    override func setUp() {
        continueAfterFailure = false
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        if let dir = env["SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func waitForTerminal(_ app: XCUIApplication, contains text: String, timeout: TimeInterval = 20) {
        let terminal = app.descendants(matching: .any)["terminal"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if terminal.exists, let value = terminal.value as? String, value.contains(text) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        snapshot(app, "timeout-\(text)")
        XCTFail("Terminal never showed \"\(text)\". Screen:\n\((terminal.value as? String) ?? "<none>")")
    }

    private func enterDestination(_ app: XCUIApplication) {
        let host = app.textFields.element(boundBy: 0)
        XCTAssertTrue(host.waitForExistence(timeout: 10))
        host.tap()
        host.typeText("127.0.0.1")
        let portField = app.textFields.element(boundBy: 1)
        portField.tap()
        portField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + port)
    }

    private func acceptHostKeyIfAsked(_ app: XCUIApplication, expectFingerprint: Bool) {
        let alert = app.staticTexts["PuTTY Security Alert"]
        if alert.waitForExistence(timeout: expectFingerprint ? 15 : 4) {
            if let fp = env["SSH_FP"] {
                let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fp)).firstMatch
                XCTAssertTrue(message.exists, "Host key dialog does not show fingerprint \(fp)")
            }
            snapshot(app, "host-key-alert")
            app.buttons["Yes"].tap()
        } else if expectFingerprint {
            XCTFail("No host key alert")
        }
    }

    func test1_PasswordPromptAndAccessDenied() {
        let app = XCUIApplication(bundleIdentifier: "com.oxapayy.puttyios")
        app.launch()
        snapshot(app, "config-window")
        enterDestination(app)
        app.buttons["Open"].tap()
        acceptHostKeyIfAsked(app, expectFingerprint: true)

        waitForTerminal(app, contains: "login as: ")
        app.typeText("\(user)\n")
        waitForTerminal(app, contains: "\(user)@127.0.0.1's password: ")
        app.typeText("definitely-wrong\n")
        waitForTerminal(app, contains: "Access denied")
        snapshot(app, "access-denied")
    }

    func test2_EncryptedKeyLoginAndShell() {
        let app = XCUIApplication(bundleIdentifier: "com.oxapayy.puttyios")
        if let key = env["SSH_KEY"] { app.launchEnvironment["PUTTY_TEST_KEY"] = key }
        app.launch()
        enterDestination(app)

        app.staticTexts["Data"].tap()
        let username = app.textFields.element(boundBy: 0)
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()
        username.typeText(user)
        app.staticTexts["Auth"].tap()
        snapshot(app, "auth-panel")

        app.buttons["Open"].tap()
        acceptHostKeyIfAsked(app, expectFingerprint: false)

        waitForTerminal(app, contains: "Using username \"\(user)\".")
        waitForTerminal(app, contains: "Passphrase for key \"userkey_enc\": ")
        app.typeText("nope\n")
        waitForTerminal(app, contains: "Wrong passphrase")
        app.typeText("\(env["SSH_PASS"] ?? "")\n")
        waitForTerminal(app, contains: "Authenticating with public key \"userkey_enc\"")

        app.typeText("echo PUTTY_$((6*7)); echo COLS=$(tput cols) TERM=$TERM\n")
        waitForTerminal(app, contains: "PUTTY_42")
        waitForTerminal(app, contains: "TERM=xterm")
        snapshot(app, "shell")

        app.typeText("exit\n")
        let closed = app.buttons["Open"].waitForExistence(timeout: 15)
        if !closed { snapshot(app, "after-exit") }
        XCTAssertFalse(app.staticTexts["PuTTY Fatal Error"].exists, "Clean exit reported as fatal error")
        XCTAssertTrue(closed, "Window did not close on clean exit")
    }

    /// Marketing screenshots for the website; runs only when SHOT_DIR and DEMO_SCRIPT are set.
    func test3_WebsiteScreenshots() throws {
        guard env["SHOT_DIR"] != nil, let demo = env["DEMO_SCRIPT"] else { throw XCTSkip("screenshots not requested") }
        let app = XCUIApplication(bundleIdentifier: "com.oxapayy.puttyios")
        if let key = env["SSH_PLAIN_KEY"] { app.launchEnvironment["PUTTY_TEST_KEY"] = key }
        app.launch()
        let saved = app.textFields.element(boundBy: 2)
        for (name, host) in [("Raspberry Pi", "192.168.1.40"), ("Router", "192.168.1.1"), ("Home Server", "127.0.0.1")] {
            let hostField = app.textFields.element(boundBy: 0)
            hostField.tap()
            hostField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + host)
            saved.tap()
            saved.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + name)
            app.buttons["Save"].tap()
        }
        let portField = app.textFields.element(boundBy: 1)
        portField.tap()
        portField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + port)
        app.buttons["Save"].tap()
        app.scrollViews.element(boundBy: 1).swipeDown()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        snapshot(app, "site-config")

        app.staticTexts["Data"].tap()
        let username = app.textFields.element(boundBy: 0)
        username.tap()
        username.typeText(user)
        app.buttons["Open"].tap()
        if app.staticTexts["PuTTY Security Alert"].waitForExistence(timeout: 15) {
            snapshot(app, "site-alert")
            app.buttons["Yes"].tap()
        }
        waitForTerminal(app, contains: "Authenticating with public key")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        app.typeText("source \(demo)\n")
        waitForTerminal(app, contains: "guest@homelab")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        snapshot(app, "site-terminal")
    }
}
