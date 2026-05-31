import Foundation

public struct RuleItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let isSelected: Bool
    public let isDefault: Bool
    public let isGroup: Bool
    public let value: String

    public init(
        id: String,
        name: String,
        displayName: String,
        isSelected: Bool,
        isDefault: Bool,
        isGroup: Bool,
        value: String = ""
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.isSelected = isSelected
        self.isDefault = isDefault
        self.isGroup = isGroup
        self.value = value
    }
}
