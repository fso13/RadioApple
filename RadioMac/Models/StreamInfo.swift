import Foundation

/// Audio properties of the current stream, as reported by BASS.
///
/// Kept free of BASS imports so formatting and codec naming are unit-testable.
struct StreamInfo: Equatable {
    let codec: String
    let frequency: Int
    let channels: Int
    let bitrateKbps: Int?
    let bufferMilliseconds: Int

    var sampleRateText: String {
        frequency > 0 ? "\(frequency) Гц" : "—"
    }

    var channelsText: String {
        switch channels {
        case 0: return "—"
        case 1: return "моно"
        case 2: return "стерео"
        default: return "\(channels) канала"
        }
    }

    var bitrateText: String {
        guard let bitrateKbps, bitrateKbps > 0 else { return "—" }
        return "\(bitrateKbps) кбит/с"
    }

    var bufferText: String {
        bufferMilliseconds > 0 ? "\(bufferMilliseconds) мс" : "—"
    }

    /// Human-readable codec name for a `BASS_CHANNELINFO.ctype` value.
    static func codecName(for ctype: UInt32) -> String {
        switch ctype {
        case 0x10003: return "MP1"
        case 0x10004: return "MP2"
        case 0x10005: return "MP3"
        case 0x10002: return "OGG/Vorbis"
        case 0x10006: return "AIFF"
        case 0x10007: return "CoreAudio"
        case 0x10008: return "Media Foundation"
        case 0x10009: return "AM"
        case 0x1000b, 0x1000c: return "AAC"
        case 0x1000d: return "FLAC"
        case 0x40000: return "WAV"
        case 0x50001: return "WAV/PCM"
        case 0x50003: return "WAV/Float"
        default:
            return (ctype & 0xffff_0000) == 0x10000 ? "Поток" : "Неизвестно"
        }
    }
}
