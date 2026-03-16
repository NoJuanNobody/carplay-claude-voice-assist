import Foundation

/// Represents and manages a user profile with preferences and settings.
public struct UserProfile {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}
