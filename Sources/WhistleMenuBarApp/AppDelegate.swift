import AppKit
import WhistleMenuBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let commandRunner = ShellCommand()
        let configStore = ConfigStore()
        let locator = W2Locator(configStore: configStore, commandRunner: commandRunner)
        let notificationService = NotificationService()
        notificationService.requestAuthorization()

        statusBarController = StatusBarController(
            w2CommandService: W2CommandService(locator: locator, commandRunner: commandRunner),
            systemProxyService: SystemProxyService(commandRunner: commandRunner),
            apiClient: WhistleAPIClient(),
            launchAtLoginService: LaunchAtLoginService(),
            notificationService: notificationService
        )
        statusBarController?.refreshMenuData()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
