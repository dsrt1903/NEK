import AVFoundation
import Foundation

@main
struct TrimVideo {
    static func main() async throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration)
        if duration.seconds < 30 { throw CocoaError(.fileReadCorruptFile) }
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let length = min(duration.seconds, 58)
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: duration.seconds - length, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        try await exporter.export(to: output, as: .mp4)
    }
}
