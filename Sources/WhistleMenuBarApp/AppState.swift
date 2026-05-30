import Foundation
import WhistleMenuBarCore

struct AppState: Equatable {
    var whistleStatus: WhistleStatus = .checking
    var proxyState: ProxyState = .checking
    var launchAtLoginEnabled = false
    var rules: [RuleItem] = []
    var rulesLoading = false
    var rulesReadFailed = false
    var multipleChoiceFailed = false
}

extension AppState {
    var canOpenWebUI: Bool {
        switch whistleStatus {
        case .running, .unknown:
            return true
        case .checking, .w2Unavailable, .stopped:
            return false
        }
    }

    var canUseRules: Bool {
        whistleStatus.isRunning
    }

    var canToggleProxy: Bool {
        whistleStatus.isRunning
    }
}
