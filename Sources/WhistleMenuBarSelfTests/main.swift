import Foundation
import WhistleMenuBarCore

@main
struct WhistleMenuBarSelfTests {
    static func main() async throws {
        var passed = 0

        try await run("w2 status parser running") {
            let output = """
            [!] Whistle@2.10.2 is running
            [i] 1. Use your device to visit these URLs and note which one works:
                   http://127.0.0.1:8899/
            """
            try expect(W2StatusParser.parse(stdout: output, stderr: "", exitCode: 0) == .running)
        }
        passed += 1

        try await run("w2 status parser stopped") {
            try expect(W2StatusParser.parse(stdout: "whistle is not running", stderr: "", exitCode: 0) == .stopped)
        }
        passed += 1

        try await run("w2 status parser unknown") {
            try expect(W2StatusParser.parse(stdout: "", stderr: "permission denied", exitCode: 1) == .unknown("permission denied"))
        }
        passed += 1

        try await run("proxy parser enabled") {
            let output = """
            <dictionary> {
              HTTPEnable : 1
              HTTPProxy : 127.0.0.1
              HTTPPort : 8899
              HTTPSEnable : 1
              HTTPSProxy : 127.0.0.1
              HTTPSPort : 8899
            }
            """
            try expect(ProxyStateParser.parse(output) == .enabled)
        }
        passed += 1

        try await run("proxy parser disabled") {
            let output = """
            <dictionary> {
              HTTPEnable : 0
              HTTPSEnable : 0
            }
            """
            try expect(ProxyStateParser.parse(output) == .disabled)
        }
        passed += 1

        try await run("proxy parser partial") {
            let output = """
            <dictionary> {
              HTTPEnable : 1
              HTTPProxy : 127.0.0.1
              HTTPPort : 8899
              HTTPSEnable : 0
            }
            """
            try expect(ProxyStateParser.parse(output) == .partial)
        }
        passed += 1

        try await run("rules decoding and default rule construction") {
            let json = """
            {
              "ec": 0,
              "enabledCount": 1,
              "defaultRulesIsDisabled": false,
              "allowMultipleChoice": true,
              "backRulesFirst": false,
              "list": [
                { "name": "rule-a", "selected": true, "data": "x" },
                { "name": "frontend", "isGroup": true },
                { "name": "rule-b", "selected": false }
              ]
            }
            """.data(using: .utf8)!

            let response = try JSONDecoder().decode(RulesListResponse.self, from: json)
            let rules = response.ruleItems()

            try expect(rules.first?.id == "__default__")
            try expect(rules.first?.displayName == L10n.string("menu.rules.default"))
            try expect(rules.first?.isSelected == true)
            try expect(rules[1].name == "rule-a")
            try expect(rules[1].isSelected == true)
            try expect(rules[2].isGroup == true)
            try expect(rules[2].displayName == L10n.format("menu.rules.group_format", "frontend"))
        }
        passed += 1

        try await run("rules API enables multiple choice and refetches") {
            let session = makeMockSession { request in
                MockHTTP.record(request)
                let path = request.url?.path ?? ""
                let method = request.httpMethod ?? ""

                if method == "GET", path == "/cgi-bin/rules/list", MockHTTP.requests.count == 1 {
                    return .json("""
                    {
                      "allowMultipleChoice": false,
                      "defaultRulesIsDisabled": false,
                      "list": [
                        { "name": "rule-a", "selected": true }
                      ]
                    }
                    """)
                }

                if method == "POST", path == "/cgi-bin/rules/allow-multiple-choice" {
                    try expect(MockHTTP.body(of: request) == "allowMultipleChoice=1")
                    return .ok()
                }

                if method == "GET", path == "/cgi-bin/rules/list", MockHTTP.requests.count == 3 {
                    return .json("""
                    {
                      "allowMultipleChoice": true,
                      "defaultRulesIsDisabled": false,
                      "list": [
                        { "name": "rule-a", "selected": true },
                        { "name": "rule-b", "selected": true }
                      ]
                    }
                    """)
                }

                throw TestFailure("unexpected request \(method) \(path)")
            }

            let client = WhistleAPIClient(session: session)
            let result = try await client.loadRulesEnsuringMultipleChoice()

            try expect(result.multipleChoiceFailed == false)
            try expect(result.rules.map(\.name) == ["Default", "rule-a", "rule-b"])
            try expect(MockHTTP.summary == [
                "GET /cgi-bin/rules/list",
                "POST /cgi-bin/rules/allow-multiple-choice",
                "GET /cgi-bin/rules/list"
            ])
        }
        passed += 1

        try await run("rules API toggle paths and form bodies") {
            let session = makeMockSession { request in
                MockHTTP.record(request)
                return .ok()
            }
            let client = WhistleAPIClient(session: session)

            try await client.toggle(RuleItem(
                id: "rule-a",
                name: "rule-a",
                displayName: "rule-a",
                isSelected: false,
                isDefault: false,
                isGroup: false,
                value: "rule-a-content"
            ))
            try expect(MockHTTP.lastBody == "name=rule-a&value=rule-a-content")

            try await client.toggle(RuleItem(
                id: "rule-a",
                name: "rule-a",
                displayName: "rule-a",
                isSelected: true,
                isDefault: false,
                isGroup: false,
                value: "rule-a-content"
            ))
            try expect(MockHTTP.lastBody == "name=rule-a&value=rule-a-content")

            try await client.toggle(RuleItem(
                id: "__default__",
                name: "Default",
                displayName: "Default Rules",
                isSelected: true,
                isDefault: true,
                isGroup: false,
                value: "default-content"
            ))
            try expect(MockHTTP.lastBody == "name=Default&value=default-content")

            try await client.toggle(RuleItem(
                id: "__default__",
                name: "Default",
                displayName: "Default Rules",
                isSelected: false,
                isDefault: true,
                isGroup: false,
                value: "default-content"
            ))
            try expect(MockHTTP.lastBody == "name=Default&value=default-content")

            try expect(MockHTTP.summary == [
                "POST /cgi-bin/rules/select",
                "POST /cgi-bin/rules/unselect",
                "POST /cgi-bin/rules/disable-default",
                "POST /cgi-bin/rules/enable-default"
            ])
        }
        passed += 1

        try await run("rules API HTTP errors omit response body") {
            let sensitiveBody = "token=secret-token&rule=internal.example.com"
            let session = makeMockSession { request in
                MockHTTP.record(request)
                return .failure(status: 500, body: sensitiveBody)
            }
            let client = WhistleAPIClient(session: session)

            do {
                _ = try await client.fetchRulesList()
                throw TestFailure("expected HTTP status failure")
            } catch let error as WhistleAPIError {
                let diagnostic = String(describing: error)
                let localized = error.localizedDescription

                try expect(diagnostic.contains("status: 500"))
                try expect(localized.contains("status=500"))
                try expect(!diagnostic.contains(sensitiveBody))
                try expect(!localized.contains(sensitiveBody))
                try expect(!diagnostic.contains("secret-token"))
                try expect(!localized.contains("secret-token"))
            }
        }
        passed += 1

        try await run("default rules disabled flag") {
            let response = RulesListResponse(
                ec: 0,
                enabledCount: 0,
                defaultRulesIsDisabled: true,
                defaultRules: nil,
                allowMultipleChoice: true,
                backRulesFirst: false,
                list: []
            )
            try expect(response.ruleItems().first?.isSelected == false)
        }
        passed += 1

        try await run("w2 locator invalid cache fallback") {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("whistle-menubar-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDirectory) }

            let validW2 = tempDirectory.appendingPathComponent("w2")
            _ = FileManager.default.createFile(atPath: validW2.path, contents: Data("#!/bin/sh\n".utf8))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: validW2.path)

            let configStore = ConfigStore(configURL: tempDirectory.appendingPathComponent("config.json"))
            await configStore.save(AppConfig(w2Path: tempDirectory.appendingPathComponent("missing-w2").path))

            let runner = FakeCommandRunner { executable, arguments in
                if executable == "/bin/zsh", arguments == ["-lc", "command -v w2"] {
                    return CommandResult(exitCode: 0, stdout: "\(validW2.path)\n", stderr: "")
                }
                if executable == validW2.path, arguments == ["-V"] {
                    return CommandResult(exitCode: 0, stdout: "2.10.2\n", stderr: "")
                }
                return CommandResult(exitCode: 1, stdout: "", stderr: "unexpected command")
            }

            let locator = W2Locator(
                configStore: configStore,
                commandRunner: runner,
                homeDirectory: tempDirectory
            )

            let located = await locator.locate()
            let updatedConfig = await configStore.load()

            try expect(located == validW2.path)
            try expect(updatedConfig.w2Path == validW2.path)
            try expect(updatedConfig.detectedAt != nil)
        }
        passed += 1

        try await run("real w2 locator smoke when w2 exists") {
            let commandRunner = ShellCommand()
            let shellLookup = try await commandRunner.run(
                executable: "/bin/zsh",
                arguments: ["-lc", "command -v w2"],
                timeout: 2,
                environment: nil
            )
            let shellPath = shellLookup.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

            let home = FileManager.default.homeDirectoryForCurrentUser
            let commonCandidates = [
                "/opt/homebrew/bin/w2",
                "/usr/local/bin/w2",
                home.appendingPathComponent(".npm-global/bin/w2").path,
                home.appendingPathComponent(".local/bin/w2").path,
                home.appendingPathComponent(".npm-packages/bin/w2").path
            ]
            let hasKnownW2 = commonCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
            guard shellLookup.exitCode == 0 && !shellPath.isEmpty || hasKnownW2 else {
                print("SKIP real w2 locator smoke: w2 not present in known locations")
                return
            }

            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("whistle-menubar-real-w2-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDirectory) }

            let locator = W2Locator(
                configStore: ConfigStore(configURL: tempDirectory.appendingPathComponent("config.json")),
                commandRunner: commandRunner
            )
            let located = await locator.locate()
            try expect(located != nil, "w2 exists in shell PATH but W2Locator returned nil")
            print("INFO real w2 located at \(located ?? "")")
        }
        passed += 1

        try await run("required localization keys resolve") {
            let keys = [
                "menu.open_webui",
                "menu.status.checking",
                "menu.status.w2_unavailable",
                "menu.status.running",
                "menu.status.stopped",
                "menu.status.unknown",
                "menu.rules.title",
                "menu.rules.default",
                "menu.rules.read_failed",
                "menu.rules.multiple_choice_failed",
                "menu.proxy",
                "menu.launch_at_login",
                "menu.quit",
                "notification.rules.title",
                "notification.proxy.title",
                "notification.launch.title"
            ]

            for key in keys {
                try expect(L10n.string(key) != key, "Missing localization for \(key)")
            }
        }
        passed += 1

        print("whistle-menubar self tests passed: \(passed)")
    }

    private static func run(_ name: String, body: () async throws -> Void) async throws {
        do {
            try await body()
            print("PASS \(name)")
        } catch {
            print("FAIL \(name): \(error)")
            throw error
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String = "expectation failed") throws {
        if !condition() {
            throw TestFailure(message)
        }
    }

    private static func makeMockSession(
        handler: @escaping (URLRequest) throws -> MockHTTP.Response
    ) -> URLSession {
        MockHTTP.reset(handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

final class FakeCommandRunner: CommandRunning {
    var handler: (String, [String]) async throws -> CommandResult

    init(handler: @escaping (String, [String]) async throws -> CommandResult) {
        self.handler = handler
    }

    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]?
    ) async throws -> CommandResult {
        try await handler(executable, arguments)
    }
}

enum MockHTTP {
    struct Response {
        let statusCode: Int
        let body: Data
        let headers: [String: String]

        static func ok() -> Response {
            Response(statusCode: 200, body: Data("{}".utf8), headers: [:])
        }

        static func json(_ text: String) -> Response {
            Response(
                statusCode: 200,
                body: Data(text.utf8),
                headers: ["Content-Type": "application/json"]
            )
        }

        static func failure(status: Int, body: String) -> Response {
            Response(statusCode: status, body: Data(body.utf8), headers: [:])
        }
    }

    private static let lock = NSLock()
    private static var handler: ((URLRequest) throws -> Response)?
    private(set) static var requests: [URLRequest] = []
    private(set) static var summary: [String] = []
    private(set) static var lastBody: String?

    static func reset(handler: @escaping (URLRequest) throws -> Response) {
        lock.lock()
        self.handler = handler
        requests = []
        summary = []
        lastBody = nil
        lock.unlock()
    }

    static func response(for request: URLRequest) throws -> Response {
        lock.lock()
        let handler = self.handler
        lock.unlock()

        guard let handler else {
            throw TestFailure("missing mock HTTP handler")
        }
        return try handler(request)
    }

    static func record(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        summary.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
        lastBody = body(of: request)
        lock.unlock()
    }

    static func body(of request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8)
    }
}

final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let mock = try MockHTTP.response(for: request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: mock.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: mock.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mock.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
