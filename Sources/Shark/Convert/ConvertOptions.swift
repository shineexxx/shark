import Foundation

struct ConvertOptions: Sendable, Equatable {
    var videoQuality: VideoQuality = .balanced
    var resolution: Resolution = .original
    var audioBitrate: AudioBitrate = .k192
    var imageQuality: Double = 0.9          // 0…1, для jpg/heic/webp/avif
    var stripMetadata = false
    var gifFPS: Int = 15

    enum VideoQuality: String, CaseIterable, Sendable, Identifiable {
        case high, balanced, compact
        var id: String { rawValue }
        var title: String {
            switch self {
            case .high: return L("Maximum")
            case .balanced: return L("Balanced")
            case .compact: return L("Compact")
            }
        }
        var crf: Int {
            switch self {
            case .high: return 18
            case .balanced: return 23
            case .compact: return 28
            }
        }
        var vp9CRF: Int {
            switch self {
            case .high: return 24
            case .balanced: return 32
            case .compact: return 40
            }
        }
        var x264Preset: String {
            switch self {
            case .high: return "slow"
            case .balanced: return "medium"
            case .compact: return "veryfast"
            }
        }
    }

    enum Resolution: String, CaseIterable, Sendable, Identifiable {
        case original, p2160, p1440, p1080, p720, p480, p360
        var id: String { rawValue }
        var title: String {
            switch self {
            case .original: return L("Same as original")
            case .p2160: return "2160p (4K)"
            case .p1440: return "1440p"
            case .p1080: return "1080p"
            case .p720: return "720p"
            case .p480: return "480p"
            case .p360: return "360p"
            }
        }
        var height: Int? {
            switch self {
            case .original: return nil
            case .p2160: return 2160
            case .p1440: return 1440
            case .p1080: return 1080
            case .p720: return 720
            case .p480: return 480
            case .p360: return 360
            }
        }
    }

    enum AudioBitrate: Int, CaseIterable, Sendable, Identifiable {
        case k96 = 96, k128 = 128, k192 = 192, k256 = 256, k320 = 320
        var id: Int { rawValue }
        var title: String { "\(rawValue) kbps" }
    }
}
