import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import Citadel
import Crypto

@MainActor protocol RemoteConnection: AnyObject {
    /// True when the remote end echoes typed characters (decides "Auto" local echo).
    var serverEchoes: Bool { get }
    func start()
    func send(_ bytes: [UInt8])
    func resize(cols: Int, rows: Int)
    func close()
}

private struct HostKeyRejected: Error {}
private struct Aborted: Error {}

/// Accepts exactly one expected host key and remembers what the server presented.
private final class HostKeyCheck: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let expected: String?
    private(set) var presented: String?

    init(expected: String?) { self.expected = expected }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let key = String(openSSHPublicKey: hostKey)
        presented = key
        if key == expected {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(HostKeyRejected())
        }
    }
}

enum HostKeyInfo {
    /// PuTTY-style fingerprint line, e.g. "ssh-ed25519 255 SHA256:abc…".
    static func fingerprint(_ openSSHKey: String) -> String {
        let parts = openSSHKey.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return openSSHKey }
        let type = String(parts[0])
        let hash = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "\(type) \(bits(type: type, blob: Array(blob))) SHA256:\(hash)"
    }

    private static func bits(type: String, blob: [UInt8]) -> Int {
        switch type {
        case "ssh-ed25519": return 255
        case "ecdsa-sha2-nistp256": return 256
        case "ecdsa-sha2-nistp384": return 384
        case "ecdsa-sha2-nistp521": return 521
        case "ssh-rsa":
            var r = SSHReader(blob)
            _ = r.string(); _ = r.blob()
            guard var n = r.blob() else { return 0 }
            while n.first == 0 { n.removeFirst() }
            guard let top = n.first else { return 0 }
            return (n.count - 1) * 8 + (8 - top.leadingZeroBitCount)
        default: return 0
        }
    }
}

enum NetworkErrorText {
    static func describe(_ error: Error) -> String {
        if let e = error as? NIOConnectionError {
            if e.connectionErrors.isEmpty, e.dnsAError != nil || e.dnsAAAAError != nil { return "Host does not exist" }
            if let first = e.connectionErrors.first?.error { return describe(first) }
        }
        if let e = error as? IOError { return errno(e.errnoCode) }
        if let e = error as? ChannelError {
            switch e {
            case .connectTimeout: return "Network error: Connection timed out"
            case .eof, .ioOnClosedChannel, .alreadyClosed, .outputClosed: return "Remote side unexpectedly closed network connection"
            default: break
            }
        }
        if error is NIOSSHError { return "Remote side unexpectedly closed network connection" }
        if let e = error as? SSHFatal { return e.message }
        return "Network error: \(error.localizedDescription)"
    }

    static func errno(_ code: Int32) -> String {
        switch code {
        case ECONNREFUSED: return "Network error: Connection refused"
        case ETIMEDOUT: return "Network error: Connection timed out"
        case ENETUNREACH: return "Network error: Network is unreachable"
        case EHOSTUNREACH: return "Network error: No route to host"
        case ECONNRESET: return "Network error: Software caused connection abort"
        default: return "Network error: \(String(cString: strerror(code)))"
        }
    }
}

@MainActor final class SSHConnection: RemoteConnection {
    private enum Outgoing { case data([UInt8]), resize(Int, Int) }
    private enum AuthResult { case success(SSHClient), refused }

    private weak var session: TerminalSession?
    private let cfg: SessionConfig
    private var task: Task<Void, Never>?
    private var client: SSHClient?
    private var outgoing: AsyncStream<Outgoing>.Continuation?
    private var size = (cols: 80, rows: 24)
    private var trustedKey: String?

    let serverEchoes = true

    init(session: TerminalSession, config: SessionConfig) {
        self.session = session
        self.cfg = config
    }

    func start() {
        task = Task { await run() }
    }

    func send(_ bytes: [UInt8]) {
        outgoing?.yield(.data(bytes))
    }

    func resize(cols: Int, rows: Int) {
        size = (cols, rows)
        outgoing?.yield(.resize(cols, rows))
    }

    func close() {
        task?.cancel()
        outgoing?.finish()
        outgoing = nil
        let c = client
        client = nil
        Task { try? await c?.close() }
    }

    // MARK: Session flow

    private func run() async {
        do {
            guard let client = try await login() else { return }
            self.client = client
            try await runShell(client)
            if !Task.isCancelled { session?.connectionClosed(error: nil) }
        } catch is Aborted {
            session?.abort()
        } catch {
            if !Task.isCancelled { session?.connectionClosed(error: NetworkErrorText.describe(error)) }
        }
    }

    private func login() async throws -> SSHClient? {
        guard let session else { return nil }

        trustedKey = HostKeyStore.get(host: cfg.host, port: cfg.port)
        if trustedKey == nil {
            let presented = try await probeHostKey()
            try await confirm(presented, previous: nil)
        }

        var username = cfg.username
        if username.isEmpty {
            guard let typed = await session.ask("login as: ", echo: true), !typed.isEmpty else { throw Aborted() }
            username = typed
        } else {
            session.print("Using username \"\(username)\".\r\n")
        }

        if let method = await publicKeyMethod(username: username) {
            if case .success(let c) = try await authenticate(method) { return c }
            session.print("Server refused our key\r\n")
        }

        guard cfg.tryPassword else {
            throw SSHFatal("No supported authentication methods available (server sent: publickey)")
        }
        for attempt in 1...5 {
            guard let password = await session.ask("\(username)@\(cfg.host)'s password: ", echo: false) else { throw Aborted() }
            if case .success(let c) = try await authenticate(.passwordBased(username: username, password: password)) { return c }
            session.print("Access denied\r\n")
            if attempt == 5 { throw SSHFatal("Too many authentication failures") }
        }
        return nil
    }

    private func publicKeyMethod(username: String) async -> SSHAuthenticationMethod? {
        guard let session, let keyID = cfg.keyID else { return nil }
        guard let data = KeyStore.get(id: keyID), let file = try? PrivateKeyFile(data: data) else {
            session.print("Unable to use key file \"\(cfg.keyName ?? "key")\" (unable to open file)\r\n")
            return nil
        }
        let keyLabel = file.comment.isEmpty ? (cfg.keyName ?? "key") : file.comment
        var key: ParsedKey?
        if file.isEncrypted {
            while key == nil {
                guard let pass = await session.ask("Passphrase for key \"\(keyLabel)\": ", echo: false) else { return nil }
                do { key = try file.decode(passphrase: pass) } catch {
                    session.print("\(error.localizedDescription)\r\n")
                    if case KeyFileError.wrongPassphrase = error { continue }
                    return nil
                }
            }
        } else {
            do { key = try file.decode(passphrase: nil) } catch {
                session.print("Unable to use key file \"\(cfg.keyName ?? "key")\" (\(error.localizedDescription))\r\n")
                return nil
            }
        }
        session.print("Authenticating with public key \"\(keyLabel)\"\r\n")
        switch key {
        case .ed25519(let k): return .ed25519(username: username, privateKey: k)
        case .rsa(let k): return .rsa(username: username, privateKey: k)
        case nil: return nil
        }
    }

    /// Connects once with a host-key check that always fails, purely to learn the server's key.
    private func probeHostKey() async throws -> String {
        let check = HostKeyCheck(expected: nil)
        do {
            let c = try await connect(.passwordBased(username: "", password: ""), check: check)
            try? await c.close()
        } catch {
            guard let presented = check.presented else { throw error }
            return presented
        }
        throw HostKeyRejected()
    }

    private func confirm(_ presented: String, previous: String?) async throws {
        guard let session else { throw Aborted() }
        switch await session.confirmHostKey(presented, previous: previous) {
        case .accept:
            HostKeyStore.set(presented, host: cfg.host, port: cfg.port)
            trustedKey = presented
        case .once:
            trustedKey = presented
        case .cancel:
            throw Aborted()
        }
    }

    private func authenticate(_ method: SSHAuthenticationMethod) async throws -> AuthResult {
        while true {
            let check = HostKeyCheck(expected: trustedKey)
            do {
                return .success(try await connect(method, check: check))
            } catch {
                if Task.isCancelled { throw Aborted() }
                if let presented = check.presented, presented != trustedKey {
                    try await confirm(presented, previous: trustedKey)
                    continue
                }
                if check.presented != nil, error is SSHClientError || error is AuthenticationFailed {
                    return .refused
                }
                throw error
            }
        }
    }

    private func connect(_ method: SSHAuthenticationMethod, check: HostKeyCheck) async throws -> SSHClient {
        try await SSHClient.connect(
            host: cfg.host,
            port: cfg.port,
            authenticationMethod: method,
            hostKeyValidator: .custom(check),
            reconnect: .never,
            algorithms: .all,
            channelHandlers: [TCPOptionsHandler(keepaliveSeconds: cfg.keepaliveSeconds, noDelay: cfg.noDelay)],
            connectTimeout: .seconds(20)
        )
    }

    private func runShell(_ client: SSHClient) async throws {
        let (stream, continuation) = AsyncStream<Outgoing>.makeStream()
        outgoing = continuation
        let erase: UInt32 = cfg.backspace == .controlH ? 8 : 127
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: cfg.termType.isEmpty ? "xterm" : cfg.termType,
            terminalCharacterWidth: size.cols,
            terminalRowHeight: size.rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([.VERASE: .init(rawValue: erase)])
        )
        session?.connectionEstablished()

        var shellEnded = false
        do {
            try await ptySession(client, request, stream) { shellEnded = true }
        } catch {
            // Citadel closes the channel after the shell exits; it may already be closed by the server.
            if !shellEnded { throw error }
        }
    }

    private func ptySession(_ client: SSHClient, _ request: SSHChannelRequestEvent.PseudoTerminalRequest,
                            _ stream: AsyncStream<Outgoing>, onEnd: () -> Void) async throws {
        let session = self.session
        try await client.withPTY(request) { inbound, outbound in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await item in stream {
                        switch item {
                        case .data(let bytes):
                            try await outbound.write(ByteBuffer(bytes: bytes))
                        case .resize(let cols, let rows):
                            try await outbound.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
                        }
                    }
                }
                for try await chunk in inbound {
                    switch chunk {
                    case .stdout(let buffer), .stderr(let buffer):
                        let bytes = Array(buffer.readableBytesView)
                        session?.received(bytes)
                    }
                }
                onEnd()
                group.cancelAll()
            }
        }
    }
}

/// Applies PuTTY's TCP options once the socket exists, on the channel's own event loop.
private final class TCPOptionsHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    let keepaliveSeconds: Int
    let noDelay: Bool

    init(keepaliveSeconds: Int, noDelay: Bool) {
        self.keepaliveSeconds = keepaliveSeconds
        self.noDelay = noDelay
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let channel = context.channel
        _ = channel.setOption(ChannelOptions.tcpOption(.tcp_nodelay), value: noDelay ? 1 : 0)
        guard keepaliveSeconds > 0 else { return }
        let secs = Int32(keepaliveSeconds)
        _ = channel.setOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
        _ = channel.setOption(ChannelOptions.socket(.init(IPPROTO_TCP), .init(TCP_KEEPALIVE)), value: secs)
        _ = channel.setOption(ChannelOptions.socket(.init(IPPROTO_TCP), .init(TCP_KEEPINTVL)), value: secs)
    }
}

struct SSHFatal: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
