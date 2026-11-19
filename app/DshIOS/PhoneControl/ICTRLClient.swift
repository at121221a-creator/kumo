import CryptoKit
import Foundation

/// The few iCTRL calls the app itself makes, to record what the agent does on screen.
///
/// The app never pairs on its own: it borrows the key the agent's client already
/// stored after the user allowed it (`~/.ictrl/token.json` in the engine's home,
/// one record per device as `device:<id>`). No key means the agent has not been
/// allowed in yet, so there is nothing to record either.
///
/// Protocol v1 of iCTRL's encrypted envelope, as in its reference client
/// `ictrl_rpc.py`: HMAC-SHA256 only. Request body is XORed with an HMAC-CTR keystream
/// under a per-request key, then MACed; the response comes back the same way.
enum ICTRLClient {
    static let base = URL(string: "http://127.0.0.1:8200")!

    struct Key {
        let tok: String
        let key: SymmetricKey
    }

    enum Failure: Error { case noService, noKey, badResponse, rejected(Int) }

    /// The stable id of the iCTRL install on this phone, from its public status endpoint.
    static func deviceID() async -> String? {
        var request = URLRequest(url: base.appendingPathComponent("whoami"), timeoutInterval: 2)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["device_id"] as? String
    }

    /// The key the agent stored for this device, if any.
    static func storedKey(deviceID: String) -> Key? {
        let url = EnginePaths.real(EnginePaths.home + "/.ictrl/token.json")
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let record = store["device:\(deviceID)"] as? [String: Any],
              let tok = record["tok"] as? String,
              let hex = record["key"] as? String,
              let raw = Data(hex: hex), raw.count == 32 else { return nil }
        return Key(tok: tok, key: SymmetricKey(data: raw))
    }

    /// A single-use URL for the live screen (fragmented MP4, H.264, no audio).
    static func streamURL(fps: Int) async throws -> URL {
        guard let id = await deviceID() else { throw Failure.noService }
        guard let key = storedKey(deviceID: id) else { throw Failure.noKey }
        let result = try await call("stream_ticket", key: key)
        guard let ticket = result["ticket"] as? String else { throw Failure.badResponse }
        var parts = URLComponents(url: base.appendingPathComponent("stream"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "ticket", value: ticket),
            URLQueryItem(name: "fps", value: String(fps)),
            // 0.75 of the screen at about 2.7 Mbit/s for 15 fps. The default is
            // near-lossless: some 18 Mbit/s, over 100 MB a minute.
            URLQueryItem(name: "quality", value: "medium"),
        ]
        return parts.url!
    }

    /// One enveloped JSON-RPC call; returns `result`.
    static func call(_ method: String, params: [String: Any] = [:], key: Key) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": method, "params": params, "id": 1])
        let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let ts = UInt64(Date().timeIntervalSince1970)
        let kEnc = derive(key.key, "ictrl-v1|enc-req", nonce)
        let kMac = derive(key.key, "ictrl-v1|mac", nonce)
        let ct = xor(body, kEnc, nonce)
        guard let tokBytes = Data(hex: key.tok) else { throw Failure.noKey }
        var signed = Data("v1".utf8) + tokBytes
        withUnsafeBytes(of: ts.bigEndian) { signed.append(contentsOf: $0) }
        signed += nonce + ct
        let tag = Data(HMAC<SHA256>.authenticationCode(for: signed, using: kMac))

        let envelope: [String: Any] = ["v": 1, "tok": key.tok, "ts": ts, "nonce": nonce.hex,
                                       "ct": ct.base64EncodedString(), "tag": tag.hex]
        var request = URLRequest(url: base.appendingPathComponent("rpc"), timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.rejected(status) }
        guard let sealed = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let respCT = (sealed["ct"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let respTag = (sealed["tag"] as? String).flatMap({ Data(hex: $0) }),
              HMAC<SHA256>.isValidAuthenticationCode(respTag, authenticating: Data("resp".utf8) + nonce + respCT, using: kMac)
        else { throw Failure.badResponse }
        let plain = xor(respCT, derive(key.key, "ictrl-v1|enc-resp", nonce), nonce)
        guard let reply = try JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let result = reply["result"] as? [String: Any] else { throw Failure.badResponse }
        return result
    }

    // MARK: - crypto

    private static func derive(_ key: SymmetricKey, _ label: String, _ nonce: Data) -> SymmetricKey {
        SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(label.utf8) + nonce, using: key)))
    }

    /// PRF-CTR: block i = HMAC(key, nonce || be32(i)).
    private static func xor(_ data: Data, _ key: SymmetricKey, _ nonce: Data) -> Data {
        var out = Data(capacity: data.count)
        var counter: UInt32 = 0
        var offset = data.startIndex
        while offset < data.endIndex {
            var input = nonce
            withUnsafeBytes(of: counter.bigEndian) { input.append(contentsOf: $0) }
            let block = HMAC<SHA256>.authenticationCode(for: input, using: key)
            for byte in block where offset < data.endIndex {
                out.append(data[offset] ^ byte)
                offset += 1
            }
            counter += 1
        }
        return out
    }

    /// Loopback only; a system proxy could never reach it.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }()
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
