import SwiftUI
import SwiftTerm

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var keyboard = KeyboardObserver()
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            Win.desktop.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    if let s = app.active {
                        TerminalWindow(session: s).id(s.id)
                    } else {
                        configWindow
                    }
                    if let s = app.reconfiguring {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ReconfigWindow(session: s)
                            .padding(sizeClass == .regular ? 60 : 8)
                    }
                }
                if !keyboard.visible { Taskbar() }
            }
            if let dialog = app.dialogs.first {
                Color.black.opacity(0.2).ignoresSafeArea()
                DialogView(dialog: dialog)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var configWindow: some View {
        WinWindow(title: "PuTTY Configuration", showsHelp: true) {
            ConfigView(cfg: $app.draft, reconfig: false, onOpen: { app.open(app.draft) },
                       onCancel: { app.draft = SessionStore.load(SessionStore.defaultName) })
        }
        .frame(maxWidth: sizeClass == .regular ? 640 : .infinity, maxHeight: sizeClass == .regular ? 620 : .infinity)
        .padding(sizeClass == .regular ? 24 : 6)
    }
}

private struct ReconfigWindow: View {
    @EnvironmentObject private var app: AppState
    let session: TerminalSession
    @State private var cfg: SessionConfig

    init(session: TerminalSession) {
        self.session = session
        _cfg = State(initialValue: session.config)
    }

    var body: some View {
        WinWindow(title: "PuTTY Reconfiguration", onClose: { app.reconfiguring = nil }) {
            ConfigView(cfg: $cfg, reconfig: true, onOpen: {
                session.apply(cfg)
                app.reconfiguring = nil
            }, onCancel: { app.reconfiguring = nil })
        }
        .frame(maxWidth: 640, maxHeight: 620)
    }
}

// MARK: Terminal window

struct TerminalWindow: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var session: TerminalSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Menu { systemMenu } label: {
                    PuttyIcon(size: 18).frame(width: 40, height: 34).contentShape(Rectangle())
                }
                Text(session.title)
                    .font(.system(size: 13))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button { session.toggleKeyboard() } label: {
                    Image(systemName: "keyboard").font(.system(size: 14)).foregroundColor(.black)
                        .frame(width: 44, height: 34).contentShape(Rectangle())
                }
                Button { app.requestClose(session) } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .light)).foregroundColor(.black)
                        .frame(width: 46, height: 34).contentShape(Rectangle())
                }
            }
            .frame(height: 34)
            .background(Color.white, ignoresSafeAreaEdges: [])
            TerminalHost(view: session.terminalView)
                .overlay(Color.white.opacity(session.flashing ? 0.5 : 0).allowsHitTesting(false))
                .background(Color(session.terminalView.nativeBackgroundColor))
        }
        .overlay(Rectangle().strokeBorder(Color(rgb: 0x1883D7), lineWidth: 1).allowsHitTesting(false))
    }

    @ViewBuilder private var systemMenu: some View {
        Button { app.activeID = nil } label: { Label("New Session...", systemImage: "plus.rectangle") }
        Button { app.open(session.config) } label: { Label("Duplicate Session", systemImage: "plus.square.on.square") }
        Button { session.restart() } label: { Label("Restart Session", systemImage: "arrow.clockwise") }
            .disabled(session.state != .closed)
        let saved = SessionStore.names.filter { $0 != SessionStore.defaultName }
        if !saved.isEmpty {
            Menu {
                ForEach(saved, id: \.self) { name in
                    Button(name) { app.open(SessionStore.load(name)) }
                }
            } label: { Label("Saved Sessions", systemImage: "folder") }
        }
        Button { app.reconfiguring = session } label: { Label("Change Settings...", systemImage: "gearshape") }
        Divider()
        Button { session.copyAll() } label: { Label("Copy All to Clipboard", systemImage: "doc.on.doc") }
        Button { session.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
        Button { session.clearScrollback() } label: { Label("Clear Scrollback", systemImage: "scroll") }
        Button { session.resetTerminal() } label: { Label("Reset Terminal", systemImage: "arrow.counterclockwise") }
        Divider()
        Button { app.showAbout() } label: { Label("About PuTTY", systemImage: "info.circle") }
        Button(role: .destructive) { app.requestClose(session) } label: { Label("Close", systemImage: "xmark") }
    }
}

private struct TerminalHost: UIViewRepresentable {
    let view: TerminalView

    func makeUIView(context: Context) -> TerminalView {
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}
}

// MARK: Taskbar

private struct Taskbar: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 2) {
            item(title: "PuTTY Configuration", active: app.activeID == nil) { app.activeID = nil }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(app.sessions) { s in
                        TaskItem(session: s, active: app.activeID == s.id) { app.activeID = s.id }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 44)
        .background(Win.taskbar.ignoresSafeArea(edges: .bottom))
    }

    private func item(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { TaskLabel(title: title, active: active, dimmed: false) }.buttonStyle(.plain)
    }
}

private struct TaskItem: View {
    @ObservedObject var session: TerminalSession
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TaskLabel(title: session.title, active: active, dimmed: session.state == .closed)
        }
        .buttonStyle(.plain)
    }
}

private struct TaskLabel: View {
    let title: String
    let active: Bool
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            PuttyIcon(size: 18).opacity(dimmed ? 0.5 : 1)
            Text(title).font(.system(size: 12)).foregroundColor(.white).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: 190, minHeight: 40, maxHeight: 40)
        .background(active ? Color.white.opacity(0.16) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(active ? Color(rgb: 0x76B9ED) : Color.clear).frame(height: 2)
        }
        .contentShape(Rectangle())
    }
}

// MARK: Message box

private struct DialogView: View {
    @EnvironmentObject private var app: AppState
    let dialog: DialogModel

    var body: some View {
        WinWindow(title: dialog.title, onClose: { app.resolve(dialog, with: dialog.buttons.last ?? DialogButton(title: "")) }) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    icon.font(.system(size: 30))
                    ScrollView {
                        Text(dialog.message)
                            .font(Win.font)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 380)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(Array(dialog.buttons.enumerated()), id: \.offset) { _, b in
                        WinButton(b.title, isDefault: b.isDefault) { app.resolve(dialog, with: b) }
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: 460)
        .padding(14)
    }

    @ViewBuilder private var icon: some View {
        switch dialog.icon {
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.palette).foregroundStyle(.black, Color(rgb: 0xFFC83D))
        case .error:
            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Color(rgb: 0xE81123))
        case .info:
            Image(systemName: "info.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Win.accent)
        case .question:
            Image(systemName: "questionmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Win.accent)
        }
    }
}
