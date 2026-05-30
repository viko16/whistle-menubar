import Foundation

public actor ConfigStore {
    public let configURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configURL: URL? = nil) {
        if let configURL {
            self.configURL = configURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
            self.configURL = applicationSupport
                .appendingPathComponent("whistle-menubar", isDirectory: true)
                .appendingPathComponent("config.json")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL) else {
            return .default
        }

        do {
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            Log.warn("Failed to decode config: \(error)")
            return .default
        }
    }

    public func save(_ config: AppConfig) {
        do {
            let directory = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            Log.warn("Failed to save config: \(error)")
        }
    }

    public func updateW2Path(_ path: String?) {
        var config = load()
        config.w2Path = path
        config.detectedAt = path == nil ? nil : Date()
        save(config)
    }
}
