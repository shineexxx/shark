import Foundation

/// Всё, что связано с медиа: аудио, видео, а также форматы изображений,
/// которые ImageIO не умеет писать (avif, tga, ppm…).
enum FFmpegConverter {

    // MARK: - Длительность

    static func duration(of url: URL) async -> Double? {
        guard let ffprobe = Tools.url(for: .ffprobe) else { return nil }
        let args = ["-v", "error", "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1", url.path]
        guard let out = try? await ProcessRunner.capture(ffprobe, args), out.ok else { return nil }
        return Double(out.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    struct MediaInfo: Sendable {
        var duration: Double?
        var width: Int?
        var height: Int?
        var videoCodec: String?
        var audioCodec: String?
        var hasVideo: Bool { videoCodec != nil }
    }

    static func probe(_ url: URL) async -> MediaInfo {
        var info = MediaInfo()
        guard let ffprobe = Tools.url(for: .ffprobe) else { return info }
        let args = ["-v", "error",
                    "-show_entries", "format=duration:stream=codec_type,codec_name,width,height",
                    "-of", "default=noprint_wrappers=1", url.path]
        guard let out = try? await ProcessRunner.capture(ffprobe, args), out.ok else { return info }

        var currentType: String?
        for line in out.stdout.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (key, value) = (parts[0], parts[1])
            switch key {
            case "duration": info.duration = Double(value)
            case "codec_type": currentType = value
            case "codec_name":
                if currentType == "video" { info.videoCodec = value }
                if currentType == "audio" { info.audioCodec = value }
            case "width": info.width = Int(value)
            case "height": info.height = Int(value)
            default: break
            }
        }
        return info
    }

    // MARK: - Конвертация

    static func convert(
        source: URL,
        destination: URL,
        target: String,
        options: ConvertOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let ffmpeg = try Tools.require(.ffmpeg)
        let info = await probe(source)
        let total = info.duration ?? 0

        var args = ["-hide_banner", "-nostdin", "-y", "-i", source.path]
        args += encodingArguments(target: target, options: options, info: info)
        args += ["-progress", "pipe:1", "-nostats", destination.path]

        try await ProcessRunner.require(ffmpeg, args) { line, isStderr in
            guard !isStderr, total > 0 else { return }
            // ffmpeg -progress пишет out_time_us=1234567
            guard line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") else { return }
            let raw = line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
            guard let micro = Double(raw), micro >= 0 else { return }
            let seconds = line.hasPrefix("out_time_us=") ? micro / 1_000_000 : micro / 1000
            progress(min(0.99, seconds / total))
        }
        progress(1.0)
    }

    // MARK: - Построение аргументов

    private static func encodingArguments(
        target: String,
        options: ConvertOptions,
        info: MediaInfo
    ) -> [String] {

        if target == "gif" { return gifArguments(options: options) }

        let kind = Formats.kind(ofExtension: Formats.fileExtension(forTarget: target))

        if kind == .audio || (kind != .video && Formats.audioExtensions.contains(target)) {
            return audioArguments(target: target, options: options)
        }
        if kind == .image {
            return imageArguments(target: target, options: options)
        }
        return videoArguments(target: target, options: options, info: info)
    }

    private static func audioArguments(target: String, options: ConvertOptions) -> [String] {
        var args = ["-vn", "-map_metadata", options.stripMetadata ? "-1" : "0"]

        // Кодек задаём явно только там, где выбор по умолчанию нас не устраивает
        // или контейнер допускает несколько вариантов.
        switch target {
        case "mp3":  args += ["-c:a", "libmp3lame", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "m4a", "aac", "mka": args += ["-c:a", "aac", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "ogg":  args += ["-c:a", "libvorbis", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "opus": args += ["-c:a", "libopus", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "wma":  args += ["-c:a", "wmav2", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "ac3":  args += ["-c:a", "ac3", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "mp2":  args += ["-c:a", "mp2", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "amr":  args += ["-c:a", "libopencore_amrnb", "-ar", "8000", "-ac", "1", "-b:a", "12.2k"]
        case "wav":  args += ["-c:a", "pcm_s16le"]
        case "aiff": args += ["-c:a", "pcm_s16be"]
        case "flac": args += ["-c:a", "flac"]
        case "alac": args += ["-c:a", "alac"]
        case "caf":  args += ["-c:a", "alac"]
        default:     args += ["-b:a", "\(options.audioBitrate.rawValue)k"]
        }
        return args
    }

    private static func videoArguments(target: String, options: ConvertOptions, info: MediaInfo) -> [String] {
        var args: [String] = []
        if options.stripMetadata { args += ["-map_metadata", "-1"] }

        if let height = options.resolution.height, (info.height ?? .max) > height {
            // -2 сохраняет пропорции и держит размер кратным двум (требование H.264/HEVC).
            args += ["-vf", "scale=-2:\(height)"]
        }

        switch target {
        case "webm":
            args += ["-c:v", "libvpx-vp9", "-crf", "\(options.videoQuality.vp9CRF)", "-b:v", "0",
                     "-row-mt", "1", "-c:a", "libopus", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "ogv":
            args += ["-c:v", "libtheora", "-q:v", "7", "-c:a", "libvorbis",
                     "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "avi":
            args += ["-c:v", "mpeg4", "-vtag", "xvid", "-q:v", "4",
                     "-c:a", "libmp3lame", "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "wmv":
            args += ["-c:v", "wmv2", "-q:v", "4", "-c:a", "wmav2",
                     "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "mpg", "mpeg":
            args += ["-c:v", "mpeg2video", "-q:v", "4", "-c:a", "mp2",
                     "-b:a", "\(options.audioBitrate.rawValue)k"]
        case "3gp":
            args += ["-c:v", "libx264", "-profile:v", "baseline", "-level", "3.0",
                     "-crf", "\(options.videoQuality.crf)", "-c:a", "aac", "-ar", "16000",
                     "-b:a", "64k", "-ac", "1"]
        case "prores":
            args += ["-c:v", "prores_ks", "-profile:v", "3", "-c:a", "pcm_s16le"]
        case "ts":
            args += ["-c:v", "libx264", "-preset", options.videoQuality.x264Preset,
                     "-crf", "\(options.videoQuality.crf)", "-c:a", "aac",
                     "-b:a", "\(options.audioBitrate.rawValue)k", "-bsf:v", "h264_mp4toannexb"]
        default: // mp4, mkv, mov, m4v, flv
            args += ["-c:v", "libx264", "-preset", options.videoQuality.x264Preset,
                     "-crf", "\(options.videoQuality.crf)", "-pix_fmt", "yuv420p",
                     "-c:a", "aac", "-b:a", "\(options.audioBitrate.rawValue)k"]
            if target == "mp4" || target == "m4v" || target == "mov" {
                args += ["-movflags", "+faststart"]
            }
        }
        return args
    }

    private static func imageArguments(target: String, options: ConvertOptions) -> [String] {
        var args = ["-frames:v", "1"]
        switch target {
        case "jpg", "jpeg":
            // ffmpeg: -q:v 2 (лучшее) … 31 (худшее)
            let q = Int((1 - options.imageQuality) * 29) + 2
            args += ["-q:v", "\(q)"]
        case "webp":
            args += ["-c:v", "libwebp", "-quality", "\(Int(options.imageQuality * 100))"]
        case "avif":
            let crf = Int((1 - options.imageQuality) * 50) + 10
            args += ["-c:v", "libaom-av1", "-crf", "\(crf)", "-b:v", "0", "-cpu-used", "6",
                     "-still-picture", "1"]
        case "png":
            args += ["-c:v", "png"]
        default:
            break
        }
        return args
    }

    private static func gifArguments(options: ConvertOptions) -> [String] {
        var scale = "scale=iw:-1"
        if let height = options.resolution.height { scale = "scale=-2:\(height)" }
        let filter = "fps=\(options.gifFPS),\(scale):flags=lanczos,split[a][b];" +
                     "[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3"
        return ["-filter_complex", filter, "-loop", "0"]
    }
}
