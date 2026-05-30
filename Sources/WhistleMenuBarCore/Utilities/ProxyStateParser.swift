import Foundation

public enum ProxyStateParser {
    public static func parse(_ output: String, host: String = "127.0.0.1", port: Int = 8899) -> ProxyState {
        let values = parseKeyValues(output)

        let httpEnabled = values["HTTPEnable"] == "1"
        let httpsEnabled = values["HTTPSEnable"] == "1"
        let httpMatches = httpEnabled &&
            values["HTTPProxy"] == host &&
            values["HTTPPort"] == String(port)
        let httpsMatches = (values["HTTPSEnable"] == nil || httpsEnabled) &&
            values["HTTPSProxy"] == host &&
            values["HTTPSPort"] == String(port)

        if httpMatches && httpsMatches {
            return .enabled
        }

        if httpMatches || httpsMatches {
            return .partial
        }

        if httpEnabled || httpsEnabled {
            return .partial
        }

        if values.isEmpty {
            return .unknown
        }

        return .disabled
    }

    private static func parseKeyValues(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                values[key] = value
            }
        }
        return values
    }
}
