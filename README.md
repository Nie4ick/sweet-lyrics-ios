# Spicy Lyrics для iOS (неофициальный порт)

Отдельное iOS-приложение, которое показывает синхронизированные **по словам** тексты песен,
играющих у вас в Spotify. Это порт расширения [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics)
для Spicetify, по образцу Android-версии [spicylyrics/mobile](https://github.com/spicylyrics/mobile).

## Что перенесено

| Функция | Как сделано на iOS |
| --- | --- |
| Подсветка по словам | Порт `LyricsAnimator.ts` 1:1: состояния NotSung/Active/Sung, градиентная заливка слога, кривые scale/y-offset/glow (кубические сплайны) и пружины [spr](https://github.com/Fraktality/spr) |
| Побуквенная анимация | Слоги длиннее 1 с разбиваются на буквы с эффектом «близости» к активной букве, как в `Emphasize.ts` |
| Размытие строк | Размытие растёт с расстоянием от активной строки (`BlurMultiplier = 1.25`) |
| Дуэты и бэк-вокал | `OppositeAligned` выравнивается вправо, бэк-вокал рисуется мельче под основной строкой |
| Проигрыши | Три анимированные точки при паузе ≥ 3 с |
| Построчные и статичные тексты | Типы `Line` и `Static` |
| Динамический фон | Размытая обложка с Metal-шейдером искажения (аналог Kawarp) |
| Источник текстов | API Spicy Lyrics, запасной вариант — [LRCLIB](https://lrclib.net) |
| Романизация | Если API её отдаёт (`TransliteratedText`) |
| Перемотка | Нажмите на строку, чтобы перемотать к ней (нужен Spotify Premium) |

## Как приложение связано со Spotify

iOS не даёт приложениям читать, что играет в других приложениях, поэтому Spotify подключается
через официальный **Spotify Web API**:

- вход через OAuth (Authorization Code + PKCE, без client secret);
- раз в секунду приложение запрашивает `/me/player/currently-playing`, а между запросами позиция
  считается локально, с плавной коррекцией рассинхрона;
- кнопки play/pause/next/previous и перемотка работают через Web API. Spotify разрешает это
  только с **Premium**.

Spotify требует, чтобы у каждого пользователя было своё приложение-клиент.
Его нужно создать один раз:

1. Откройте <https://developer.spotify.com/dashboard> → **Create app**.
2. Redirect URI: `spicylyrics-ios://callback`.
3. В разделе «Which API/SDKs are you planning to use» отметьте **Web API**.
4. В **User Management** добавьте e-mail своего аккаунта Spotify (приложение в Development Mode
   работает только для пользователей из этого списка).
5. Скопируйте **Client ID** и вставьте его на первом экране приложения.

## Источник текстов: ключ Spicy Lyrics

- **С ключом (рекомендуется).** Получите клиентский ключ `sl_pk_…` на
  <https://developers.spicylyrics.org> (каталог приложений) и вставьте его в
  *Настройки → Источники текстов*. Тогда используется публичный `GET /v1/lyrics/{trackId}`, как в
  Android-версии.
- **Без ключа.** Приложение отправляет запрос на `POST /query`, как расширение для Spicetify,
  с вашим токеном Spotify. Ответ в формате SLObjPack распаковывается на устройстве. Сервер может
  не принять токен стороннего приложения. Тогда появится подсказка добавить ключ, а текст будет
  взят из LRCLIB (только построчно).

## Сборка

Нужен Mac с Xcode 16+ (iOS 17+) **или** GitHub Actions.

### На Mac

```bash
brew install xcodegen
xcodegen generate
open SpicyLyrics.xcodeproj
```

В Xcode выберите свою команду (Signing & Capabilities). Если бандл занят, замените
`PRODUCT_BUNDLE_IDENTIFIER` в `project.yml`. Затем запустите приложение на iPhone.

### Без Mac (Windows): GitHub Actions + сайдлоад

1. Загрузите эту папку в свой репозиторий на GitHub.
2. Workflow `.github/workflows/ios-build.yml` соберёт **неподписанный** `SpicyLyrics-unsigned.ipa`
   на macOS-раннере. Скачайте его в разделе *Actions → последний запуск → Artifacts*.
3. Установите IPA через [Sideloadly](https://sideloadly.io) или [AltStore](https://altstore.io)
   со своим Apple ID. С бесплатным аккаунтом подпись действует 7 дней, потом установку нужно
   повторить.

## Структура

```
SpicyLyrics/
  App/          точка входа, жизненный цикл (опрос только когда приложение открыто)
  Spotify/      OAuth PKCE, Web API, модель плеера и часы воспроизведения
  Lyrics/       модели, парсеры (Spicy JSON, LRC), SLObjPack, сервис и дисковый кэш
  Rendering/    пружины и сплайны, аниматор, отрисовка строк, прокрутка
  Background/   динамический фон и Metal-шейдер
  UI/           онбординг, главный экран, панель управления, настройки
```

## Ограничения

- Работает, пока приложение открыто. iOS не даёт держать опрос Spotify в фоне.
- Без Premium можно только смотреть тексты, управление воспроизведением недоступно.
- Нет переводов текстов, Genius и локальных TTML-файлов: в этой версии их нет.

## Лицензия

AGPL-3.0, как и у оригинальных проектов (см. `LICENSE`). Приложение не связано со Spotify AB и
с авторами Spicy Lyrics.
