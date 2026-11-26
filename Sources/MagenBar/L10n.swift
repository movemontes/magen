// Idiomas: o app é escrito em português; `tr` troca pelo inglês quando o Mac
// (ou a escolha no menu) está em outro idioma. Como a tabela core/en.json do Treco.
import Foundation

enum Lang {
    static let key = "idioma"
    /// "pt" or "en". The person's choice in the menu wins; otherwise the Mac's language.
    static var current: String {
        if let forced = ProcessInfo.processInfo.environment["MAGEN_LANG"], ["pt", "en"].contains(forced) { return forced } // tests
        if let chosen = UserDefaults.standard.string(forKey: key), ["pt", "en"].contains(chosen) { return chosen }
        let first = Locale.preferredLanguages.first?.lowercased() ?? "pt"
        return first.hasPrefix("pt") ? "pt" : "en"
    }
    static var isEnglish: Bool { current == "en" }
    static func set(_ lang: String) { UserDefaults.standard.set(lang, forKey: key) }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "pt_BR") }
}

/// Text in the app's language. Unknown texts stay in Portuguese.
func tr(_ pt: String) -> String {
    guard Lang.isEnglish else { return pt }
    return english[pt] ?? pt
}

/// Same, for texts with blanks (%@ for words, %d for numbers).
func trf(_ pt: String, _ args: CVarArg...) -> String {
    String(format: tr(pt), locale: Lang.locale, arguments: args)
}

/// Numbers and dates in the app's language (1.156.935 / 1,156,935).
func num(_ n: Int) -> String { n.formatted(.number.locale(Lang.locale)) }
