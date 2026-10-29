import Foundation

enum ConnectionType: String, Codable, CaseIterable {
    case raw, telnet, rlogin, ssh, serial

    var label: String {
        switch self {
        case .raw: return "Raw"
        case .telnet: return "Telnet"
        case .rlogin: return "Rlogin"
        case .ssh: return "SSH"
        case .serial: return "Serial"
        }
    }

    /// Rlogin needs a privileged source port and serial lines do not exist on iOS.
    var isAvailable: Bool { self != .rlogin && self != .serial }
}

enum CloseOnExit: String, Codable { case always, never, clean }
enum BackspaceKey: String, Codable { case controlH, control127 }
enum BellStyle: String, Codable { case none, haptic, visual }
enum CursorShape: String, Codable { case block, underline, bar }
enum LocalOption: String, Codable { case auto, on, off }

enum TermFont: String, Codable, CaseIterable {
    case courierNew, menlo, systemMono

    var label: String {
        switch self {
        case .courierNew: return "Courier New"
        case .menlo: return "Menlo"
        case .systemMono: return "SF Mono"
        }
    }
}

enum ColourScheme: String, Codable, CaseIterable {
    case puttyDefault, xterm, blackOnWhite, greenOnBlack, solarizedDark

    var label: String {
        switch self {
        case .puttyDefault: return "PuTTY Default"
        case .xterm: return "xterm"
        case .blackOnWhite: return "Black on White"
        case .greenOnBlack: return "Green on Black"
        case .solarizedDark: return "Solarized Dark"
        }
    }
}

struct SessionConfig: Codable, Equatable {
    // Session
    var host = ""
    var port = 22
    var type: ConnectionType = .ssh
    var closeOnExit: CloseOnExit = .clean

    // Terminal
    var implicitCR = false
    var implicitLF = false
    var localEcho: LocalOption = .auto
    var backspace: BackspaceKey = .control127
    var altIsMeta = true
    var bell: BellStyle = .haptic

    // Window
    var scrollback = 2000
    var font: TermFont = .courierNew
    var fontSize: Double = 12
    var cursor: CursorShape = .block
    var cursorBlinks = false
    var windowTitle = ""
    var warnOnClose = true
    var colours: ColourScheme = .puttyDefault

    // Connection
    var keepaliveSeconds = 0
    var noDelay = true
    var username = ""
    var termType = "xterm"

    // SSH
    var keyID: String?
    var keyName: String?
    var tryPassword = true

    // Telnet
    var telnetNewLine = true

    var displayTitle: String {
        if !windowTitle.isEmpty { return windowTitle }
        return host.isEmpty ? "PuTTY" : "\(host) - PuTTY"
    }

    /// Decodes on top of the defaults, so sessions saved by older builds keep loading.
    static func decode(_ data: Data) -> SessionConfig? {
        guard let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(SessionConfig())) as? [String: Any]
        else { return nil }
        let merged = defaults.merging(stored) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(SessionConfig.self, from: mergedData)
    }
}
