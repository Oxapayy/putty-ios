import Foundation
import Network

/// Raw TCP and Telnet (RFC 854) connections.
@MainActor final class TCPConnection: RemoteConnection {
    private enum T {
        static let IAC: UInt8 = 255, DONT: UInt8 = 254, DO: UInt8 = 253, WONT: UInt8 = 252, WILL: UInt8 = 251
        static let SB: UInt8 = 250, SE: UInt8 = 240
        static let ECHO: UInt8 = 1, SGA: UInt8 = 3, TTYPE: UInt8 = 24, NAWS: UInt8 = 31
    }
    private enum ParseState { case data, iac, command(UInt8), sub, subIAC }

    private weak var session: TerminalSession?
    private let cfg: SessionConfig
    private let telnet: Bool
    private var connection: NWConnection?
    private var closed = false
    private var size = (cols: 80, rows: 24)

    private var parse = ParseState.data
    private var subBuffer: [UInt8] = []
    private var localOn = Set<UInt8>(), localPending = Set<UInt8>()
    private var remoteOn = Set<UInt8>(), remotePending = Set<UInt8>()

    var serverEchoes: Bool { telnet && remoteOn.contains(T.ECHO) }

    init(session: TerminalSession, config: SessionConfig, telnet: Bool) {
        self.session = session
        self.cfg = config
        self.telnet = telnet
    }

    func start() {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = cfg.noDelay
        tcp.connectionTimeout = 20
        if cfg.keepaliveSeconds > 0 {
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = cfg.keepaliveSeconds
            tcp.keepaliveInterval = cfg.keepaliveSeconds
        }
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: cfg.port)) else {
            finish(error: "Network error: Invalid port")
            return
        }
        let c = NWConnection(host: NWEndpoint.Host(cfg.host), port: port, using: NWParameters(tls: nil, tcp: tcp))
        c.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        connection = c
        c.start(queue: .main)
    }

    func send(_ bytes: [UInt8]) {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        for b in bytes {
            if b == 13 {
                out += telnet ? (cfg.telnetNewLine ? [13, 10] : [13, 0]) : [13, 10]
            } else if telnet && b == T.IAC {
                out += [T.IAC, T.IAC]
            } else {
                out.append(b)
            }
        }
        write(out)
    }

    func resize(cols: Int, rows: Int) {
        size = (cols, rows)
        if telnet && localOn.contains(T.NAWS) { sendNAWS() }
    }

    func close() {
        closed = true
        connection?.cancel()
        connection = nil
    }

    // MARK: Network

    private func handle(_ state: NWConnection.State) {
        guard !closed else { return }
        switch state {
        case .ready:
            session?.connectionEstablished()
            if telnet {
                offerLocal(T.NAWS); offerLocal(T.TTYPE); offerLocal(T.SGA)
                requestRemote(T.ECHO); requestRemote(T.SGA)
            }
            receive()
        case .waiting(let error), .failed(let error):
            finish(error: describe(error))
        default:
            break
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, !self.closed else { return }
                if let data, !data.isEmpty { self.process(Array(data)) }
                if let error { self.finish(error: self.describe(error)); return }
                if complete { self.finish(error: nil); return }
                self.receive()
            }
        }
    }

    private func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, let connection else { return }
        connection.send(content: Data(bytes), completion: .contentProcessed { _ in })
    }

    private func finish(error: String?) {
        guard !closed else { return }
        closed = true
        connection?.cancel()
        connection = nil
        session?.connectionClosed(error: error)
    }

    private func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code): return NetworkErrorText.errno(code.rawValue)
        case .dns: return "Host does not exist"
        default: return "Network error: \(error.localizedDescription)"
        }
    }

    // MARK: Telnet

    private func process(_ bytes: [UInt8]) {
        guard telnet else { session?.received(bytes); return }
        var out: [UInt8] = []
        for b in bytes {
            switch parse {
            case .data:
                if b == T.IAC { parse = .iac } else { out.append(b) }
            case .iac:
                switch b {
                case T.IAC: out.append(b); parse = .data
                case T.WILL, T.WONT, T.DO, T.DONT: parse = .command(b)
                case T.SB: subBuffer = []; parse = .sub
                default: parse = .data
                }
            case .command(let cmd):
                negotiate(cmd, b)
                parse = .data
            case .sub:
                if b == T.IAC { parse = .subIAC } else { subBuffer.append(b) }
            case .subIAC:
                if b == T.SE { subnegotiation(subBuffer); parse = .data }
                else { subBuffer.append(b); parse = .sub }
            }
        }
        if !out.isEmpty { session?.received(out) }
    }

    private func negotiate(_ cmd: UInt8, _ opt: UInt8) {
        let supportedLocal: Set<UInt8> = [T.NAWS, T.TTYPE, T.SGA]
        let supportedRemote: Set<UInt8> = [T.ECHO, T.SGA]
        switch cmd {
        case T.DO:
            if supportedLocal.contains(opt) {
                if !localOn.contains(opt) {
                    localOn.insert(opt)
                    if localPending.remove(opt) == nil { write([T.IAC, T.WILL, opt]) }
                }
                if opt == T.NAWS { sendNAWS() }
            } else if localPending.remove(opt) == nil {
                write([T.IAC, T.WONT, opt])
            }
        case T.DONT:
            if localOn.contains(opt) || localPending.contains(opt) {
                localOn.remove(opt)
                if localPending.remove(opt) == nil { write([T.IAC, T.WONT, opt]) }
            }
        case T.WILL:
            if supportedRemote.contains(opt) {
                if !remoteOn.contains(opt) {
                    remoteOn.insert(opt)
                    if remotePending.remove(opt) == nil { write([T.IAC, T.DO, opt]) }
                }
            } else if remotePending.remove(opt) == nil {
                write([T.IAC, T.DONT, opt])
            }
        case T.WONT:
            if remoteOn.contains(opt) || remotePending.contains(opt) {
                remoteOn.remove(opt)
                if remotePending.remove(opt) == nil { write([T.IAC, T.DONT, opt]) }
            }
        default:
            break
        }
    }

    private func subnegotiation(_ data: [UInt8]) {
        guard data.count >= 2, data[0] == T.TTYPE, data[1] == 1 else { return }
        let term = cfg.termType.isEmpty ? "xterm" : cfg.termType
        write([T.IAC, T.SB, T.TTYPE, 0] + Array(term.uppercased().utf8) + [T.IAC, T.SE])
    }

    private func offerLocal(_ opt: UInt8) {
        localPending.insert(opt)
        write([T.IAC, T.WILL, opt])
    }

    private func requestRemote(_ opt: UInt8) {
        remotePending.insert(opt)
        write([T.IAC, T.DO, opt])
    }

    private func sendNAWS() {
        var payload: [UInt8] = []
        for v in [size.cols, size.rows] {
            for b in [UInt8(v >> 8 & 0xff), UInt8(v & 0xff)] {
                payload.append(b)
                if b == T.IAC { payload.append(b) }
            }
        }
        write([T.IAC, T.SB, T.NAWS] + payload + [T.IAC, T.SE])
    }
}
