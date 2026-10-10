import NaturalLanguage
import SwiftUI
import Translation

/// Translates the current lyrics on the device with Apple's Translation framework (iOS 18+) and
/// hands the result to the player; the lyrics show it under each line. The first use of a
/// language pair makes iOS offer to download its model.
struct LyricsTranslation: ViewModifier {
    let player: PlayerModel
    let settings: AppSettings

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(TranslationDriver(player: player, settings: settings))
        } else {
            content
        }
    }

    /// Languages offered in settings (Apple Translation supports these on device).
    static let languages: [(id: String, name: String)] = [
        ("ru", "Русский"), ("en", "English"), ("uk", "Українська"), ("de", "Deutsch"),
        ("fr", "Français"), ("es", "Español"), ("it", "Italiano"), ("pt", "Português"),
        ("pl", "Polski"), ("tr", "Türkçe"), ("ja", "日本語"), ("ko", "한국어"), ("zh-Hans", "简体中文"),
    ]
}

@available(iOS 18.0, *)
@MainActor
private struct TranslationDriver: ViewModifier {
    let player: PlayerModel
    let settings: AppSettings
    @State private var configuration: TranslationSession.Configuration?

    /// Changes whenever there is something new to translate.
    private var key: String {
        "\(settings.translateLyrics)|\(settings.translationLanguage)|\(player.lyricsRevision)"
    }

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                await translate(with: session)
            }
            .onChange(of: key, initial: true) { _, _ in reconfigure() }
    }

    /// Unique original-language texts of the lead lines.
    private func pendingTexts() -> [String] {
        guard settings.translateLyrics, case .loaded(let lyrics) = player.lyricsState else { return [] }
        let texts = lyrics.lines
            .filter { !$0.isInterlude && !$0.isBackground }
            .map(\.sourceText)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Array(Set(texts))
    }

    private func sourceLanguage(of texts: [String]) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(texts.joined(separator: "\n"))
        return recognizer.dominantLanguage
    }

    private func reconfigure() {
        let texts = pendingTexts()
        guard !texts.isEmpty else { return }
        let target = Locale.Language(identifier: settings.translationLanguage)
        let source = sourceLanguage(of: texts)
        // A song already in the target language needs no translation.
        if let source, let code = target.languageCode?.identifier, source.rawValue.hasPrefix(code) { return }
        let sourceLanguage = source.map { Locale.Language(identifier: $0.rawValue) }
        if configuration?.source == sourceLanguage, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: sourceLanguage, target: target)
        }
    }

    private func translate(with session: TranslationSession) async {
        let texts = pendingTexts()
        guard !texts.isEmpty else { return }
        let revision = player.lyricsRevision
        let requests = texts.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
        do {
            var result: [String: String] = [:]
            for response in try await session.translations(from: requests) {
                if let id = response.clientIdentifier { result[id] = response.targetText }
            }
            player.setTranslations(result, revision: revision)
        } catch {
            // An unsupported language pair or a declined download: show the lyrics untranslated.
        }
    }
}
