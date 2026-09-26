import Foundation

enum AppLocalization {
    static func string(_ key: String, locale: Locale, bundle: Bundle = .main) -> String {
        let resourceName = resourceName(for: locale)
        guard let path = bundle.path(forResource: resourceName, ofType: "lproj"),
              let localizedBundle = Bundle(path: path)
        else {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func resourceName(for locale: Locale) -> String {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if identifier.hasPrefix("zh-Hant") { return "zh-Hant" }
        if identifier.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }
}
