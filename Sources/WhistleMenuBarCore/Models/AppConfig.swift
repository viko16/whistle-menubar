import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var w2Path: String?
    public var detectedAt: Date?
    public var whistleHost: String
    public var whistlePort: Int
    public var webUIPort: Int

    public init(
        version: Int = 1,
        w2Path: String? = nil,
        detectedAt: Date? = nil,
        whistleHost: String = "127.0.0.1",
        whistlePort: Int = 8899,
        webUIPort: Int = 8899
    ) {
        self.version = version
        self.w2Path = w2Path
        self.detectedAt = detectedAt
        self.whistleHost = whistleHost
        self.whistlePort = whistlePort
        self.webUIPort = webUIPort
    }

    public static let `default` = AppConfig()
}
