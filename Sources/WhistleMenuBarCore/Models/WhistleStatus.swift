import Foundation

public enum WhistleStatus: Equatable, Sendable {
    case checking
    case w2Unavailable
    case running
    case stopped
    case unknown(String?)

    public var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    public var hasUsableW2: Bool {
        if case .w2Unavailable = self {
            return false
        }
        return true
    }
}
