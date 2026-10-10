import SwiftUI

/// First run: explains the one-time Spotify developer app setup and signs in.
struct OnboardingView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @Environment(AppSettings.self) private var settings
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        @Bindable var settings = settings
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

                    // A Client ID built into the app skips the developer-app setup.
                    if !settings.hasBundledSpotifyClientID {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Подключение Spotify (один раз)")
                                .font(.headline)
                            step(1, "Откройте developer.spotify.com/dashboard и создайте приложение (Create app).")
                            step(2, "В поле Redirect URI добавьте:")
                            HStack {
                                Text(SpotifyAuth.redirectURI)
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = SpotifyAuth.redirectURI
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                            .padding(12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            step(3, "Отметьте Web API, сохраните. В User Management добавьте свой e-mail Spotify.")
                            step(4, "Скопируйте Client ID и вставьте ниже.")
                            Link("Открыть Spotify Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                                .font(.callout.weight(.semibold))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Client ID")
                                .font(.headline)
                            TextField("например 3f2a…", text: $settings.spotifyClientID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body.monospaced())
                                .padding(12)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }

                    }

                    if let error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

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
                    .disabled(busy || settings.effectiveSpotifyClientID.isEmpty)

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

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.15), in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
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
