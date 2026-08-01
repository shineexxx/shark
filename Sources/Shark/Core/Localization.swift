import Foundation

/// Язык интерфейса. `system` следует настройкам macOS.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, en, ru

    var id: String { rawValue }

    var code: String? {
        switch self {
        case .system: return nil
        case .en: return "en"
        case .ru: return "ru"
        }
    }

    /// Название языка пишем на нём самом — так его найдут те, кто не читает текущий.
    var title: String {
        switch self {
        case .system: return L("System")
        case .en: return "English"
        case .ru: return "Русский"
        }
    }
}

/// Перевод по английскому ключу. Ключ и есть английский текст,
/// поэтому непереведённая строка деградирует в осмысленный английский,
/// а не в служебный идентификатор.
func L(_ key: String) -> String {
    guard Localization.effective == "ru", let value = Localization.russian[key] else { return key }
    return value
}

enum Localization {

    static var selected: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "appLanguage"),
                  let language = AppLanguage(rawValue: raw) else { return .system }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appLanguage")
            // Стандартные меню (Файл, Правка, Окно…) рисует AppKit по своим
            // ресурсам, поэтому язык приходится задавать и на уровне бандла.
            if let code = newValue.code {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    /// Какой язык реально показываем прямо сейчас.
    static var effective: String {
        if let code = selected.code { return code }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ru") ? "ru" : "en"
    }

    static let russian: [String: String] = [
        // MARK: Каркас
        "Converter": "Конвертер",
        "Downloader": "Загрузчик",
        "All components in place": "Все компоненты на месте",
        "Components missing": "Не хватает компонентов",

        // MARK: Типы файлов
        "Audio": "Аудио",
        "Video": "Видео",
        "Images": "Изображения",
        "Documents": "Документы",
        "Archives": "Архивы",
        "Other": "Другое",

        // MARK: Конвертер
        "Drag files here": "Перетащите файлы сюда",
        "Audio, video, images, documents — one by one or a whole folder":
            "Аудио, видео, изображения, документы — по одному или папкой",
        "Choose files…": "Выбрать файлы…",
        "Add": "Добавить",
        "Clear": "Очистить",
        "Convert to": "Конвертировать в",
        "Resolution": "Разрешение",
        "Bitrate": "Битрейт",
        "Image quality": "Качество изображения",
        "Save to": "Куда сохранять",
        "Next to the original": "Рядом с оригиналом",
        "Reset": "Сбросить",
        "Strip metadata": "Удалять метаданные",
        "Convert": "Конвертировать",
        "Stop": "Остановить",
        "Done %@ of %@": "Готово %@ из %@",
        "Show in Finder": "Показать в Finder",
        "Rename result": "Переименовать результат",
        "Rename": "Переименовать",
        "Remove": "Убрать",
        "Retry": "Повторить",
        "Retry failed": "Повторить неудачные",
        "Retry failed downloads": "Повторить неудачные загрузки",
        "Applies to the selected file": "Применяется к выбранному файлу",
        "A file with this name already exists": "Файл с таким именем уже существует",
        "Result name": "Имя результата",
        "Sound": "Звук",
        "s": "с",
        "min": "мин",
        "h": "ч",
        "Total %@": "Всего %@",

        // MARK: Качество
        "Maximum": "Максимум",
        "Balanced": "Баланс",
        "Compact": "Компактно",
        "Same as original": "Как в оригинале",

        // MARK: Загрузчик
        "Video link — YouTube, RuTube, VK, TikTok…":
            "Ссылка на видео — YouTube, RuTube, VK, TikTok…",
        "Paste from clipboard": "Вставить из буфера",
        "and hundreds more sites": "и ещё сотни площадок",
        "Nothing here yet": "Пока пусто",
        "Paste one or more links — a list works too, one per line":
            "Вставьте одну или несколько ссылок — можно списком, каждую с новой строки",
        "%@ queued": "%@ в очереди",
        "Remove finished": "Убрать завершённые",
        "What to download": "Что скачиваем",
        "Audio only": "Только звук",
        "Quality": "Качество",
        "Container": "Контейнер",
        "Audio format": "Формат звука",
        "Options": "Опции",
        "Embed cover art": "Обложка в файл",
        "Subtitles (ru/en)": "Субтитры (ru/en)",
        "Download whole playlist": "Качать плейлист целиком",
        "Browser cookies": "Cookies из браузера",
        "Needed for private, age-restricted and account-only videos.":
            "Нужны для приватных, возрастных и доступных только по аккаунту видео.",
        "No cookies": "Без cookies",
        "VK Video": "VK Видео",
        "macOS blocks access to Safari cookies. Grant Full Disk Access to Shark, or pick Firefox, or choose a cookies.txt file.":
            "macOS не пускает к cookies Safari. Дайте Shark полный доступ к диску, либо выберите Firefox, либо укажите файл cookies.txt.",
        "Browser cookies not found. Make sure that browser is installed and you are signed in.":
            "Cookies браузера не найдены. Проверьте, что браузер установлен и вы в него вошли.",
        "Open Full Disk Access settings": "Открыть настройки доступа к диску",
        "Cookies file": "Файл cookies",
        "Choose a cookies.txt file": "Выберите файл cookies.txt",
        "Use a file instead": "Указать файл",
        "Safari cookies need Full Disk Access. Firefox works without it.":
            "Для cookies Safari нужен полный доступ к диску. Firefox работает без него.",
        "Download": "Скачать",
        "Queued": "В очереди",
        "Preparing…": "Подготовка…",
        "%@ left": "осталось %@",
        "Cancelled": "Отменено",
        "Ready": "Готово",
        "Loading details…": "загружаю сведения…",
        "Link": "Ссылка",
        "Paste a video link (http:// or https://)":
            "Вставьте ссылку на видео (http:// или https://)",
        "This is not a link": "Это не ссылка",
        "%@ links — they will be checked after adding":
            "Ссылок: %@ — проверятся после добавления",
        "Checking the source…": "Проверяю источник…",
        "Source is supported, but the video needs cookies":
            "Источник поддерживается, но видео требует cookies",
        "This source is not supported": "Этот источник не поддерживается",
        "Best": "Максимум",
        "up to %@": "до %@",

        // MARK: Компоненты
        "Everything in place": "Всё на месте",
        "The app is fully self-contained: the engines live inside the .app and do not depend on what is installed in the system.":
            "Приложение полностью автономно: движки лежат внутри .app и не зависят от того, что установлено в системе.",
        "These engines belong inside the .app. Build with Scripts/build.sh — it fetches them itself, or drop the binaries into the folder below.":
            "Эти движки должны лежать внутри .app. Соберите приложение скриптом Scripts/build.sh — он сам их подтянет, либо положите бинарники в папку ниже.",
        "Open components folder": "Открыть папку компонентов",
        "Done": "Готово",
        "not found": "не найден",
        "media conversion, merging downloads": "конвертация медиа, склейка загрузок",
        "video and audio downloading": "загрузка видео и звука",
        "JS runtime for YouTube (optional)": "JS-рантайм для YouTube (необязателен)",
        "Update yt-dlp": "Обновить yt-dlp",
        "Revert": "Откатить",
        "Downloading…": "Скачиваю…",
        "Verifying…": "Проверяю…",
        "Updated to %@": "Обновлено до %@",
        "Reverted to the bundled version": "Возвращена версия из приложения",
        "Download failed (HTTP %@)": "Не удалось скачать (HTTP %@)",
        "The downloaded file does not run — the update was not applied.":
            "Скачанный файл не запускается — обновление не применено.",
        "Sites keep changing, so yt-dlp goes stale faster than the rest. The update is stored next to the app data and can be reverted.":
            "Площадки постоянно меняются, поэтому yt-dlp устаревает быстрее остальных. Обновление кладётся рядом с данными приложения, и его можно откатить.",

        // MARK: Настройки
        "Settings": "Настройки",
        "Settings…": "Настройки…",
        "General": "Основные",
        "Conversion": "Конвертация",
        "Downloads": "Загрузки",
        "Engines": "Движки",
        "Language": "Язык",
        "System": "Системный",
        "Menu titles change after restarting the app.":
            "Названия пунктов меню сменятся после перезапуска приложения.",
        "Launch at login": "Запускать при входе",
        "Keep running when the window is closed":
            "Не выходить при закрытии окна",
        "On closing the window the app leaves the Dock and stays in the menu bar.":
            "При закрытии окна приложение уходит из Dock и остаётся в строке меню.",
        "Show icon in the menu bar": "Значок в строке меню",
        "Reveal result in Finder when done": "Показывать результат в Finder",
        "Play a sound when the queue finishes": "Звук по завершении очереди",
        "Notify when the queue finishes": "Уведомление по завершении",
        "Default save folder": "Папка сохранения по умолчанию",
        "Default download folder": "Папка загрузок по умолчанию",
        "Choose…": "Выбрать…",
        "Default video quality": "Качество видео по умолчанию",
        "Default audio bitrate": "Битрейт звука по умолчанию",
        "Default mode": "Режим по умолчанию",
        "Overwrite existing files": "Перезаписывать существующие файлы",
        "Otherwise a numbered copy is created.":
            "Иначе создаётся копия с номером.",

        // MARK: Меню
        "%@ done": "готово %@",
        "Open Shark": "Открыть Shark",
        "Quit": "Завершить",
        "File": "Файл",
        "Add Files…": "Добавить файлы…",
        "Add Folder…": "Добавить папку…",
        "Clear Queue": "Очистить очередь",
        "Choose Output Folder…": "Выбрать папку назначения…",
        "Start Conversion": "Начать конвертацию",
        "Stop Conversion": "Остановить конвертацию",
        "Paste Link": "Вставить ссылку",
        "Start Download": "Начать загрузку",
        "Stop Download": "Остановить загрузку",
        "Show Converter": "Показать конвертер",
        "Show Downloader": "Показать загрузчик",
        "Check Engines…": "Проверить движки…",
        "Open Downloads Folder": "Открыть папку загрузок",
        "Actions": "Действия",

        // MARK: Контекстное меню Finder
        "Convert with Shark": "Конвертировать через Shark",
        "No files were passed": "Файлы не переданы",

        // MARK: Обновление приложения
        "Check for updates on launch": "Проверять обновления при запуске",
        "Check for Updates…": "Проверить обновления…",
        "Check Now": "Проверить",
        "Checking for updates…": "Проверяю обновления…",
        "Version %@": "Версия %@",
        "Version %@ is available": "Доступна версия %@",
        "You have the latest version (%@)": "Установлена последняя версия (%@)",
        "Shark %@ is available": "Доступен Shark %@",
        "You have version %@.": "У вас версия %@.",
        "Update and Restart": "Обновить и перезапустить",
        "Later": "Позже",
        "Installing…": "Устанавливаю…",
        "Shark was installed with Homebrew. Updating in place will confuse it — run brew upgrade --cask shark instead.":
            "Shark установлен через Homebrew. Обновление поверх собьёт его учёт версий — выполните brew upgrade --cask shark.",
        "Could not reach GitHub (HTTP %@)": "Не удалось связаться с GitHub (HTTP %@)",
        "GitHub returned an unexpected answer.": "GitHub ответил неожиданным образом.",
        "The release has no archive to install.": "В релизе нет архива для установки.",
        "No write access to %@ — install the update manually.":
            "Нет прав на запись в %@ — установите обновление вручную.",
        "The downloaded archive could not be unpacked.":
            "Не удалось распаковать скачанный архив.",
        "The downloaded app does not run — the update was not applied.":
            "Скачанное приложение не запускается — обновление не применено.",

        // MARK: Ошибки
        "Operation cancelled": "Операция отменена",
        "File is already in this format": "Файл уже в этом формате",
        "Could not create PDF": "Не удалось создать PDF",
        "Login required for this video. Turn on browser cookies in the download settings.":
            "Видео требует входа в аккаунт. Включите cookies из браузера в настройках загрузки.",
        "Private video — cookies from an account with access are required.":
            "Приватное видео — нужны cookies аккаунта с доступом.",
        "Video unavailable (removed or region-blocked).":
            "Видео недоступно (удалено или заблокировано по региону).",
        "yt-dlp does not support this link.": "yt-dlp не поддерживает эту ссылку.",
        "Server returned 403 — try cookies or update yt-dlp.":
            "403 от сервера — попробуйте cookies или обновите yt-dlp.",
        "YouTube needs a JS runtime. Rebuild with Scripts/build.sh — it embeds deno.":
            "Для YouTube нужен JS-рантайм. Пересоберите приложение скриптом Scripts/build.sh — он вложит deno."
    ]
}
