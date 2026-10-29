import Foundation
import Crypto
import CommonCrypto
import Citadel

enum ParsedKey {
    case ed25519(Curve25519.Signing.PrivateKey)
    case rsa(Insecure.RSA.PrivateKey)
}

enum KeyFileError: LocalizedError {
    case unrecognised, unsupportedType(String), unsupportedEncryption, wrongPassphrase

    var errorDescription: String? {
        switch self {
        case .unrecognised: return "Couldn't load private key (unrecognised format)"
        case .unsupportedType(let t): return "Couldn't load private key (unsupported key type \(t))"
        case .unsupportedEncryption: return "Couldn't load private key (unsupported encryption; re-save it unencrypted or as PPK version 2)"
        case .wrongPassphrase: return "Wrong passphrase"
        }
    }
}

/// A private key in OpenSSH or PuTTY (.ppk) format.
struct PrivateKeyFile {
    let comment: String
    let keyType: String
    let isEncrypted: Bool
    private let openSSHText: String?
    private let ppk: [String: String]?

    init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw KeyFileError.unrecognised }
        if text.hasPrefix("PuTTY-User-Key-File-") {
            let fields = PrivateKeyFile.parsePPK(text)
            guard let header = text.split(separator: "\n").first, let colon = header.firstIndex(of: ":") else { throw KeyFileError.unrecognised }
            ppk = fields
            openSSHText = nil
            keyType = header[header.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            comment = fields["Comment"] ?? ""
            isEncrypted = (fields["Encryption"] ?? "none") != "none"
        } else if text.contains("BEGIN OPENSSH PRIVATE KEY") {
            let info = try PrivateKeyFile.inspectOpenSSH(text)
            ppk = nil
            openSSHText = text
            keyType = info.type
            comment = info.comment
            isEncrypted = info.encrypted
        } else {
            throw KeyFileError.unrecognised
        }
        guard keyType == "ssh-ed25519" || keyType == "ssh-rsa" else { throw KeyFileError.unsupportedType(keyType) }
    }

    func decode(passphrase: String?) throws -> ParsedKey {
        let text = try openSSHText ?? convertPPK(passphrase: passphrase)
        let pass = (openSSHText != nil && isEncrypted) ? passphrase.flatMap { $0.data(using: .utf8) } : nil
        do {
            switch keyType {
            case "ssh-ed25519": return .ed25519(try Curve25519.Signing.PrivateKey(sshEd25519: text, decryptionKey: pass))
            default: return .rsa(try Insecure.RSA.PrivateKey(sshRsa: text, decryptionKey: pass))
            }
        } catch {
            throw isEncrypted ? KeyFileError.wrongPassphrase : KeyFileError.unrecognised
        }
    }

    // MARK: OpenSSH

    private static func inspectOpenSSH(_ text: String) throws -> (type: String, comment: String, encrypted: Bool) {
        let body = text.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let data = Data(base64Encoded: body) else { throw KeyFileError.unrecognised }
        var r = SSHReader(Array(data))
        let magic = Array("openssh-key-v1".utf8) + [0]
        guard r.bytes(magic.count) == magic,
              let cipher = r.string(), r.string() != nil, r.string() != nil,
              r.uint32() == 1, let pub = r.blob(), let priv = r.blob()
        else { throw KeyFileError.unrecognised }
        var pr = SSHReader(pub)
        let type = pr.string() ?? ""
        var comment = ""
        if cipher == "none" {
            var s = SSHReader(priv)
            _ = s.uint32(); _ = s.uint32()
            _ = s.string()
            switch type {
            case "ssh-ed25519": _ = s.blob(); _ = s.blob()
            case "ssh-rsa": for _ in 0..<6 { _ = s.blob() }
            default: break
            }
            comment = s.string() ?? ""
        }
        return (type, comment, cipher != "none")
    }

    // MARK: PuTTY .ppk

    private static func parsePPK(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard let colon = line.firstIndex(of: ":") else { i += 1; continue }
            let name = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name.hasSuffix("-Lines"), let n = Int(value) {
                let start = min(i + 1, lines.count), end = min(i + 1 + n, lines.count)
                fields[String(name.dropLast(6))] = lines[start..<end].joined()
                i = end
            } else {
                fields[name] = value
                i += 1
            }
        }
        return fields
    }

    private func convertPPK(passphrase: String?) throws -> String {
        guard let ppk, let pub = ppk["Public"].flatMap({ Data(base64Encoded: $0) }),
              var priv = ppk["Private"].flatMap({ Data(base64Encoded: $0) })
        else { throw KeyFileError.unrecognised }

        if isEncrypted {
            guard ppk["Encryption"] == "aes256-cbc", ppk["Key-Derivation"] == nil else { throw KeyFileError.unsupportedEncryption }
            let pass = Data((passphrase ?? "").utf8)
            let key = Data(Insecure.SHA1.hash(data: Data([0, 0, 0, 0]) + pass)) + Data(Insecure.SHA1.hash(data: Data([0, 0, 0, 1]) + pass))
            priv = try aes256cbcDecrypt(priv, key: key.prefix(32))
            let macKey = Data(Insecure.SHA1.hash(data: Data("putty-private-key-file-mac-key".utf8) + pass))
            var macData = SSHWriter()
            macData.string(keyType); macData.string("aes256-cbc"); macData.string(comment)
            macData.blob(Array(pub)); macData.blob(Array(priv))
            let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(macData.bytes), using: SymmetricKey(data: macKey))
            let hex = mac.map { String(format: "%02x", $0) }.joined()
            guard hex == ppk["Private-MAC"]?.lowercased() else { throw KeyFileError.wrongPassphrase }
        }

        var pr = SSHReader(Array(pub)), sr = SSHReader(Array(priv))
        _ = pr.string()
        var section = SSHWriter()
        let check = UInt32.random(in: 0...UInt32.max)
        section.uint32(check); section.uint32(check)
        section.string(keyType)
        switch keyType {
        case "ssh-ed25519":
            guard let pk = pr.blob(), let seed = sr.blob(), seed.count == 32 else { throw KeyFileError.unrecognised }
            section.blob(pk); section.blob(seed + pk)
        default:
            guard let e = pr.blob(), let n = pr.blob(), let d = sr.blob(), let p = sr.blob(),
                  let q = sr.blob(), let iqmp = sr.blob() else { throw KeyFileError.unrecognised }
            for part in [n, e, d, iqmp, p, q] { section.blob(part) }
        }
        section.string(comment)
        var pad: UInt8 = 1
        while section.bytes.count % 8 != 0 { section.bytes.append(pad); pad += 1 }

        var file = SSHWriter()
        file.bytes += Array("openssh-key-v1".utf8) + [0]
        file.string("none"); file.string("none"); file.string("")
        file.uint32(1)
        file.blob(Array(pub)); file.blob(section.bytes)
        let b64 = Data(file.bytes).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(b64)\n-----END OPENSSH PRIVATE KEY-----\n"
    }

    private func aes256cbcDecrypt(_ data: Data, key: Data) throws -> Data {
        guard data.count % kCCBlockSizeAES128 == 0 else { throw KeyFileError.unrecognised }
        var out = Data(count: data.count)
        var moved = 0
        let iv = Data(count: kCCBlockSizeAES128)
        let status = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                        k.baseAddress, key.count, v.baseAddress,
                        d.baseAddress, data.count, o.baseAddress, data.count, &moved)
            } } }
        }
        guard status == kCCSuccess else { throw KeyFileError.wrongPassphrase }
        return out.prefix(moved)
    }
}

// MARK: SSH wire format helpers

struct SSHReader {
    private let data: [UInt8]
    private var pos = 0

    init(_ data: [UInt8]) { self.data = data }

    mutating func bytes(_ n: Int) -> [UInt8]? {
        guard n >= 0, pos + n <= data.count else { return nil }
        defer { pos += n }
        return Array(data[pos..<pos + n])
    }

    mutating func uint32() -> UInt32? {
        guard let b = bytes(4) else { return nil }
        return b.reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func blob() -> [UInt8]? {
        guard let len = uint32() else { return nil }
        return bytes(Int(len))
    }

    mutating func string() -> String? { blob().map { String(decoding: $0, as: UTF8.self) } }
}

struct SSHWriter {
    var bytes: [UInt8] = []

    mutating func uint32(_ v: UInt32) { bytes += [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)] }
    mutating func blob(_ b: [UInt8]) { uint32(UInt32(b.count)); bytes += b }
    mutating func string(_ s: String) { blob(Array(s.utf8)) }
}
