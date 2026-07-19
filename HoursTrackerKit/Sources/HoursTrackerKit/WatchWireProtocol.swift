import Foundation

/// Idempotent clock action originating on the watch (or echoed from phone).
public struct WatchClockEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case clockIn
        case clockOut
    }

    /// Stable UUID generated at creation — used for dedupe on replay.
    public let id: UUID
    public let kind: Kind
    /// Wall-clock time of the tap on the watch.
    public let timestamp: Date
    /// For `clockIn`: equals `id` (new session id).
    /// For `clockOut`: the open session being closed.
    public let sessionID: UUID

    public init(id: UUID = UUID(), kind: Kind, timestamp: Date = Date(), sessionID: UUID) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.sessionID = sessionID
    }

    public static func makeClockIn(at timestamp: Date = Date()) -> WatchClockEvent {
        let id = UUID()
        return WatchClockEvent(id: id, kind: .clockIn, timestamp: timestamp, sessionID: id)
    }

    public static func makeClockOut(sessionID: UUID, at timestamp: Date = Date()) -> WatchClockEvent {
        WatchClockEvent(id: UUID(), kind: .clockOut, timestamp: timestamp, sessionID: sessionID)
    }
}

/// Messages exchanged over WatchConnectivity (JSON in `[String: Any]` via Data).
public enum WatchWireMessage: Codable, Equatable, Sendable {
    case snapshot(WatchSnapshot)
    case clockEvent(WatchClockEvent)
    case requestSnapshot
    /// Phone ack that it applied (or already knew) this event id.
    case eventAck(UUID)

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum MessageType: String, Codable {
        case snapshot, clockEvent, requestSnapshot, eventAck
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .snapshot(let value):
            try c.encode(MessageType.snapshot, forKey: .type)
            try c.encode(value, forKey: .payload)
        case .clockEvent(let value):
            try c.encode(MessageType.clockEvent, forKey: .type)
            try c.encode(value, forKey: .payload)
        case .requestSnapshot:
            try c.encode(MessageType.requestSnapshot, forKey: .type)
        case .eventAck(let id):
            try c.encode(MessageType.eventAck, forKey: .type)
            try c.encode(id, forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(MessageType.self, forKey: .type)
        switch type {
        case .snapshot:
            self = .snapshot(try c.decode(WatchSnapshot.self, forKey: .payload))
        case .clockEvent:
            self = .clockEvent(try c.decode(WatchClockEvent.self, forKey: .payload))
        case .requestSnapshot:
            self = .requestSnapshot
        case .eventAck:
            self = .eventAck(try c.decode(UUID.self, forKey: .payload))
        }
    }
}

public enum WatchWireCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode(_ message: WatchWireMessage) throws -> Data {
        try encoder.encode(message)
    }

    public static func decode(_ data: Data) throws -> WatchWireMessage {
        try decoder.decode(WatchWireMessage.self, from: data)
    }

    /// Pack for `WCSession` userInfo / applicationContext dictionaries.
    public static func dictionary(for message: WatchWireMessage) throws -> [String: Any] {
        ["ht_wire": try encode(message)]
    }

    public static func message(from dictionary: [String: Any]) throws -> WatchWireMessage? {
        guard let data = dictionary["ht_wire"] as? Data else { return nil }
        return try decode(data)
    }
}
