import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var cacheCleared = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Динамический фон", isOn: $settings.dynamicBackground)
                    Toggle("Размытие неактивных строк", isOn: $settings.blurInactiveLines)
                    Toggle("Романизация (если есть)", isOn: $settings.showRomanization)
                    Toggle("Не гасить экран", isOn: $settings.keepScreenOn)
                    Toggle("Прятать интерфейс во время песни", isOn: $settings.autoHideControls)
                    Toggle("Полоска громкости", isOn: $settings.showVolumeSlider)
                    Toggle("Экономия батареи", isOn: $settings.powerSaving)
                    VStack(alignment: .leading) {
                        Text("Размер шрифта: \(Int(settings.fontSize))")
                        Slider(value: $settings.fontSize, in: 22...48, step: 1)
                    }
                } header: {
                    Text("Внешний вид")
                }

                Section {
                    Toggle("Обложка", isOn: $settings.landscapeArtwork)
                    Toggle("Название и исполнитель", isOn: $settings.landscapeTitle)
                } header: {
                    Text("Горизонтальный режим")
                } footer: {
                    Text("Если выключить и то и другое, текст займёт весь экран, а кнопки будут появляться слева по касанию.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Сдвиг текста: \(Int(settings.timingOffsetMs)) мс")
                        Slider(value: $settings.timingOffsetMs, in: -1500...1500, step: 50)
                    }
                    Button("Сбросить сдвиг") { settings.timingOffsetMs = 0 }
                } header: {
                    Text("Синхронизация")
                } footer: {
                    Text("Положительное значение показывает слова раньше. Помогает при задержке Bluetooth-наушников.")
                }

                Section {
                    if settings.hasBundledSpicyKey {
                        Label("Ключ Spicy Lyrics встроен в приложение", systemImage: "checkmark.seal.fill")
                    } else {
                        TextField("sl_pk_…", text: $settings.spicyLyricsKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                        if !settings.spicyLyricsKey.isEmpty && settings.validSpicyKey == nil {
                            Text(settings.spicyLyricsKey.hasPrefix("sl_sk_")
                                 ? "Это секретный ключ. Нужен клиентский ключ sl_pk_…"
                                 : "Ключ должен начинаться с sl_pk_")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        Link("Получить ключ Spicy Lyrics", destination: URL(string: "https://developers.spicylyrics.org")!)
                    }
                    Toggle("Запасной источник LRCLIB", isOn: $settings.useLRCLibFallback)
                    Button("Перезагрузить текст") {
                        player.loadLyrics(force: true)
                        dismiss()
                    }
                    Button(cacheCleared ? "Кэш очищен" : "Очистить кэш текстов") {
                        player.clearLyricsCache()
                        cacheCleared = true
                    }
                    .disabled(cacheCleared)
                } header: {
                    Text("Источники текстов")
                } footer: {
                    Text("С клиентским ключом используется публичный API /v1/lyrics. Без ключа приложение пробует авторизоваться токеном Spotify, как расширение для Spicetify.")
                }

                Section {
                    LabeledContent("Доступ", value: settings.usingBundledClientID
                                   ? "Встроенный"
                                   : "Свой Client ID …\(String(settings.spotifyClientID.suffix(4)))")
                    NavigationLink {
                        SpotifySetupGuideView()
                    } label: {
                        Label(settings.usingBundledClientID ? "Подключить свой Client ID" : "Сменить Client ID",
                              systemImage: "key.horizontal")
                    }
                    if settings.bundledSpotifyClientID != nil, settings.useOwnClientID {
                        Button("Вернуться к встроенному доступу") {
                            // The session belongs to the user's own Client ID: sign in again.
                            settings.useOwnClientID = false
                            auth.logOut()
                            dismiss()
                        }
                    }
                    Button("Выйти из Spotify", role: .destructive) {
                        auth.logOut()
                        dismiss()
                    }
                } header: {
                    Text("Spotify")
                } footer: {
                    Text("Встроенный доступ Spotify — максимум на 5 человек. Со своим Client ID ограничение снимается (нужен Spotify Premium).")
                }

                Section {
                    LabeledContent("Версия", value: AppVersion.display)
                    Link("Spicy Lyrics (оригинал)", destination: URL(string: "https://github.com/Spikerko/spicy-lyrics")!)
                    Link("Spicy Lyrics Mobile (Android)", destination: URL(string: "https://github.com/spicylyrics/mobile")!)
                    Link("LRCLIB", destination: URL(string: "https://lrclib.net")!)
                } header: {
                    Text("О приложении")
                } footer: {
                    Text("Неофициальный iOS-порт. Распространяется по лицензии AGPL-3.0, как и оригинал. Не связан со Spotify AB.")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
