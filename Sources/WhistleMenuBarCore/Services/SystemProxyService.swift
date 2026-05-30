import Foundation

public final class SystemProxyService {
    private let commandRunner: CommandRunning
    private let host: String
    private let port: Int

    public init(
        commandRunner: CommandRunning,
        host: String = "127.0.0.1",
        port: Int = 8899
    ) {
        self.commandRunner = commandRunner
        self.host = host
        self.port = port
    }

    public func currentState() async -> ProxyState {
        do {
            let result = try await commandRunner.run(
                executable: "/usr/sbin/scutil",
                arguments: ["--proxy"],
                timeout: 2,
                environment: nil
            )
            guard result.exitCode == 0 else {
                Log.warn("scutil --proxy failed: \(result.combinedOutput.truncatedForLog())")
                return .unknown
            }
            return ProxyStateParser.parse(result.stdout, host: host, port: port)
        } catch {
            Log.warn("scutil --proxy failed: \(error)")
            return .unknown
        }
    }
}
