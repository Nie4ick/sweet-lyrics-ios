import SwiftUI

/// First run: sign in with the built-in Client ID, or set up one's own (step-by-step guide).
struct OnboardingView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @Environment(AppSettings.self) private var settings
    @State private var error: String?
    @State private var busy = false

    private var canLogIn: Bool {
        settings.usingBundledClientID || AppSettings.isValidClientID(settings.spotifyClientID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Spicy Lyrics")
                            .font(.system(size: 40, weight: .heavy))
                        Text("Синхронные по словам тексты для того, что играет у вас в Spotify.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    if canLogIn {
                        loginButton
                    }

                    accessExplanation

                    NavigationLink {
                        SpotifySetupGuideView()
                    } label: {
                        Label(canLogIn ? "Подключить свой Client ID" : "Настроить доступ к Spotify (5 минут)",
                              systemImage: "key.horizontal")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(canLogIn ? 0.12 : 0.9), in: Capsule())
                            .foregroundStyle(canLogIn ? .white : .black)
                    }

                    if settings.bundledSpotifyClientID != nil, settings.useOwnClientID {
                        Button("Вернуться к встроенному доступу") {
                            settings.useOwnClientID = false
                        }
                        .font(.callout.weight(.semibold))
                    }

                    Text("Приложение не связано со Spotify AB и с авторами Spicy Lyrics. Это неофициальный порт расширения Spicy Lyrics под AGPL-3.0.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.25, green: 0.1, blue: 0.35), .black],
                               startPoint: .topLeading, endPoint: .bottom)
                    .ignoresSafeArea()
            )
        }
    }

    private var loginButton: some View {
        Button {
            Task { await logIn() }
        } label: {
            HStack {
                if busy { ProgressView().tint(.black) }
                Text("Войти через Spotify")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 0.12, green: 0.84, blue: 0.38), in: Capsule())
            .foregroundStyle(.black)
        }
        .disabled(busy)
    }

    @ViewBuilder
    private var accessExplanation: some View {
        if settings.usingBundledClientID {
            Text("Встроенный доступ Spotify рассчитан только на 5 человек. Если после входа появится ошибка доступа, подключите свой Client ID: это бесплатно, нужен Spotify Premium.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        } else if canLogIn {
            Text("Используется ваш Client ID …\(String(settings.spotifyClientID.suffix(4))).")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        } else {
            Text("Чтобы приложение видело, что играет в Spotify, нужен свой Client ID из бесплатного кабинета разработчика Spotify. Пошаговая инструкция — по кнопке ниже.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func logIn() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await auth.logIn()
        } catch SpotifyAuthError.cancelled {
            // Nothing to report.
        } catch {
            self.error = error.localizedDescription
        }
    }
}
