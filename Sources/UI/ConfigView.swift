import SwiftUI
import UniformTypeIdentifiers

enum Category: String, CaseIterable, Identifiable {
    case session, terminal, keyboard, bell, window, appearance, behaviour, colours, connection, data, ssh, auth, telnet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ssh: return "SSH"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var children: [Category] {
        switch self {
        case .terminal: return [.keyboard, .bell]
        case .window: return [.appearance, .behaviour, .colours]
        case .connection: return [.data, .ssh, .telnet]
        case .ssh: return [.auth]
        default: return []
        }
    }

    var header: String {
        switch self {
        case .session: return "Basic options for your PuTTY session"
        case .terminal: return "Options controlling the terminal emulation"
        case .keyboard: return "Options controlling the effects of keys"
        case .bell: return "Options controlling the terminal bell"
        case .window: return "Options controlling PuTTY's window"
        case .appearance: return "Configure the appearance of PuTTY's window"
        case .behaviour: return "Configure the behaviour of PuTTY's window"
        case .colours: return "Options controlling use of colours"
        case .connection: return "Options controlling the connection"
        case .data: return "Data to send to the server"
        case .ssh: return "Options controlling SSH connections"
        case .auth: return "Options controlling SSH authentication"
        case .telnet: return "Options controlling Telnet connections"
        }
    }
}

struct ConfigView: View {
    @EnvironmentObject private var app: AppState
    @Binding var cfg: SessionConfig
    let reconfig: Bool
    let onOpen: () -> Void
    let onCancel: () -> Void

    @State private var category: Category
    @State private var expanded: Set<Category> = [.terminal, .window, .connection, .ssh]
    @State private var savedName = ""
    @State private var selectedSaved: String?
    @State private var savedNames = SessionStore.names
    @State private var importingKey = false
    @State private var hostKeyRevision = 0

    init(cfg: Binding<SessionConfig>, reconfig: Bool, onOpen: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _cfg = cfg
        self.reconfig = reconfig
        self.onOpen = onOpen
        self.onCancel = onCancel
        _category = State(initialValue: reconfig ? .terminal : .session)
    }

    private var roots: [Category] { reconfig ? [.terminal, .window] : [.session, .terminal, .window, .connection] }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if geo.size.width >= 560 {
                    HStack(alignment: .top, spacing: 8) {
                        categoryTree.frame(width: 170)
                        panel
                    }
                    .padding(8)
                } else {
                    VStack(spacing: 8) {
                        categoryTree.frame(height: min(196, geo.size.height * 0.3))
                        panel
                    }
                    .padding(8)
                }
                buttonBar
            }
        }
        .fileImporter(isPresented: $importingKey, allowedContentTypes: [.item], onCompletion: importKey)
    }

    // MARK: Tree

    private var visibleNodes: [(Category, Int)] {
        var out: [(Category, Int)] = []
        func walk(_ c: Category, _ depth: Int) {
            out.append((c, depth))
            if expanded.contains(c) { c.children.forEach { walk($0, depth + 1) } }
        }
        roots.forEach { walk($0, 0) }
        return out
    }

    private var categoryTree: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Category:").font(Win.font).foregroundColor(.black)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleNodes, id: \.0) { node, depth in treeRow(node, depth) }
                }
                .padding(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            .overlay(Rectangle().strokeBorder(Win.treeBorder, lineWidth: 1))
        }
    }

    private func treeRow(_ node: Category, _ depth: Int) -> some View {
        let selected = node == category
        return HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(depth) * 16)
            Group {
                if node.children.isEmpty {
                    Color.clear
                } else {
                    Button {
                        if expanded.contains(node) { expanded.remove(node) } else { expanded.insert(node) }
                    } label: {
                        ZStack {
                            Rectangle().fill(Color.white).frame(width: 9, height: 9)
                            Rectangle().strokeBorder(Color(rgb: 0x919191), lineWidth: 1).frame(width: 9, height: 9)
                            Text(expanded.contains(node) ? "−" : "+").font(.system(size: 9, weight: .medium)).foregroundColor(Win.glyph)
                        }
                        .frame(width: 22, height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 22, height: 26)
            Text(node.title)
                .font(Win.font)
                .foregroundColor(.black)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(selected ? Win.treeSelection : Color.clear)
                .overlay(Rectangle().strokeBorder(selected ? Win.treeSelectionBorder : Color.clear, lineWidth: 1))
            Spacer(minLength: 0)
        }
        .frame(height: 26)
        .contentShape(Rectangle())
        .onTapGesture { category = node }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category.header)
                .font(Win.font)
                .foregroundColor(.black)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().strokeBorder(Win.groupLine, lineWidth: 1))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { panelContent }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .foregroundColor(.black)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var panelContent: some View {
        switch category {
        case .session: sessionPanel
        case .terminal: terminalPanel
        case .keyboard: keyboardPanel
        case .bell: bellPanel
        case .window: windowPanel
        case .appearance: appearancePanel
        case .behaviour: behaviourPanel
        case .colours: coloursPanel
        case .connection: connectionPanel
        case .data: dataPanel
        case .ssh: sshPanel
        case .auth: authPanel
        case .telnet: telnetPanel
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(Win.font).foregroundColor(.black).fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ s: String) -> some View {
        Text(s).font(Win.small).foregroundColor(Color(rgb: 0x555555)).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Session

    private var sessionPanel: some View {
        Group {
            WinGroupBox("Specify the destination you want to connect to") {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        label("Host Name (or IP address)")
                        WinTextField(text: $cfg.host, keyboard: .URL)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        label("Port")
                        WinNumberField(value: $cfg.port, range: 0...65535).frame(width: 66)
                    }
                }
                label("Connection type:").padding(.top, 2)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { typeRadios(ConnectionType.allCases) }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) { typeRadios([.raw, .telnet, .rlogin]) }
                        HStack(spacing: 12) { typeRadios([.ssh, .serial]) }
                    }
                }
            }
            WinGroupBox("Load, save or delete a stored session") {
                label("Saved Sessions")
                WinTextField(text: $savedName)
                HStack(alignment: .top, spacing: 8) {
                    savedList
                    VStack(spacing: 8) {
                        WinButton("Load", minWidth: 70, action: loadSession)
                        WinButton("Save", minWidth: 70, action: saveSession)
                        WinButton("Delete", minWidth: 70, action: deleteSession)
                            .disabled(selectedSaved == nil || selectedSaved == SessionStore.defaultName)
                    }
                }
            }
            WinGroupBox("Close window on exit:") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { closeRadios }
                    VStack(alignment: .leading, spacing: 0) { closeRadios }
                }
            }
        }
    }

    @ViewBuilder private func typeRadios(_ types: [ConnectionType]) -> some View {
        ForEach(types, id: \.self) { t in
            WinRadio(label: t.label, selected: cfg.type == t, enabled: t.isAvailable) { setType(t) }
        }
    }

    @ViewBuilder private var closeRadios: some View {
        WinRadio(label: "Always", selected: cfg.closeOnExit == .always) { cfg.closeOnExit = .always }
        WinRadio(label: "Never", selected: cfg.closeOnExit == .never) { cfg.closeOnExit = .never }
        WinRadio(label: "Only on clean exit", selected: cfg.closeOnExit == .clean) { cfg.closeOnExit = .clean }
    }

    private var savedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(savedNames, id: \.self) { name in
                    let selected = name == selectedSaved
                    Text(name)
                        .font(Win.font)
                        .foregroundColor(selected ? .white : .black)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .background(selected ? Win.accent : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            selectedSaved = name
                            savedName = name
                            cfg = SessionStore.load(name)
                            openTapped()
                        }
                        .onTapGesture {
                            selectedSaved = name
                            savedName = name
                        }
                }
            }
        }
        .frame(height: 160)
        .background(Color.white)
        .overlay(Rectangle().strokeBorder(Win.fieldBorder, lineWidth: 1))
    }

    private func setType(_ t: ConnectionType) {
        if t == .ssh && cfg.port == 23 { cfg.port = 22 }
        if t == .telnet && cfg.port == 22 { cfg.port = 23 }
        cfg.type = t
    }

    private func loadSession() {
        dismissKeyboard()
        let name = selectedSaved ?? (savedNames.contains(savedName) ? savedName : nil)
        guard let name else { return }
        cfg = SessionStore.load(name)
        selectedSaved = name
        savedName = name
    }

    private func saveSession() {
        dismissKeyboard()
        var name = savedName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = selectedSaved ?? "" }
        guard !name.isEmpty else { return }
        SessionStore.save(cfg, as: name)
        savedNames = SessionStore.names
        selectedSaved = name
        savedName = name
    }

    private func deleteSession() {
        dismissKeyboard()
        guard let name = selectedSaved, name != SessionStore.defaultName else { return }
        SessionStore.delete(name)
        savedNames = SessionStore.names
        selectedSaved = nil
        savedName = ""
    }

    // MARK: Terminal

    private var terminalPanel: some View {
        Group {
            WinGroupBox("Set various terminal options") {
                WinCheckbox(label: "Implicit CR in every LF", isOn: $cfg.implicitCR)
                WinCheckbox(label: "Implicit LF in every CR", isOn: $cfg.implicitLF)
            }
            WinGroupBox("Line discipline options") {
                label("Local echo:")
                HStack(spacing: 12) {
                    WinRadio(label: "Auto", selected: cfg.localEcho == .auto) { cfg.localEcho = .auto }
                    WinRadio(label: "Force on", selected: cfg.localEcho == .on) { cfg.localEcho = .on }
                    WinRadio(label: "Force off", selected: cfg.localEcho == .off) { cfg.localEcho = .off }
                }
            }
        }
    }

    private var keyboardPanel: some View {
        Group {
            WinGroupBox("Change the sequences sent by:") {
                label("The Backspace key")
                HStack(spacing: 12) {
                    WinRadio(label: "Control-H", selected: cfg.backspace == .controlH) { cfg.backspace = .controlH }
                    WinRadio(label: "Control-? (127)", selected: cfg.backspace == .control127) { cfg.backspace = .control127 }
                }
            }
            WinGroupBox("Modifier keys") {
                WinCheckbox(label: "Option key on a hardware keyboard acts as Meta (Alt)", isOn: $cfg.altIsMeta)
            }
        }
    }

    private var bellPanel: some View {
        WinGroupBox("Set the style of bell") {
            label("Action to happen when a bell occurs:")
            WinRadio(label: "None (bell disabled)", selected: cfg.bell == .none) { cfg.bell = .none }
            WinRadio(label: "Vibrate (haptic feedback)", selected: cfg.bell == .haptic) { cfg.bell = .haptic }
            WinRadio(label: "Visual bell (flash window)", selected: cfg.bell == .visual) { cfg.bell = .visual }
        }
    }

    // MARK: Window

    private var windowPanel: some View {
        Group {
            WinGroupBox("Set the size of the window") {
                note("The terminal always fills the screen. Rows and columns follow the window size and font size; pinch the terminal to zoom.")
            }
            WinGroupBox("Control the scrollback in the window") {
                HStack {
                    label("Lines of scrollback")
                    Spacer()
                    WinNumberField(value: $cfg.scrollback, range: 0...100_000).frame(width: 90)
                }
            }
        }
    }

    private var appearancePanel: some View {
        Group {
            WinGroupBox("Adjust the use of the cursor") {
                label("Cursor appearance:")
                HStack(spacing: 12) {
                    WinRadio(label: "Block", selected: cfg.cursor == .block) { cfg.cursor = .block }
                    WinRadio(label: "Underline", selected: cfg.cursor == .underline) { cfg.cursor = .underline }
                    WinRadio(label: "Vertical line", selected: cfg.cursor == .bar) { cfg.cursor = .bar }
                }
                WinCheckbox(label: "Cursor blinks", isOn: $cfg.cursorBlinks)
            }
            WinGroupBox("Font settings") {
                HStack(spacing: 8) {
                    label("Font:")
                    WinDropdown(options: TermFont.allCases.map { ($0, $0.label) }, selection: $cfg.font)
                }
                HStack(spacing: 8) {
                    label("Size:")
                    WinButton("−", minWidth: 40) { cfg.fontSize = max(6, cfg.fontSize - 1) }
                    Text("\(Int(cfg.fontSize)) pt").font(Win.font).frame(width: 50)
                    WinButton("+", minWidth: 40) { cfg.fontSize = min(36, cfg.fontSize + 1) }
                }
                let palette = TerminalPalette.scheme(cfg.colours)
                Text("login as: root\nroot@server:~# ls -la")
                    .font(Font(TerminalFonts.preview(cfg.font, size: cfg.fontSize)))
                    .foregroundColor(Color(TerminalPalette.ui(palette.foreground)))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(TerminalPalette.ui(palette.background)))
                    .overlay(Rectangle().strokeBorder(Win.fieldBorder, lineWidth: 1))
            }
        }
    }

    private var behaviourPanel: some View {
        Group {
            WinGroupBox("Adjust the behaviour of the window title") {
                label("Window title:")
                WinTextField(text: $cfg.windowTitle)
                note("Leave blank to use \"host - PuTTY\" or the title set by the server.")
            }
            WinGroupBox("Closing the window") {
                WinCheckbox(label: "Warn before closing window", isOn: $cfg.warnOnClose)
            }
        }
    }

    private var coloursPanel: some View {
        WinGroupBox("Select a colour scheme") {
            ForEach(ColourScheme.allCases, id: \.self) { s in
                WinRadio(label: s.label, selected: cfg.colours == s) { cfg.colours = s }
            }
            let palette = TerminalPalette.scheme(cfg.colours)
            VStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<8, id: \.self) { col in
                            Rectangle().fill(Color(TerminalPalette.ui(palette.ansi[row * 8 + col]))).frame(height: 16)
                        }
                    }
                }
            }
            .padding(4)
            .background(Color(TerminalPalette.ui(palette.background)))
            .overlay(Rectangle().strokeBorder(Win.fieldBorder, lineWidth: 1))
        }
    }

    // MARK: Connection

    private var connectionPanel: some View {
        Group {
            WinGroupBox("Sending of null packets to keep session active") {
                HStack {
                    label("Seconds between keepalives (0 to turn off)")
                    Spacer()
                    WinNumberField(value: $cfg.keepaliveSeconds, range: 0...3600).frame(width: 60)
                }
            }
            WinGroupBox("Low-level TCP connection options") {
                WinCheckbox(label: "Disable Nagle's algorithm (TCP_NODELAY option)", isOn: $cfg.noDelay)
            }
        }
    }

    private var dataPanel: some View {
        Group {
            WinGroupBox("Login details") {
                label("Auto-login username")
                WinTextField(text: $cfg.username)
                note("When empty, PuTTY asks \"login as:\" in the terminal window.")
            }
            WinGroupBox("Terminal details") {
                label("Terminal-type string")
                WinTextField(text: $cfg.termType)
            }
        }
    }

    private var sshPanel: some View {
        Group {
            WinGroupBox("Host keys") {
                let _ = hostKeyRevision
                let host = cfg.host.trimmingCharacters(in: .whitespaces)
                if let key = HostKeyStore.get(host: host, port: cfg.port) {
                    label("Cached host key for \(host):\(cfg.port):")
                    Text(HostKeyInfo.fingerprint(key))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.black)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    WinButton("Forget Key") {
                        HostKeyStore.remove(host: host, port: cfg.port)
                        hostKeyRevision += 1
                    }
                } else {
                    note(host.isEmpty
                         ? "Enter a host name on the Session panel to see its cached key."
                         : "No host key is cached for \(host):\(cfg.port). PuTTY will ask you to verify it on the first connection.")
                }
            }
            WinGroupBox("Supported algorithms") {
                note("""
                Key exchange: curve25519-sha256, ecdh-sha2-nistp256/384/521, diffie-hellman-group14-sha256/sha1
                Host keys: ssh-ed25519, ecdsa-sha2-nistp256/384/521, ssh-rsa
                Ciphers: aes128-gcm, aes256-gcm, aes128-ctr
                """)
            }
        }
    }

    private var authPanel: some View {
        Group {
            WinGroupBox("Authentication methods") {
                WinCheckbox(label: "Attempt authentication using password", isOn: $cfg.tryPassword)
            }
            WinGroupBox("Authentication parameters") {
                label("Private key file for authentication:")
                HStack(spacing: 8) {
                    Text(cfg.keyName ?? "")
                        .font(Win.font)
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .background(Color.white)
                        .overlay(Rectangle().strokeBorder(Win.fieldBorder, lineWidth: 1))
                    WinButton("Browse...", minWidth: 80) { importingKey = true }
                }
                if cfg.keyID != nil {
                    WinButton("Remove Key") {
                        releaseKey(cfg.keyID)
                        cfg.keyID = nil
                        cfg.keyName = nil
                    }
                }
                note("OpenSSH or PuTTY .ppk keys (Ed25519, RSA). The key is copied into the iOS Keychain; passphrases are asked for at login and never stored.")
            }
        }
    }

    private var telnetPanel: some View {
        WinGroupBox("Telnet protocol adjustments") {
            WinCheckbox(label: "Return key sends Telnet New Line instead of ^M", isOn: $cfg.telnetNewLine)
        }
    }

    // MARK: Actions

    private var buttonBar: some View {
        HStack(spacing: 8) {
            if !reconfig { WinButton("About") { app.showAbout() } }
            Spacer()
            WinButton(reconfig ? "Apply" : "Open", isDefault: true, action: openTapped)
            WinButton("Cancel", action: onCancel)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func openTapped() {
        dismissKeyboard()
        guard !reconfig else { onOpen(); return }
        var host = cfg.host.trimmingCharacters(in: .whitespaces)
        if host.isEmpty, let name = selectedSaved {
            cfg = SessionStore.load(name)
            host = cfg.host.trimmingCharacters(in: .whitespaces)
        }
        if let at = host.lastIndex(of: "@") {
            cfg.username = String(host[..<at])
            host = String(host[host.index(after: at)...])
        }
        cfg.host = host
        guard !host.isEmpty else {
            app.showDialog(title: "PuTTY Error", message: "You must enter a host name before opening a session.", icon: .error,
                           buttons: [DialogButton(title: "OK", isDefault: true)])
            return
        }
        onOpen()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func importKey(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            _ = try PrivateKeyFile(data: data)
            guard let id = KeyStore.add(data) else { throw KeyFileError.unrecognised }
            releaseKey(cfg.keyID)
            cfg.keyID = id
            cfg.keyName = name
        } catch {
            app.showDialog(title: "PuTTY Error", message: "Unable to load key file \"\(name)\":\n\(error.localizedDescription)",
                           icon: .error, buttons: [DialogButton(title: "OK", isDefault: true)])
        }
    }

    /// Removes a key from the Keychain once no saved or running session uses it.
    private func releaseKey(_ id: String?) {
        guard let id else { return }
        let inUse = SessionStore.names.contains { SessionStore.load($0).keyID == id } || app.sessions.contains { $0.config.keyID == id }
        if !inUse { KeyStore.delete(id: id) }
    }
}
