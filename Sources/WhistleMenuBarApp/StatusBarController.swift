import AppKit
import WhistleMenuBarCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let menuBuilder = MenuBuilder()
    private let w2CommandService: W2CommandService
    private let systemProxyService: SystemProxyService
    private let apiClient: WhistleAPIClient
    private let launchAtLoginService: LaunchAtLoginService
    private let notificationService: NotificationService

    private var state = AppState()
    private var refreshToken = UUID()
    private var didNotifyMultipleChoiceFailure = false

    init(
        w2CommandService: W2CommandService,
        systemProxyService: SystemProxyService,
        apiClient: WhistleAPIClient,
        launchAtLoginService: LaunchAtLoginService,
        notificationService: NotificationService
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.w2CommandService = w2CommandService
        self.systemProxyService = systemProxyService
        self.apiClient = apiClient
        self.launchAtLoginService = launchAtLoginService
        self.notificationService = notificationService
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        configureStatusItem()
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuData()
    }

    func refreshMenuData() {
        let token = beginMenuRefresh()

        Task {
            let refreshData = await loadMenuRefreshData()
            applyMenuRefresh(refreshData, token: token)
        }
    }

    private func beginMenuRefresh() -> UUID {
        let token = UUID()
        refreshToken = token
        state.launchAtLoginEnabled = launchAtLoginService.isEnabled()
        rebuildMenu()
        return token
    }

    private func loadMenuRefreshData() async -> MenuRefreshData {
        let whistleStatus = await w2CommandService.getStatus()
        async let proxyStateTask: ProxyState = loadProxyState(
            hasUsableW2: whistleStatus.hasUsableW2
        )
        let rulesRefresh = await loadRulesRefreshData(isRunning: whistleStatus.isRunning)
        let proxyState = await proxyStateTask

        return MenuRefreshData(
            whistleStatus: whistleStatus,
            proxyState: proxyState,
            rules: rulesRefresh.rules,
            rulesReadFailed: rulesRefresh.rulesReadFailed,
            multipleChoiceFailed: rulesRefresh.multipleChoiceFailed
        )
    }

    private func loadProxyState(hasUsableW2: Bool) async -> ProxyState {
        guard hasUsableW2 else { return .unknown }
        return await systemProxyService.currentState()
    }

    private func loadRulesRefreshData(isRunning: Bool) async -> RulesRefreshData {
        guard isRunning else { return RulesRefreshData() }

        do {
            let result = try await apiClient.loadRulesEnsuringMultipleChoice()
            return RulesRefreshData(
                rules: result.rules,
                multipleChoiceFailed: result.multipleChoiceFailed
            )
        } catch {
            Log.warn("Rules refresh failed: \(error)")
            return RulesRefreshData(rulesReadFailed: true)
        }
    }

    private func applyMenuRefresh(_ refreshData: MenuRefreshData, token: UUID) {
        guard refreshToken == token else { return }
        state.whistleStatus = refreshData.whistleStatus
        state.proxyState = refreshData.proxyState
        state.launchAtLoginEnabled = launchAtLoginService.isEnabled()
        state.rules = refreshData.rules
        state.rulesLoading = false
        state.rulesReadFailed = refreshData.rulesReadFailed
        state.multipleChoiceFailed = refreshData.multipleChoiceFailed
        rebuildMenu()
        notifyRulesRefreshIssueIfNeeded(refreshData)
    }

    @objc func openWebUI() {
        guard state.whistleStatus.hasUsableW2 else {
            notificationService.send(titleKey: "notification.w2.title", bodyKey: "notification.w2.body")
            return
        }
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8899")!)
    }

    @objc func startWhistle() {
        guard state.whistleStatus == .stopped else { return }

        state.whistleStatus = .checking
        rebuildMenu()

        Task {
            await restartWhistle()
        }
    }

    @objc func toggleRule(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? RuleMenuPayload else { return }
        let rule = payload.rule
        guard !rule.isGroup else { return }

        state.rulesLoading = true
        state.rulesReadFailed = false
        rebuildMenu()

        Task {
            await toggle(rule)
        }
    }

    @objc func toggleProxy() {
        let shouldEnable = state.proxyState != .enabled
        state.proxyState = .checking
        rebuildMenu()

        Task {
            await setProxyEnabled(shouldEnable)
        }
    }

    @objc func toggleLaunchAtLogin() {
        let shouldEnable = !state.launchAtLoginEnabled
        do {
            try launchAtLoginService.setEnabled(shouldEnable)
            state.launchAtLoginEnabled = launchAtLoginService.isEnabled()
            rebuildMenu()
        } catch {
            presentFailure(
                "Launch at login toggle failed: \(error)",
                titleKey: "notification.launch.title",
                body: .localizedKey("notification.launch.body")
            )
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func restartWhistle() async {
        do {
            try await w2CommandService.restart()
            refreshMenuData()
        } catch {
            presentFailure(
                "Whistle restart failed: \(error)",
                titleKey: "notification.start_whistle.title",
                body: .localizedKey("notification.start_whistle.body")
            ) {
                self.state.whistleStatus = .stopped
            }
        }
    }

    private func toggle(_ rule: RuleItem) async {
        do {
            try await apiClient.toggle(rule)
            let result = try await apiClient.loadRulesEnsuringMultipleChoice()
            applyRulesLoadResult(result)
        } catch {
            presentFailure(
                "Rules toggle failed for \(rule.name): \(error)",
                titleKey: "notification.rules.title",
                body: .text(L10n.format(
                    "notification.rules.toggle_body_format",
                    rule.displayName
                ))
            ) {
                self.state.rulesLoading = false
                self.state.rulesReadFailed = true
            }
        }
    }

    private func setProxyEnabled(_ shouldEnable: Bool) async {
        do {
            try await w2CommandService.setProxyEnabled(shouldEnable)
            state.proxyState = await systemProxyService.currentState()
            rebuildMenu()
        } catch {
            presentFailure(
                "Proxy toggle failed: \(error)",
                titleKey: "notification.proxy.title",
                body: .localizedKey("notification.proxy.body")
            ) {
                self.state.proxyState = .unknown
            }
        }
    }

    private func applyRulesLoadResult(_ result: RulesLoadResult) {
        state.rules = result.rules
        state.rulesLoading = false
        state.rulesReadFailed = false
        state.multipleChoiceFailed = result.multipleChoiceFailed
        rebuildMenu()
    }

    private func notifyRulesRefreshIssueIfNeeded(_ refreshData: MenuRefreshData) {
        if refreshData.rulesReadFailed {
            sendNotification(
                titleKey: "notification.rules.title",
                body: .localizedKey("notification.rules.read_body")
            )
        } else if refreshData.multipleChoiceFailed && !didNotifyMultipleChoiceFailure {
            didNotifyMultipleChoiceFailure = true
            sendNotification(
                titleKey: "notification.rules.title",
                body: .localizedKey("notification.rules.multiple_choice_body")
            )
        }
    }

    private func presentFailure(
        _ logMessage: String,
        titleKey: String,
        body: NotificationBody,
        updateState: () -> Void = {}
    ) {
        Log.warn(logMessage)
        updateState()
        rebuildMenu()
        sendNotification(titleKey: titleKey, body: body)
    }

    private func sendNotification(titleKey: String, body: NotificationBody) {
        switch body {
        case .localizedKey(let bodyKey):
            notificationService.send(titleKey: titleKey, bodyKey: bodyKey)
        case .text(let body):
            notificationService.send(titleKey: titleKey, body: body)
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = statusBarIconImage()
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "whistle-menubar"
        }
    }

    // Do not use Bundle.module here: SwiftPM's generated accessor fatalErrors
    // when the app target resource bundle is missing from a packaged .app.
    private func statusBarIconImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "StatusBarIconTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return Bundle.main.image(forResource: "StatusBarIconTemplate")
            ?? NSImage(systemSymbolName: "network", accessibilityDescription: "whistle-menubar")
    }

    private func rebuildMenu() {
        // Keep the attached menu instance so refreshes update the currently open menu.
        menuBuilder.rebuild(menu, state: state, target: self)
    }
}

private struct MenuRefreshData {
    let whistleStatus: WhistleStatus
    let proxyState: ProxyState
    let rules: [RuleItem]
    let rulesReadFailed: Bool
    let multipleChoiceFailed: Bool
}

private struct RulesRefreshData {
    var rules: [RuleItem] = []
    var rulesReadFailed = false
    var multipleChoiceFailed = false
}

private enum NotificationBody {
    case localizedKey(String)
    case text(String)
}
