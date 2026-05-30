import Foundation

public final class W2Locator {
    private let configStore: ConfigStore
    private let commandRunner: CommandRunning
    private let fileManager: FileManager
    private let homeDirectory: URL

    public init(
        configStore: ConfigStore,
        commandRunner: CommandRunning,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.configStore = configStore
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    public func locate() async -> String? {
        let config = await configStore.load()
        if let cachedPath = config.w2Path, await isValidW2(at: cachedPath) {
            return cachedPath
        }

        for candidate in commonCandidates() {
            if await isValidW2(at: candidate) {
                await configStore.updateW2Path(candidate)
                return candidate
            }
        }

        if let shellPath = await shellLookup(login: false), await isValidW2(at: shellPath) {
            await configStore.updateW2Path(shellPath)
            return shellPath
        }

        if let npmPath = await npmPrefixCandidate(), await isValidW2(at: npmPath) {
            await configStore.updateW2Path(npmPath)
            return npmPath
        }

        if let interactivePath = await shellLookup(login: true), await isValidW2(at: interactivePath) {
            await configStore.updateW2Path(interactivePath)
            return interactivePath
        }

        await configStore.updateW2Path(nil)
        return nil
    }

    private func commonCandidates() -> [String] {
        [
            "/opt/homebrew/bin/w2",
            "/usr/local/bin/w2",
            homeDirectory.appendingPathComponent(".npm-global/bin/w2").path,
            homeDirectory.appendingPathComponent(".local/bin/w2").path,
            homeDirectory.appendingPathComponent(".npm-packages/bin/w2").path,
            "/usr/bin/w2",
            "/bin/w2"
        ]
    }

    private func shellLookup(login: Bool) async -> String? {
        do {
            let result = try await commandRunner.run(
                executable: "/bin/zsh",
                arguments: [login ? "-ic" : "-lc", "command -v w2"],
                timeout: 2,
                environment: nil
            )
            guard result.exitCode == 0 else { return nil }
            return firstPathLine(result.stdout)
        } catch {
            Log.warn("shell lookup for w2 failed: \(error)")
            return nil
        }
    }

    private func npmPrefixCandidate() async -> String? {
        do {
            let result = try await commandRunner.run(
                executable: "/bin/zsh",
                arguments: ["-lc", "npm config get prefix"],
                timeout: 2,
                environment: nil
            )
            guard result.exitCode == 0, let prefix = firstPathLine(result.stdout), !prefix.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: prefix).appendingPathComponent("bin/w2").path
        } catch {
            Log.warn("npm prefix lookup failed: \(error)")
            return nil
        }
    }

    private func firstPathLine(_ text: String) -> String? {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.hasPrefix("/") }
    }

    private func isValidW2(at path: String) async -> Bool {
        guard fileManager.fileExists(atPath: path), fileManager.isExecutableFile(atPath: path) else {
            return false
        }

        do {
            let result = try await commandRunner.run(
                executable: path,
                arguments: ["-V"],
                timeout: 2,
                environment: nil
            )
            let output = result.combinedOutput.lowercased()
            if result.exitCode == 0 {
                return true
            }
            return output.contains("whistle") || output.contains("w2")
        } catch {
            Log.warn("w2 validation failed for \(path): \(error)")
            return false
        }
    }
}
