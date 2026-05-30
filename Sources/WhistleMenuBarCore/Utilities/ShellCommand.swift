import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combinedOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public protocol CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]?
    ) async throws -> CommandResult
}

public enum ShellCommandError: Error, LocalizedError, Equatable {
    case launchFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .timedOut:
            return "Command timed out"
        }
    }
}

public final class ShellCommand: CommandRunning {
    public static let defaultPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private let maxOutputBytes: Int

    public init(maxOutputBytes: Int = 128 * 1024) {
        self.maxOutputBytes = maxOutputBytes
    }

    public func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment["PATH"] = ShellCommand.enrichedPATH(existing: mergedEnvironment["PATH"])
        environment?.forEach { mergedEnvironment[$0.key] = $0.value }
        process.environment = mergedEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = LockedDataBuffer(limit: maxOutputBytes)
        let stderrBuffer = LockedDataBuffer(limit: maxOutputBytes)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutBuffer.append(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrBuffer.append(data)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let state = CompletionState()
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            let cleanup = ProcessCleanup(timer: timer, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

            process.terminationHandler = { process in
                cleanup.perform()
                let result = CommandResult(
                    exitCode: process.terminationStatus,
                    stdout: stdoutBuffer.stringValue,
                    stderr: stderrBuffer.stringValue
                )
                state.resumeOnce {
                    continuation.resume(returning: result)
                }
            }

            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    process.terminate()
                }
                cleanup.perform()
                state.resumeOnce {
                    continuation.resume(throwing: ShellCommandError.timedOut)
                }
            }
            timer.resume()

            do {
                try process.run()
            } catch {
                cleanup.perform()
                state.resumeOnce {
                    continuation.resume(throwing: ShellCommandError.launchFailed(String(describing: error)))
                }
            }
        }
    }

    public static func enrichedPATH(existing: String? = ProcessInfo.processInfo.environment["PATH"]) -> String {
        var components: [String] = []
        if let existing, !existing.isEmpty {
            components.append(contentsOf: existing.split(separator: ":").map(String.init))
        }

        components.append(contentsOf: userToolPaths())
        components.append(contentsOf: defaultPATH.split(separator: ":").map(String.init))

        var seen = Set<String>()
        return components
            .filter { !$0.isEmpty }
            .filter { path in
                if seen.contains(path) {
                    return false
                }
                seen.insert(path)
                return true
            }
            .joined(separator: ":")
    }

    private static func userToolPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".npm-packages/bin").path,
            home.appendingPathComponent(".volta/bin").path,
            home.appendingPathComponent(".asdf/shims").path
        ]

        paths.append(contentsOf: versionedNodeBins(
            under: home.appendingPathComponent(".local/share/fnm/node-versions"),
            suffix: "installation/bin"
        ))
        paths.append(contentsOf: versionedNodeBins(
            under: home.appendingPathComponent(".nvm/versions/node"),
            suffix: "bin"
        ))
        paths.append(contentsOf: immediateBinDirectories(
            under: home.appendingPathComponent(".local/state/fnm_multishells")
        ))

        return paths.filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func versionedNodeBins(under baseURL: URL, suffix: String) -> [String] {
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return versions.map { $0.appendingPathComponent(suffix).path }
    }

    private static func immediateBinDirectories(under baseURL: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return entries.map { $0.appendingPathComponent("bin").path }
    }
}

private final class ProcessCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private let timer: DispatchSourceTimer
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private var didCleanup = false

    init(timer: DispatchSourceTimer, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.timer = timer
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    func perform() {
        lock.lock()
        defer { lock.unlock() }
        guard !didCleanup else { return }
        didCleanup = true
        timer.cancel()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }
}

private final class CompletionState {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        body()
    }
}

private final class LockedDataBuffer {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard data.count < limit else { return }
        let remaining = limit - data.count
        if newData.count <= remaining {
            data.append(newData)
        } else {
            data.append(newData.prefix(remaining))
        }
    }

    var stringValue: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
