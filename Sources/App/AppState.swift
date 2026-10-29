import SwiftUI
import Combine

enum DialogIcon { case warning, error, info, question }

struct DialogButton {
    let title: String
    var isDefault = false
    var action: () -> Void = {}
}

struct DialogModel: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let icon: DialogIcon
    let buttons: [DialogButton]
}

@MainActor final class AppState: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var activeID: UUID?
    @Published var draft = SessionStore.load(SessionStore.defaultName)
    @Published var reconfiguring: TerminalSession?
    @Published private(set) var dialogs: [DialogModel] = []

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var active: TerminalSession? { sessions.first { $0.id == activeID } }

    init() {
        #if DEBUG
        // UI tests hand in a private key file instead of driving the document picker.
        if let path = ProcessInfo.processInfo.environment["PUTTY_TEST_KEY"],
           let data = FileManager.default.contents(atPath: path), let id = KeyStore.add(data) {
            draft.keyID = id
            draft.keyName = (path as NSString).lastPathComponent
        }
        #endif
    }

    func open(_ cfg: SessionConfig) {
        let s = TerminalSession(config: cfg, app: self)
        sessions.append(s)
        activeID = s.id
        s.start()
    }

    func requestClose(_ s: TerminalSession) {
        guard s.config.warnOnClose, s.state != .closed else { closeSession(s); return }
        showDialog(title: "PuTTY Exit Confirmation", message: "Are you sure you want to close this session?", icon: .question, buttons: [
            DialogButton(title: "OK", isDefault: true) { [weak self, weak s] in
                guard let self, let s else { return }
                self.closeSession(s)
            },
            DialogButton(title: "Cancel"),
        ])
    }

    func closeSession(_ s: TerminalSession) {
        s.disconnect()
        sessions.removeAll { $0.id == s.id }
        if reconfiguring?.id == s.id { reconfiguring = nil }
        if activeID == s.id { activeID = nil }
    }

    func showDialog(title: String, message: String, icon: DialogIcon, buttons: [DialogButton]) {
        dialogs.append(DialogModel(title: title, message: message, icon: icon, buttons: buttons))
    }

    func resolve(_ dialog: DialogModel, with button: DialogButton) {
        dialogs.removeAll { $0.id == dialog.id }
        button.action()
    }

    func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        showDialog(title: "About PuTTY", message: """
        PuTTY for iOS
        Release \(version)

        SSH, Telnet and Raw client for iPhone and iPad, modelled on PuTTY by Simon Tatham.

        Terminal emulation: SwiftTerm
        SSH: Citadel / SwiftNIO SSH

        Nothing is logged. Saved sessions never contain passwords; private keys are kept in the iOS Keychain.
        """, icon: .info, buttons: [DialogButton(title: "OK", isDefault: true)])
    }

    /// Asks iOS for a little extra time so connections survive a quick app switch.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard backgroundTask == .invalid, sessions.contains(where: { $0.state != .closed }) else { return }
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in self?.endBackgroundTask() }
        case .active:
            endBackgroundTask()
        default:
            break
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

final class KeyboardObserver: ObservableObject {
    @Published var visible = false
    private var bag = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.visible = true }.store(in: &bag)
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.visible = false }.store(in: &bag)
    }
}
