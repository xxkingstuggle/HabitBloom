import AVFoundation
import CoreHaptics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class CheckInFeedbackService {
    static let shared = CheckInFeedbackService()

    private var activePlayers: [AVAudioPlayer] = []
    private var cachedSounds: [FeedbackSoundKey: Data] = [:]
    private var pendingSoundKeys = Set<FeedbackSoundKey>()
    private var hapticEngine: CHHapticEngine?

    private init() {}

    func play(completing: Bool, level: Int) {
        pruneFinishedPlayers()
        playHaptics(completing: completing, level: level)

        #if canImport(UIKit)
        let impact = UIImpactFeedbackGenerator(style: completing ? .medium : .soft)
        impact.prepare()
        impact.impactOccurred(intensity: completing ? min(0.78, 0.48 + CGFloat(level) * 0.035) : 0.30)
        #endif

        let clampedLevel = min(max(level, 0), 9)
        let key = FeedbackSoundKey(completing: completing, level: clampedLevel)

        if let data = cachedSounds[key] {
            playSound(data)
            return
        }

        generateSoundIfNeeded(for: key)
    }

    private func playSound(_ data: Data) {
        guard !data.isEmpty, let player = try? AVAudioPlayer(data: data) else { return }
        player.prepareToPlay()
        player.play()
        activePlayers.append(player)
    }

    private func generateSoundIfNeeded(for key: FeedbackSoundKey) {
        guard pendingSoundKeys.insert(key).inserted else { return }
        Task.detached(priority: .userInitiated) {
            let data = FeedbackSoundRenderer.makeLayeredSoundData(
                completing: key.completing,
                level: key.level
            ) ?? Data()
            await CheckInFeedbackService.shared.cacheGeneratedSound(data, for: key)
        }
    }

    private func cacheGeneratedSound(_ data: Data, for key: FeedbackSoundKey) {
        pendingSoundKeys.remove(key)
        cachedSounds[key] = data
        playSound(data)
    }

    private func pruneFinishedPlayers() {
        activePlayers.removeAll { !$0.isPlaying }
    }

    private func playHaptics(completing: Bool, level: Int) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if hapticEngine == nil {
                hapticEngine = try CHHapticEngine()
                hapticEngine?.resetHandler = { [weak self] in
                    Task { @MainActor in try? self?.hapticEngine?.start() }
                }
            }

            try hapticEngine?.start()
            let intensity = min(1, completing ? 0.58 + Float(level) * 0.045 : 0.32)
            let sharpness = completing ? Float(0.82) : Float(0.38)
            let events = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: completing ? intensity * 0.46 : 0.16),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: completing ? 0.62 : 0.22)
                    ],
                    relativeTime: completing ? 0.055 : 0.045
                )
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            // The UIKit fallback above still provides a lightweight tactile cue.
        }
    }

}

private enum FeedbackSoundRenderer {
    private static let sampleRate = 44_100

    static func makeLayeredSoundData(completing: Bool, level: Int) -> Data? {
        let scale: [Double] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
        let semitone = scale[min(level, scale.count - 1)]
        let baseFrequency = completing ? 520.0 : 320.0
        let frequency = baseFrequency * pow(2.0, semitone / 12.0)
        let duration = completing ? 0.24 : 0.13
        let gain = completing ? min(0.92, 0.46 + Double(level) * 0.035) : 0.30

        let sampleCount = max(1, Int(Double(sampleRate) * duration))
        var samples = [Int16]()
        samples.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let t = Double(index) / Double(sampleRate)
            let progress = Double(index) / Double(sampleCount)
            let attack = min(1.0, progress / 0.035)
            let decay = pow(1.0 - progress, completing ? 2.2 : 3.8)
            let envelope = attack * decay

            let clickWindow = max(0, 1.0 - progress / 0.12)
            let click = sin(2.0 * .pi * frequency * 5.7 * t) * clickWindow * 0.34
            let ping = sin(2.0 * .pi * frequency * t)
            let shimmer = sin(2.0 * .pi * frequency * 2.38 * t) * 0.22
            let air = sin(2.0 * .pi * frequency * 3.04 * t) * pow(1.0 - progress, 5.0) * 0.18
            let downward = completing ? 0 : sin(2.0 * .pi * (frequency * (1.0 - progress * 0.18)) * t) * 0.24
            let value = (click + ping + shimmer + air + downward) * envelope * gain
            samples.append(Int16(max(-1, min(1, value)) * Double(Int16.max)))
        }

        return wavData(samples: samples, sampleRate: sampleRate)
    }

    private static func wavData(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let blockAlign: UInt16 = 2
        let subchunk2Size = UInt32(samples.count * 2)
        let chunkSize = UInt32(36) + subchunk2Size

        data.append("RIFF".data(using: .ascii)!)
        data.append(littleEndianData(chunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(littleEndianData(UInt32(16)))
        data.append(littleEndianData(UInt16(1)))
        data.append(littleEndianData(UInt16(1)))
        data.append(littleEndianData(UInt32(sampleRate)))
        data.append(littleEndianData(UInt32(byteRate)))
        data.append(littleEndianData(blockAlign))
        data.append(littleEndianData(UInt16(16)))
        data.append("data".data(using: .ascii)!)
        data.append(littleEndianData(subchunk2Size))

        for sample in samples {
            data.append(littleEndianData(UInt16(bitPattern: sample)))
        }

        return data
    }

    private static func littleEndianData<T: FixedWidthInteger>(_ value: T) -> Data {
        var littleEndian = value.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout<T>.size)
    }
}

private struct FeedbackSoundKey: Hashable, Sendable {
    let completing: Bool
    let level: Int
}
