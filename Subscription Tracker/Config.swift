import Foundation

enum Config {
    private static let info: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return [:]
        }
        return dict
    }()

    static var backendHost: URL {
        if let v = info["backend_host"] as? String, let url = URL(string: v) {
            return url
        }
        // fallback
        return URL(string: "https://hippl.site")!
    }
}
