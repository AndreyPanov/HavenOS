import Foundation

/// A typed UserDefaults value captured in a backup.
public enum BackupCredentialValue: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case stringArray([String])
    case int(Int)
    case double(Double)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case string
        case bool
        case stringArray
        case int
        case double
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ValueType.self, forKey: .type) {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .stringArray:
            self = .stringArray(try container.decode([String].self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .stringArray(let value):
            try container.encode(ValueType.stringArray, forKey: .type)
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

/// UserDefaults values captured with a capability backup.
public struct BackupCredentialSnapshot: Codable, Equatable, Sendable {
    public static let fileName = "credentials.json"

    public let values: [String: BackupCredentialValue]

    public init(values: [String: BackupCredentialValue]) {
        self.values = values
    }
}

public extension BackupCredentialSnapshot {
    var isEmpty: Bool {
        values.isEmpty
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> BackupCredentialSnapshot {
        try JSONDecoder().decode(BackupCredentialSnapshot.self, from: data)
    }
}
