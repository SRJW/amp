import Foundation
import SwiftUI
import Observation

/// Supported app display languages: System default plus the 13 major world languages.
enum AppLanguage: String, CaseIterable, Codable, Identifiable, Hashable {
    case system = "system"
    case english = "en"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"
    case hindi = "hi"
    case arabic = "ar"
    case portuguese = "pt"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case korean = "ko"
    case italian = "it"
    case russian = "ru"
    case turkish = "tr"

    var id: String { rawValue }

    /// The 13 explicit languages offered in Settings › Language.
    static let supportedLanguages: [AppLanguage] = [
        .english, .spanish, .chineseSimplified, .hindi, .arabic,
        .portuguese, .french, .german, .japanese, .korean,
        .italian, .russian, .turkish
    ]

    /// Name written in the language itself so a listener can always find their own language.
    var nativeName: String {
        switch self {
        case .system: "System default"
        case .english: "English"
        case .spanish: "Español"
        case .chineseSimplified: "简体中文"
        case .hindi: "हिन्दी"
        case .arabic: "العربية"
        case .portuguese: "Português"
        case .french: "Français"
        case .german: "Deutsch"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .italian: "Italiano"
        case .russian: "Русский"
        case .turkish: "Türkçe"
        }
    }

    /// Short uppercase badge shown next to each language row.
    var shortCode: String {
        switch self {
        case .system: "AUTO"
        case .english: "EN"
        case .spanish: "ES"
        case .chineseSimplified: "ZH"
        case .hindi: "HI"
        case .arabic: "AR"
        case .portuguese: "PT"
        case .french: "FR"
        case .german: "DE"
        case .japanese: "JA"
        case .korean: "KO"
        case .italian: "IT"
        case .russian: "RU"
        case .turkish: "TR"
        }
    }

    /// Resolves `.system` against iOS preferred languages, falling back to English.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        for preferred in Locale.preferredLanguages {
            let lower = preferred.lowercased()
            if lower.hasPrefix("zh") { return .chineseSimplified }
            let prefix = String(lower.prefix(2))
            if let match = Self.supportedLanguages.first(where: { $0.rawValue.lowercased() == prefix }) {
                return match
            }
        }
        return .english
    }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    var layoutDirection: LayoutDirection {
        resolved == .arabic ? .rightToLeft : .leftToRight
    }

    /// Localized name of this language in the currently active locale.
    func localizedName(in activeLocale: Locale) -> String {
        guard self != .system else { return nativeName }
        let display = activeLocale.localizedString(forIdentifier: rawValue)
            ?? activeLocale.localizedString(forLanguageCode: rawValue)
            ?? nativeName
        return display.prefix(1).uppercased(with: activeLocale) + display.dropFirst()
    }
}

/// Live in-app translation store backed by `translations.json` in the app bundle.
/// Because it is `@Observable`, views reading `L(...)` update immediately when the user switches languages.
@MainActor
@Observable
final class AppLocalization {
    static let shared = AppLocalization()

    var language: AppLanguage = .system {
        didSet {
            guard language != oldValue else { return }
            syncSystemPreference(language)
        }
    }

    @ObservationIgnored private let tables: [String: [String: String]]

    private init() {
        let url = Bundle.main.url(forResource: "translations", withExtension: "json")
            ?? Bundle.main.url(forResource: "translations", withExtension: "json", subdirectory: "Localization")
        if let url,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            tables = decoded
        } else {
            tables = [:]
        }
    }

    func apply(_ choice: AppLanguage) {
        if language != choice { language = choice }
        syncSystemPreference(choice)
    }

    func string(_ key: String) -> String {
        let code = language.resolved.rawValue
        if code == AppLanguage.english.rawValue { return key }
        return tables[code]?[key] ?? key
    }

    func format(_ key: String, _ args: [CVarArg]) -> String {
        let pattern = string(key)
        return String(format: pattern, locale: language.locale, arguments: args)
    }

    private func syncSystemPreference(_ choice: AppLanguage) {
        if choice == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([choice.rawValue], forKey: "AppleLanguages")
        }
    }
}

@MainActor
func L(_ key: String) -> String {
    AppLocalization.shared.string(key)
}

@MainActor
func L(_ key: String, _ args: CVarArg...) -> String {
    AppLocalization.shared.format(key, args)
}
