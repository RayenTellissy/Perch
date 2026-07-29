import AVFoundation

// Chiptune-style alert sounds synthesized as square waves — no asset files
final class SoundPlayer {
    enum Sound: CaseIterable {
        case approval, question, done
    }

    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [Sound: Date] = [:]
    private let sampleRate = 44100.0

    static func defaultsKey(for sound: Sound) -> String {
        switch sound {
        case .approval: "soundApproval"
        case .question: "soundQuestion"
        case .done: "soundDone"
        }
    }

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        buffers[.approval] = makeBuffer(notes: [(659, 0.09), (880, 0.14)])
        buffers[.question] = makeBuffer(notes: [(523, 0.08), (659, 0.08), (988, 0.13)])
        buffers[.done] = makeBuffer(notes: [(523, 0.07), (659, 0.07), (784, 0.07), (1047, 0.16)])
    }

    func play(_ sound: Sound, force: Bool = false) {
        let defaults = UserDefaults.standard
        if !force {
            guard defaults.bool(forKey: "soundsEnabled"),
                  defaults.bool(forKey: Self.defaultsKey(for: sound)) else { return }
        }
        guard let buffer = buffers[sound] else { return }

        // Throttle bursts from parallel sessions
        if let last = lastPlayed[sound], Date().timeIntervalSince(last) < 1.0 { return }
        lastPlayed[sound] = Date()

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                NSLog("Perch: audio engine failed to start: \(error)")
                return
            }
        }
        player.scheduleBuffer(buffer)
        if !player.isPlaying {
            player.play()
        }
    }

    private func makeBuffer(notes: [(freq: Double, dur: Double)], gap: Double = 0.02) -> AVAudioPCMBuffer? {
        let totalSeconds = notes.reduce(0) { $0 + $1.dur + gap }
        let frameCount = AVAudioFrameCount(totalSeconds * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let samples = buffer.floatChannelData![0]
        var frame = 0
        let amplitude: Float = 0.12
        let fade = Int(0.005 * sampleRate)

        for note in notes {
            let noteFrames = Int(note.dur * sampleRate)
            for i in 0..<noteFrames {
                let t = Double(i) / sampleRate
                let square: Float = sin(2 * .pi * note.freq * t) >= 0 ? 1 : -1
                var envelope: Float = 1
                if i < fade { envelope = Float(i) / Float(fade) }
                if i > noteFrames - fade { envelope = Float(noteFrames - i) / Float(fade) }
                samples[frame] = square * amplitude * envelope
                frame += 1
            }
            let gapFrames = Int(gap * sampleRate)
            for _ in 0..<gapFrames where frame < Int(frameCount) {
                samples[frame] = 0
                frame += 1
            }
        }
        return buffer
    }
}
