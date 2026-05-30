import Foundation

public enum ProxyState: Equatable, Sendable {
    case checking
    case enabled
    case disabled
    case partial
    case unknown
}
