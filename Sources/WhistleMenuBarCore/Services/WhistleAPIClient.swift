import Foundation

public struct RulesLoadResult: Equatable, Sendable {
    public let rules: [RuleItem]
    public let multipleChoiceFailed: Bool
}

public enum WhistleAPIError: Error, LocalizedError, Equatable {
    case invalidURL(String)
    case invalidResponse
    case httpStatus(url: String, status: Int, body: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid Whistle API URL: \(path)"
        case .invalidResponse:
            return "Invalid Whistle API response"
        case .httpStatus(let url, let status, let body):
            return "Whistle API failed url=\(url) status=\(status) body=\(body.truncatedForLog())"
        case .decoding(let message):
            return "Whistle API decode failed: \(message)"
        }
    }
}

public final class WhistleAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        host: String = "127.0.0.1",
        port: Int = 8899,
        session: URLSession = .shared
    ) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func loadRulesEnsuringMultipleChoice() async throws -> RulesLoadResult {
        let initial = try await fetchRulesList()
        let initialRules = initial.ruleItems()

        guard initial.allowMultipleChoice != true else {
            return RulesLoadResult(rules: initialRules, multipleChoiceFailed: false)
        }

        do {
            try await enableMultipleChoice()
            let refreshed = try await fetchRulesList()
            return RulesLoadResult(rules: refreshed.ruleItems(), multipleChoiceFailed: false)
        } catch {
            Log.warn("Failed to enable multiple choice rules: \(error)")
            return RulesLoadResult(rules: initialRules, multipleChoiceFailed: true)
        }
    }

    public func toggle(_ rule: RuleItem) async throws {
        guard !rule.isGroup else { return }

        if rule.isDefault {
            try await post(path: rule.isSelected ? "/cgi-bin/rules/disable-default" : "/cgi-bin/rules/enable-default")
        } else {
            try await post(
                path: rule.isSelected ? "/cgi-bin/rules/unselect" : "/cgi-bin/rules/select",
                form: ["name": rule.name]
            )
        }
    }

    public func fetchRulesList() async throws -> RulesListResponse {
        var request = try makeRequest(path: "/cgi-bin/rules/list", method: "GET")
        request.timeoutInterval = 5

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhistleAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WhistleAPIError.httpStatus(
                url: request.url?.absoluteString ?? "",
                status: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        do {
            return try decoder.decode(RulesListResponse.self, from: data)
        } catch {
            throw WhistleAPIError.decoding(String(describing: error))
        }
    }

    public func enableMultipleChoice() async throws {
        try await post(
            path: "/cgi-bin/rules/allow-multiple-choice",
            form: ["allowMultipleChoice": "1"]
        )
    }

    private func post(path: String, form: [String: String] = [:]) async throws {
        var request = try makeRequest(path: path, method: "POST")
        request.timeoutInterval = 5
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(form).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhistleAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WhistleAPIError.httpStatus(
                url: request.url?.absoluteString ?? "",
                status: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw WhistleAPIError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func formURLEncoded(_ form: [String: String]) -> String {
        form
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
    }
}

public struct RulesListResponse: Decodable, Equatable, Sendable {
    public let ec: Int?
    public let enabledCount: Int?
    public let defaultRulesIsDisabled: Bool?
    public let defaultRules: String?
    public let allowMultipleChoice: Bool?
    public let backRulesFirst: Bool?
    public let list: [RawRuleItem]

    public init(
        ec: Int?,
        enabledCount: Int?,
        defaultRulesIsDisabled: Bool?,
        defaultRules: String?,
        allowMultipleChoice: Bool?,
        backRulesFirst: Bool?,
        list: [RawRuleItem]
    ) {
        self.ec = ec
        self.enabledCount = enabledCount
        self.defaultRulesIsDisabled = defaultRulesIsDisabled
        self.defaultRules = defaultRules
        self.allowMultipleChoice = allowMultipleChoice
        self.backRulesFirst = backRulesFirst
        self.list = list
    }

    public func ruleItems() -> [RuleItem] {
        let defaultItem = RuleItem(
            id: "__default__",
            name: "Default",
            displayName: L10n.string("menu.rules.default"),
            isSelected: !(defaultRulesIsDisabled ?? false),
            isDefault: true,
            isGroup: false
        )

        let normalItems = list.map { raw in
            let isGroup = raw.isRuleGroup
            let displayName = isGroup ? L10n.format("menu.rules.group_format", raw.name) : raw.name
            return RuleItem(
                id: raw.name,
                name: raw.name,
                displayName: displayName,
                isSelected: raw.selected == true,
                isDefault: false,
                isGroup: isGroup
            )
        }

        return [defaultItem] + normalItems
    }
}

public struct RawRuleItem: Decodable, Equatable, Sendable {
    public let name: String
    public let selected: Bool?
    public let data: String?
    public let isGroup: Bool?
    public let group: Bool?

    public init(
        name: String,
        selected: Bool?,
        data: String?,
        isGroup: Bool?,
        group: Bool?
    ) {
        self.name = name
        self.selected = selected
        self.data = data
        self.isGroup = isGroup
        self.group = group
    }

    public var isRuleGroup: Bool {
        if isGroup == true { return true }
        if group == true { return true }
        return false
    }
}
