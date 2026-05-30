import Foundation

public enum W2StatusParser {
    public static func parse(stdout: String, stderr: String, exitCode: Int32) -> WhistleStatus {
        let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let lowercased = combined.lowercased()

        if matches(combined, pattern: #"(?i)whistle@\S+\s+is\s+running"#) ||
            matches(combined, pattern: #"(?i)\bis\s+running\b"#) {
            return .running
        }

        if matches(combined, pattern: #"(?i)(stopped|not\s+running|no\s+running)"#) {
            return .stopped
        }

        if exitCode != 0 {
            if lowercased.contains("not running") {
                return .stopped
            }
            return .unknown(combined.truncatedForLog())
        }

        if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unknown(nil)
        }

        return .unknown(combined.truncatedForLog())
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
