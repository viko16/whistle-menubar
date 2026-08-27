import AppKit
import WhistleMenuBarCore

@MainActor
final class MenuBuilder {
    private static let emptyStateImage = NSImage(size: NSSize(width: 18, height: 18))

    func rebuild(_ menu: NSMenu, state: AppState, target: StatusBarController) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        menu.addItem(disabledItem(title: statusTitle(for: state.whistleStatus)))

        if state.whistleStatus == .stopped {
            let startWhistle = NSMenuItem(
                title: L10n.string("menu.start_whistle"),
                action: #selector(StatusBarController.startWhistle),
                keyEquivalent: ""
            )
            startWhistle.target = target
            startWhistle.isEnabled = true
            menu.addItem(startWhistle)
        }

        let openWebUI = NSMenuItem(
            title: L10n.string("menu.open_webui"),
            action: #selector(StatusBarController.openWebUI),
            keyEquivalent: ""
        )
        openWebUI.target = target
        openWebUI.isEnabled = state.canOpenWebUI
        menu.addItem(openWebUI)

        menu.addItem(.separator())
        addRules(to: menu, state: state, target: target)
        menu.addItem(.separator())
        addProxy(to: menu, state: state, target: target)
        addLaunchAtLogin(to: menu, state: state, target: target)
        addQuit(to: menu, target: target)
    }

    private func addRules(to menu: NSMenu, state: AppState, target: StatusBarController) {
        menu.addItem(disabledItem(title: L10n.string("menu.rules.title")))

        guard state.canUseRules else {
            menu.addItem(disabledItem(title: L10n.string("menu.rules.unavailable")))
            return
        }

        if state.rulesReadFailed {
            menu.addItem(disabledItem(title: L10n.string("menu.rules.read_failed")))
            return
        }

        if state.multipleChoiceFailed {
            menu.addItem(disabledItem(title: L10n.string("menu.rules.multiple_choice_failed")))
        }

        if state.rules.isEmpty {
            menu.addItem(disabledItem(title: state.rulesLoading ? L10n.string("menu.rules.loading") : L10n.string("menu.rules.empty")))
            return
        }

        for rule in state.rules {
            let item = NSMenuItem(
                title: rule.displayName,
                action: rule.isGroup ? nil : #selector(StatusBarController.toggleRule(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = RuleMenuPayload(rule: rule)
            item.isEnabled = !rule.isGroup
            item.state = (!rule.isGroup && rule.isSelected) ? .on : .off
            reserveStateColumn(for: item)
            menu.addItem(item)
        }
    }

    private func addProxy(to menu: NSMenu, state: AppState, target: StatusBarController) {
        let item = NSMenuItem(
            title: L10n.string("menu.proxy"),
            action: #selector(StatusBarController.toggleProxy),
            keyEquivalent: ""
        )
        item.target = target
        item.isEnabled = state.canToggleProxy
        item.state = state.proxyState == .enabled ? .on : .off
        reserveStateColumn(for: item)
        menu.addItem(item)
    }

    private func addLaunchAtLogin(to menu: NSMenu, state: AppState, target: StatusBarController) {
        let item = NSMenuItem(
            title: L10n.string("menu.launch_at_login"),
            action: #selector(StatusBarController.toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        item.target = target
        item.isEnabled = true
        item.state = state.launchAtLoginEnabled ? .on : .off
        reserveStateColumn(for: item)
        menu.addItem(item)
    }

    private func addQuit(to menu: NSMenu, target: StatusBarController) {
        let item = NSMenuItem(
            title: L10n.string("menu.quit"),
            action: #selector(StatusBarController.quit),
            keyEquivalent: "q"
        )
        item.target = target
        menu.addItem(item)
    }

    private func statusTitle(for status: WhistleStatus) -> String {
        switch status {
        case .checking:
            return L10n.string("menu.status.checking")
        case .w2Unavailable:
            return L10n.string("menu.status.w2_unavailable")
        case .running:
            return L10n.string("menu.status.running")
        case .stopped:
            return L10n.string("menu.status.stopped")
        case .unknown:
            return L10n.string("menu.status.unknown")
        }
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func reserveStateColumn(for item: NSMenuItem) {
        item.offStateImage = Self.emptyStateImage
    }
}

final class RuleMenuPayload: NSObject {
    let rule: RuleItem

    init(rule: RuleItem) {
        self.rule = rule
    }
}
