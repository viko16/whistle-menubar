import Foundation

public enum L10n {
    public static func string(_ key: String) -> String {
        localizationBundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    private static var localizationBundle: Bundle {
        let candidates: [Bundle?] = [
            Bundle.main,
            Bundle.module,
            Bundle.main.resourceURL.flatMap {
                Bundle(url: $0.appendingPathComponent("WhistleMenuBarCore_WhistleMenuBarCore.resources"))
            },
            Bundle.main.resourceURL.flatMap {
                Bundle(url: $0.appendingPathComponent("WhistleMenuBarCore_WhistleMenuBarCore.bundle"))
            }
        ]

        return candidates.compactMap { $0 }.first { bundle in
            bundle.path(forResource: "Localizable", ofType: "strings") != nil ||
                bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "zh-Hans") != nil ||
                bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil
        } ?? .module
    }
}
