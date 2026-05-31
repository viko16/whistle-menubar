import AppKit
import WhistleMenuBarCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
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
        configureStatusItem()
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuData()
    }

    func refreshMenuData() {
        let token = UUID()
        refreshToken = token
        state.launchAtLoginEnabled = launchAtLoginService.isEnabled()
        rebuildMenu()

        Task {
            let whistleStatus = await w2CommandService.getStatus()
            async let proxyStateTask: ProxyState = whistleStatus.hasUsableW2 ? systemProxyService.currentState() : .unknown

            var loadedRules: [RuleItem] = []
            var rulesReadFailed = false
            var multipleChoiceFailed = false

            if whistleStatus.isRunning {
                do {
                    let result = try await apiClient.loadRulesEnsuringMultipleChoice()
                    loadedRules = result.rules
                    multipleChoiceFailed = result.multipleChoiceFailed
                } catch {
                    Log.warn("Rules refresh failed: \(error)")
                    rulesReadFailed = true
                }
            }

            let proxyState = await proxyStateTask

            await MainActor.run {
                guard self.refreshToken == token else { return }
                self.state.whistleStatus = whistleStatus
                self.state.proxyState = proxyState
                self.state.launchAtLoginEnabled = self.launchAtLoginService.isEnabled()
                self.state.rules = loadedRules
                self.state.rulesLoading = false
                self.state.rulesReadFailed = rulesReadFailed
                self.state.multipleChoiceFailed = multipleChoiceFailed
                self.rebuildMenu()

                if rulesReadFailed {
                    self.notificationService.send(
                        titleKey: "notification.rules.title",
                        bodyKey: "notification.rules.read_body"
                    )
                } else if multipleChoiceFailed && !self.didNotifyMultipleChoiceFailure {
                    self.didNotifyMultipleChoiceFailure = true
                    self.notificationService.send(
                        titleKey: "notification.rules.title",
                        bodyKey: "notification.rules.multiple_choice_body"
                    )
                }
            }
        }
    }

    @objc func openWebUI() {
        guard state.whistleStatus.hasUsableW2 else {
            notificationService.send(titleKey: "notification.w2.title", bodyKey: "notification.w2.body")
            return
        }
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8899")!)
    }

    @objc func toggleRule(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? RuleMenuPayload else { return }
        let rule = payload.rule
        guard !rule.isGroup else { return }

        state.rulesLoading = true
        state.rulesReadFailed = false
        rebuildMenu()

        Task {
            do {
                try await apiClient.toggle(rule)
                let result = try await apiClient.loadRulesEnsuringMultipleChoice()
                await MainActor.run {
                    self.state.rules = result.rules
                    self.state.rulesLoading = false
                    self.state.rulesReadFailed = false
                    self.state.multipleChoiceFailed = result.multipleChoiceFailed
                    self.rebuildMenu()
                }
            } catch {
                Log.warn("Rules toggle failed for \(rule.name): \(error)")
                await MainActor.run {
                    self.state.rulesLoading = false
                    self.state.rulesReadFailed = true
                    self.rebuildMenu()
                    self.notificationService.send(
                        titleKey: "notification.rules.title",
                        body: L10n.format("notification.rules.toggle_body_format", rule.displayName)
                    )
                }
            }
        }
    }

    @objc func toggleProxy() {
        let shouldEnable = state.proxyState != .enabled
        state.proxyState = .checking
        rebuildMenu()

        Task {
            do {
                try await w2CommandService.setProxyEnabled(shouldEnable)
                let refreshed = await systemProxyService.currentState()
                await MainActor.run {
                    self.state.proxyState = refreshed
                    self.rebuildMenu()
                }
            } catch {
                Log.warn("Proxy toggle failed: \(error)")
                await MainActor.run {
                    self.state.proxyState = .unknown
                    self.rebuildMenu()
                    self.notificationService.send(
                        titleKey: "notification.proxy.title",
                        bodyKey: "notification.proxy.body"
                    )
                }
            }
        }
    }

    @objc func toggleLaunchAtLogin() {
        let shouldEnable = !state.launchAtLoginEnabled
        do {
            try launchAtLoginService.setEnabled(shouldEnable)
            state.launchAtLoginEnabled = launchAtLoginService.isEnabled()
            rebuildMenu()
        } catch {
            Log.warn("Launch at login toggle failed: \(error)")
            notificationService.send(
                titleKey: "notification.launch.title",
                bodyKey: "notification.launch.body"
            )
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = Bundle.module.image(forResource: "StatusBarIconTemplate")
                ?? Bundle.main.image(forResource: "StatusBarIconTemplate")
                ?? NSImage(systemSymbolName: "network", accessibilityDescription: "whistle-menubar")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "whistle-menubar"
        }
    }

    private func rebuildMenu() {
        let menu = menuBuilder.build(state: state, target: self)
        menu.delegate = self
        statusItem.menu = menu
    }
}
