import Foundation

/// Untyped JSON as the engine sends it. The engine's RPC payloads are wide and
/// evolve with plugins, so views read the fields they need through subscripts
/// instead of mirroring every shape in Codable structs.
enum JSON: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    subscript(key: String) -> JSON {
        if case .object(let object) = self { return object[key] ?? .null }
        return .null
    }

    subscript(index: Int) -> JSON {
        if case .array(let array) = self, array.indices.contains(index) { return array[index] }
        return .null
    }

    var string: String? { if case .string(let value) = self { return value }; return nil }
    var double: Double? { if case .number(let value) = self { return value }; return nil }
    var int: Int? { double.map { Int($0) } }
    var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    var array: [JSON] { if case .array(let value) = self { return value }; return [] }
    var object: [String: JSON] { if case .object(let value) = self { return value }; return [:] }
    var isNull: Bool { if case .null = self { return true }; return false }
    /// Self, or nil for `.null`.
    var nonNull: JSON? {
        if isNull { return nil }
        return self
    }

    /// Decode into a Codable type when a shape is stable enough to model.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }

    /// Parse what the engine sent. JavaScript strings may hold half of a surrogate pair (text cut
    /// in the middle of an emoji), which `JSON.stringify` writes as a lone `\uD83D`; Foundation
    /// refuses the whole document for it. Such halves read as U+FFFD instead, as a browser would.
    static func parse(_ data: Data) throws -> JSON {
        do {
            return try JSONDecoder().decode(JSON.self, from: data)
        } catch {
            guard let repaired = repairingLoneSurrogates(data) else { throw error }
            return try JSONDecoder().decode(JSON.self, from: repaired)
        }
    }

    /// The text with every `\uXXXX` escape of an unpaired surrogate turned into `�`; nil when it has none.
    static func repairingLoneSurrogates(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        func unit(at index: Int) -> UInt16? {
            guard index + 5 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u"),
                  let value = UInt16(String(decoding: bytes[(index + 2)...(index + 5)], as: UTF8.self), radix: 16) else { return nil }
            return value
        }
        let replacement = Array(#"�"#.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var changed = false
        var index = 0
        while index < bytes.count {
            // Outside an escape, a backslash only ever appears inside a string, so no quote tracking is needed.
            guard bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count else {
                output.append(bytes[index]); index += 1; continue
            }
            guard let value = unit(at: index) else {
                // `\\`, `\"`, `\n`…: copied whole, so an escaped backslash never starts a `\u` of its own.
                output.append(contentsOf: bytes[index...(index + 1)]); index += 2; continue
            }
            if (0xD800...0xDBFF).contains(value), let low = unit(at: index + 6), (0xDC00...0xDFFF).contains(low) {
                output.append(contentsOf: bytes[index..<(index + 12)]); index += 12
            } else if (0xD800...0xDFFF).contains(value) {
                output.append(contentsOf: replacement); index += 6; changed = true
            } else {
                output.append(contentsOf: bytes[index..<(index + 6)]); index += 6
            }
        }
        return changed ? Data(output) : nil
    }
}

extension JSON: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByFloatLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(dictionaryLiteral elements: (String, JSON)...) { self = .object(Dictionary(elements, uniquingKeysWith: { $1 })) }
    init(arrayLiteral elements: JSON...) { self = .array(elements) }
}
