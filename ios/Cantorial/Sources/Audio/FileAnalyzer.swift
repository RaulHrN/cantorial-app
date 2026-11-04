import AVFoundation
import CantorialCore

/// Extracts the sung melody of an audio file: chunked decoding, anti-alias filtering and
/// decimation to ~22 kHz per channel, vocal melody extraction (which tells the voice apart from
/// the instruments) and note segmentation. Memory stays flat whatever the song length.
enum FileAnalyzer {
    struct Result {
        let notes: [NoteEvent]
        let durationMs: Int
        /// Share of the song where a voice was found.
        let voicedRatio: Float
    }

    enum Failure: Error { case unreadable }

    /// Runs off the main thread; checks for cancellation between chunks.
    static func analyze(_ url: URL, progress: @escaping @Sendable (Float) -> Void) async throws -> Result {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let rate = Float(format.sampleRate)
        let channels = Int(format.channelCount)
        guard rate > 0, channels > 0 else { throw Failure.unreadable }
        let factor = max(1, Int((rate / 22050).rounded()))
        let extractor = MelodyExtractor(sampleRate: rate / Float(factor))
        var lowL: Biquad? = factor > 1 ? Biquad.lowPass(sampleRate: rate, cutoff: 0.42 * rate / Float(factor)) : nil
        var lowR: Biquad? = factor > 1 ? Biquad.lowPass(sampleRate: rate, cutoff: 0.42 * rate / Float(factor)) : nil
        let chunk: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw Failure.unreadable }
        let total = max(1, file.length)
        var accL: Float = 0
        var accR: Float = 0
        var count = 0
        var lastProgress = -1
        while true {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: chunk)
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let data = buffer.floatChannelData else { throw Failure.unreadable }
            let l = data[0]
            let r = channels > 1 ? data[1] : data[0]
            for i in 0..<n {
                // Stereo is kept: the extractor uses it to find the centred lead voice.
                var a = l[i]
                var b = r[i]
                if lowL != nil {
                    a = lowL!.process(a)
                    b = lowR!.process(b)
                }
                accL += a
                accR += b
                count += 1
                if count == factor {
                    extractor.push(accL / Float(factor), accR / Float(factor))
                    accL = 0
                    accR = 0
                    count = 0
                }
            }
            let p = Int(Double(file.framePosition) * 100 / Double(total))
            if p != lastProgress {
                lastProgress = p
                progress(Float(min(p, 100)) / 100)
            }
        }
        let melody = extractor.finish()
        let notes = Segmenter.segment(melody.track, hopMs: melody.hopMs, firstFrameMs: melody.firstFrameMs, onsets: Segmenter.onsets(melody.levels))
            .filter { (36...90).contains($0.midi) }
        let duration = Int(Double(file.length) / format.sampleRate * 1000)
        return Result(notes: notes, durationMs: duration, voicedRatio: melody.voicedRatio)
    }
}
