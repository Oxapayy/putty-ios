import UIKit
import SwiftTerm

enum HostKeyDecision { case accept, once, cancel }

@MainActor final class TerminalSession: NSObject, ObservableObject, Identifiable, TerminalViewDelegate {
    enum State { case connecting, connected, closed }

    let id = UUID()
    @Published private(set) var config: SessionConfig
    @Published private(set) var state: State = .connecting
    @Published private(set) var remoteTitle: String?
    @Published private(set) var flashing = false

    weak var app: AppState?
    let terminalView: TerminalView
    private var connection: RemoteConnection?
    private var prompt: Prompt?
    private var pinchStartSize: Double = 12

    private struct Prompt {
        let echo: Bool
        var buffer: [UInt8] = []
        let done: (String?) -> Void
    }

    var title: String {
        let base = config.windowTitle.isEmpty ? (remoteTitle ?? config.displayTitle) : config.windowTitle
        return state == .closed ? "\(base) (inactive)" : base
    }

    init(config: SessionConfig, app: AppState) {
        self.config = config
        self.app = app
        terminalView = PuttyTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        super.init()
        terminalView.terminalDelegate = self
        terminalView.keyboardAppearance = .dark
        terminalView.accessibilityIdentifier = "terminal"
        terminalView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
        apply(config)
    }

    // MARK: Lifecycle

    func start() {
        state = .connecting
        remoteTitle = nil
        let c: RemoteConnection
        switch config.type {
        case .ssh: c = SSHConnection(session: self, config: config)
        case .telnet: c = TCPConnection(session: self, config: config, telnet: true)
        case .raw: c = TCPConnection(session: self, config: config, telnet: false)
        case .rlogin, .serial:
            connectionClosed(error: "\(config.type.label) connections are not supported on iOS")
            return
        }
        connection = c
        let size = terminalView.terminalDimensions
        c.resize(cols: size.cols, rows: size.rows)
        c.start()
    }

    func restart() {
        guard state == .closed else { return }
        print("\r\n")
        start()
    }

    func disconnect() {
        connection?.close()
        connection = nil
        cancelPrompt()
        state = .closed
    }

    /// Applies settings that can change while the session runs ("Change Settings").
    func apply(_ cfg: SessionConfig) {
        config = cfg
        let tv = terminalView
        TerminalFonts.set(on: tv, font: cfg.font, size: cfg.fontSize)
        tv.changeScrollback(max(0, cfg.scrollback))
        let palette = TerminalPalette.scheme(cfg.colours)
        tv.installColors(palette.swiftTermColors)
        tv.nativeForegroundColor = TerminalPalette.ui(palette.foreground)
        tv.nativeBackgroundColor = TerminalPalette.ui(palette.background)
        tv.caretColor = TerminalPalette.ui(palette.cursor)
        tv.backgroundColor = TerminalPalette.ui(palette.background)
        tv.backspaceSendsControlH = cfg.backspace == .controlH
        tv.optionAsMetaKey = cfg.altIsMeta
        let style: CursorStyle
        switch cfg.cursor {
        case .block: style = cfg.cursorBlinks ? .blinkBlock : .steadyBlock
        case .underline: style = cfg.cursorBlinks ? .blinkUnderline : .steadyUnderline
        case .bar: style = cfg.cursorBlinks ? .blinkBar : .steadyBar
        }
        tv.setCursorStyle(style)
        tv.setNeedsDisplay()
    }

    // MARK: Called by connections

    func connectionEstablished() {
        state = .connected
    }

    func received(_ bytes: [UInt8]) {
        var data = bytes
        if config.implicitCR || config.implicitLF {
            data = []
            data.reserveCapacity(bytes.count)
            for b in bytes {
                if b == 10 && config.implicitCR { data.append(13) }
                data.append(b)
                if b == 13 && config.implicitLF { data.append(10) }
            }
        }
        terminalView.feed(byteArray: data[...])
    }

    func print(_ text: String) {
        terminalView.feed(text: text)
    }

    /// Reads a line typed into the terminal, like PuTTY's "login as:" and password prompts.
    func ask(_ text: String, echo: Bool) async -> String? {
        cancelPrompt()
        print(text)
        return await withCheckedContinuation { cont in
            prompt = Prompt(echo: echo, done: { cont.resume(returning: $0) })
        }
    }

    func confirmHostKey(_ key: String, previous: String?) async -> HostKeyDecision {
        guard let app else { return .cancel }
        let fp = HostKeyInfo.fingerprint(key)
        let type = fp.split(separator: " ").first.map(String.init) ?? "host"
        let message: String
        let icon: DialogIcon
        if previous == nil {
            icon = .warning
            message = """
            The server's host key is not cached. You have no guarantee that the server is the computer you think it is.

            The server's \(type) key fingerprint is:
            \(fp)

            If you trust this host, hit Yes to add the key to PuTTY's cache and carry on connecting.
            If you want to carry on connecting just once, without adding the key to the cache, hit No.
            If you do not trust this host, hit Cancel to abandon the connection.
            """
        } else {
            icon = .error
            message = """
            WARNING - POTENTIAL SECURITY BREACH!

            The server's host key does not match the one PuTTY has cached. This means that either the server administrator has changed the host key, or you have actually connected to another computer pretending to be the server.

            The new \(type) key fingerprint is:
            \(fp)

            If you were expecting this change and trust the new key, hit Yes to update PuTTY's cache and continue connecting.
            If you want to carry on connecting but without updating the cache, hit No.
            If you want to abandon the connection completely, hit Cancel. Hitting Cancel is the ONLY guaranteed safe choice.
            """
        }
        return await withCheckedContinuation { cont in
            app.showDialog(title: "PuTTY Security Alert", message: message, icon: icon, buttons: [
                DialogButton(title: "Yes", isDefault: previous == nil) { cont.resume(returning: .accept) },
                DialogButton(title: "No") { cont.resume(returning: .once) },
                DialogButton(title: "Cancel", isDefault: previous != nil) { cont.resume(returning: .cancel) },
            ])
        }
    }

    func connectionClosed(error: String?) {
        guard state != .closed else { return }
        connection = nil
        cancelPrompt()
        state = .closed
        let shouldClose = config.closeOnExit == .always || (config.closeOnExit == .clean && error == nil)
        if let error {
            app?.showDialog(title: "PuTTY Fatal Error", message: error, icon: .error, buttons: [
                DialogButton(title: "OK", isDefault: true) { [weak self] in
                    guard let self, shouldClose else { return }
                    self.app?.closeSession(self)
                },
            ])
        } else if shouldClose {
            app?.closeSession(self)
        }
    }

    /// The user cancelled a prompt or rejected the host key.
    func abort() {
        disconnect()
        app?.closeSession(self)
    }

    // MARK: Menu actions

    func copyAll() {
        let data = terminalView.getBufferAsData(kind: .normal)
        UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
    }

    func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        terminalView.pasteText(text)
    }

    func clearScrollback() {
        terminalView.clearScrollback()
    }

    func resetTerminal() {
        terminalView.resetToInitialState()
        apply(config)
    }

    func toggleKeyboard() {
        if terminalView.isFirstResponder {
            _ = terminalView.resignFirstResponder()
        } else {
            _ = terminalView.becomeFirstResponder()
        }
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchStartSize = config.fontSize
        case .changed:
            let size = (pinchStartSize * Double(g.scale)).rounded()
            let clamped = min(36, max(6, size))
            if clamped != config.fontSize {
                var cfg = config
                cfg.fontSize = clamped
                config = cfg
                TerminalFonts.set(on: terminalView, font: cfg.font, size: clamped)
            }
        default:
            break
        }
    }

    // MARK: Prompt input

    private func cancelPrompt() {
        guard let p = prompt else { return }
        prompt = nil
        p.done(nil)
    }

    private func handlePrompt(_ bytes: [UInt8]) {
        guard var p = prompt else { return }
        for b in bytes {
            switch b {
            case 13, 10:
                prompt = nil
                print("\r\n")
                p.done(String(decoding: p.buffer, as: UTF8.self))
                return
            case 3, 4:
                prompt = nil
                print("\r\n")
                p.done(nil)
                return
            case 8, 127:
                guard !p.buffer.isEmpty else { continue }
                while let last = p.buffer.popLast(), last & 0xC0 == 0x80 {}
                if p.echo { print("\u{8} \u{8}") }
            case 21:
                if p.echo { print(String(repeating: "\u{8} \u{8}", count: String(decoding: p.buffer, as: UTF8.self).count)) }
                p.buffer.removeAll()
            case 27:
                prompt = p
                return
            default:
                guard b >= 32 else { continue }
                p.buffer.append(b)
                if p.echo { terminalView.feed(byteArray: [b]) }
            }
        }
        prompt = p
    }

    private var localEcho: Bool {
        switch config.localEcho {
        case .on: return true
        case .off: return false
        case .auto: return config.type != .ssh && !(connection?.serverEchoes ?? true)
        }
    }

    // MARK: TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = Array(data)
        if prompt != nil {
            handlePrompt(bytes)
            return
        }
        guard state == .connected, let connection else { return }
        if localEcho {
            var echo: [UInt8] = []
            for b in bytes { if b == 13 { echo += [13, 10] } else { echo.append(b) } }
            terminalView.feed(byteArray: echo[...])
        }
        connection.send(bytes)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        connection?.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        remoteTitle = title.isEmpty ? nil : title
    }

    func bell(source: TerminalView) {
        switch config.bell {
        case .none:
            break
        case .haptic:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .visual:
            flashing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.flashing = false }
        }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.string = String(decoding: content, as: UTF8.self)
    }

    func clipboardRead(source: TerminalView) -> Data? { nil }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        UIApplication.shared.open(url)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}
