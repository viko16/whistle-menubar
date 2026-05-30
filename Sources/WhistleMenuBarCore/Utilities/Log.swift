import Foundation

public enum Log {
    public static func info(_ message: String) {
        print("[whistle-menubar] \(message)")
    }

    public static func warn(_ message: String) {
        print("[whistle-menubar] WARN \(message)")
    }
}

public extension String {
    func truncatedForLog(limit: Int = 2_000) -> String {
        if count <= limit {
            return self
        }
        let index = self.index(startIndex, offsetBy: limit)
        return String(self[..<index]) + "…"
    }

    var urlFormEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
