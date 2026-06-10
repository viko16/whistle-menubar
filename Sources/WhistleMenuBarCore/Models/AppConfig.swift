import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var w2Path: String?
    public var detectedAt: Date?

    public init(
        version: Int = 1,
        w2Path: String? = nil,
        detectedAt: Date? = nil
    ) {
        self.version = version
        self.w2Path = w2Path
        self.detectedAt = detectedAt
    }

    public static let `default` = AppConfig()
}
