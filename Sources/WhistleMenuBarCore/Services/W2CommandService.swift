import Foundation

public enum W2CommandError: Error, LocalizedError {
    case unavailable
    case failed(CommandResult)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "w2 unavailable"
        case .failed(let result):
            return "w2 command failed with exit code \(result.exitCode): \(result.combinedOutput.truncatedForLog())"
        }
    }
}

public final class W2CommandService {
    private let locator: W2Locator
    private let commandRunner: CommandRunning

    public init(locator: W2Locator, commandRunner: CommandRunning) {
        self.locator = locator
        self.commandRunner = commandRunner
    }

    public func getStatus() async -> WhistleStatus {
        guard let w2Path = await locator.locate() else {
            return .w2Unavailable
        }

        do {
            let result = try await commandRunner.run(
                executable: w2Path,
                arguments: ["status"],
                timeout: 3,
                environment: nil
            )
            return W2StatusParser.parse(
                stdout: result.stdout,
                stderr: result.stderr,
                exitCode: result.exitCode
            )
        } catch {
            Log.warn("w2 status failed: \(error)")
            return .unknown(String(describing: error))
        }
    }

    public func setProxyEnabled(_ enabled: Bool) async throws {
        guard let w2Path = await locator.locate() else {
            throw W2CommandError.unavailable
        }

        let arguments = enabled ? ["proxy"] : ["proxy", "0"]
        let result = try await commandRunner.run(
            executable: w2Path,
            arguments: arguments,
            timeout: 10,
            environment: nil
        )
        guard result.exitCode == 0 else {
            throw W2CommandError.failed(result)
        }
    }
}
