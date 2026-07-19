import Foundation

public enum MaritalStatus: String, Codable, CaseIterable, Identifiable {
    case single
    case married

    public var id: String { rawValue }

    // Display names: iOS app `MaritalStatus+Localized`.
}
