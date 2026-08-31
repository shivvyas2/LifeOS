import AVFoundation
import CoreGraphics
import Foundation
import Insights
import OSLog
import Speech

/// Microphone capture for LIFO.
///
/// One tap opens the mic and no second tap is needed: the listener watches the
/// level, decides when the sentence is over, and transcribes what it recorded.
/// The stop button stays for the times someone wants out early.
///
/// ElevenLabs Scribe is primary. Apple Speech is the backup when there is no
/// key, the network call fails, or the clip is too short for Scribe.
///
/// Not MainActor. The app target defaults every type to MainActor, but
/// `AVAudioEngine`'s tap runs on the I/O thread.
nonisolated
final class SpeechListener: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.shivvyas.lifeos", category: "speech")
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onLevel: ((CGFloat) -> Void)?
    var onError: ((String) -> Void)?
    /// Fires the moment the endpointer calls the sentence finished, which is
    /// before any transcript exists. The screen has to stop claiming to listen
    /// then, not when the text lands: the second or two spent uploading the
    /// clip otherwise looks like the mic ignoring you.
    var onEndOfSpeech: (() -> Void)?

    private let lock = NSLock()
    private var session = UUID()
    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var running = false
    private var tapInstalled = false
    private var lastLevelAt = Date.distantPast
    private var usesElevenLabs = false
    private var recordingURL: URL?
    private var audioFile: AVAudioFile?
    private var completing = false

    /// When the turn is over. Read and written only under `lock`, from the
    /// audio thread, once per buffer. The rule itself lives in `Insights`
    /// where it can be run against a made-up room in a test.
    private var endpointer = SpeechEndpointer()
    /// Seconds of audio seen, which is the endpointer's clock.
    private var elapsedAudio: TimeInterval = 0
    private var sampleRate: Double = 0
    /// The newest live transcript from Apple's recognizer, kept because the
    /// task is cancelled at teardown and its final result never arrives.
    private var lastPartial = ""

    /// All `AVAudioSession` activate/deactivate and engine start/stop run here.
    /// `setActive` on the main thread logs AVAudioSession_iOS.mm:978 and can stall the UI.
    private static let sessionQueue = DispatchQueue(label: "com.shivvyas.lifeos.speech-session")

    var isRunning: Bool {
        lock.withLock { running }
    }

    func start() async {
        let id = UUID()
        lock.withLock {
            session = id
            running = false
            completing = false
            endpointer = SpeechEndpointer()
            elapsedAudio = 0
            sampleRate = 0
            lastPartial = ""
            usesElevenLabs = AppConfig.elevenLabsAPIKey?.isEmpty == false
        }

        let mic = await AVAudioApplication.requestRecordPermission()
        guard still(id) else { return }
        guard mic else {
            emitError("Microphone permission is needed to talk to LIFO.")
            return
        }

        if !lock.withLock({ usesElevenLabs }) {
            let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard still(id) else { return }
            guard speechStatus == .authorized else {
                emitError("Microphone permission is needed to talk to LIFO.")
                return
            }
        }

        do {
            try await tryOnSessionQueue { try self.installEngine(session: id) }
        } catch {
            guard still(id) else { return }
            Self.log.error("engine failed: \(error.localizedDescription, privacy: .public)")
            emitError("Could not start the microphone.")
            cancel()
        }
    }

    /// Drop the recording. Keyboard, leave, or a finished send.
    func stop() {
        cancel()
    }

    /// Pause: transcribe what was said (ElevenLabs, then Apple).
    func finish() async {
        let id = lock.withLock { session }
        await complete(session: id, alreadyMarked: false)
    }

    private func cancel() {
        let snapshot = teardown(invalidate: true)
        Self.sessionQueue.async {
            Self.release(snapshot)
            if let url = snapshot.recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        emitLevel(0)
    }

    private func complete(session id: UUID, alreadyMarked: Bool) async {
        if !alreadyMarked {
            let proceed = lock.withLock { () -> Bool in
                guard session == id, !completing else { return false }
                completing = true
                return true
            }
            guard proceed else { return }
        } else {
            guard still(id) else { return }
        }

        let snapshot = lock.withLock {
            Teardown(
                engine: audioEngine,
                request: request,
                task: task,
                hadTap: tapInstalled,
                recordingURL: recordingURL,
                usesElevenLabs: usesElevenLabs
            )
        }

        lock.withLock {
            running = false
            tapInstalled = false
            audioEngine = nil
            request = nil
            task = nil
            audioFile = nil
            recordingURL = nil
        }

        emitEndOfSpeech()
        await runOnSessionQueue { Self.release(snapshot) }
        emitLevel(0)

        guard still(id) else {
            if let url = snapshot.recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        guard let url = snapshot.recordingURL else {
            emitError("Could not hear that. Type instead, or try the mic again.")
            return
        }

        if snapshot.usesElevenLabs {
            await transcribeRecorded(url: url, session: id)
        } else {
            await finalizeApple(url: url, session: id)
        }
    }

    /// Close the mic on a turn where nobody said anything. Not `complete`:
    /// there is no clip worth uploading, and no answer worth waiting for.
    private func abandon(session id: UUID) {
        guard still(id) else { return }
        cancel()
        emitError("I did not hear anything. Tap the mic and try again.")
    }

    /// Feeds the endpointer one reading per audio buffer and does what it says.
    ///
    /// The clock is the audio itself, buffer frames over the sample rate,
    /// rather than the wall. A thread busy elsewhere would otherwise put time
    /// into a silence the speaker never left, and end the turn on top of them.
    private func observe(rms: CGFloat, frames: AVAudioFrameCount, session id: UUID) {
        let verdict = lock.withLock { () -> SpeechEndpointer.Verdict in
            guard running, session == id, !completing, sampleRate > 0 else {
                return .keepListening
            }
            elapsedAudio += Double(frames) / sampleRate
            let verdict = endpointer.observe(level: Double(rms), at: elapsedAudio)
            if verdict != .keepListening { completing = true }
            return verdict
        }

        switch verdict {
        case .keepListening:
            return
        case .finished:
            Task { await self.complete(session: id, alreadyMarked: true) }
        case .nothingHeard:
            Task { self.abandon(session: id) }
        }
    }

    private func transcribeRecorded(url: URL, session id: UUID) async {
        defer { try? FileManager.default.removeItem(at: url) }
        guard still(id) else { return }

        let wav = (try? Data(contentsOf: url)) ?? Data()
        guard wav.count > 1024 else {
            emitError("That was too short to hear. Try the mic again.")
            return
        }

        if let key = AppConfig.elevenLabsAPIKey {
            do {
                let text = try await ElevenLabsSpeechClient.transcribe(wav: wav, apiKey: key)
                guard still(id) else { return }
                await emitFinal(text)
                return
            } catch {
                Self.log.error("elevenlabs failed, using apple speech")
            }
        }

        guard still(id) else { return }
        if let text = await appleTranscribe(url: url), still(id) {
            await emitFinal(text)
            return
        }
        guard still(id) else { return }
        emitError("Could not hear that. Type instead, or try the mic again.")
    }

    /// Finish a turn that ran on Apple's recognizer.
    ///
    /// The live task is cancelled during teardown and never delivers its final
    /// result, so the last partial is the sentence. It is also already on
    /// screen and costs nothing, which makes this the fast path; recognising
    /// the recorded file again is the fallback for a turn that produced no
    /// partials at all.
    private func finalizeApple(url: URL, session id: UUID) async {
        defer { try? FileManager.default.removeItem(at: url) }
        guard still(id) else { return }

        let heard = lock.withLock { lastPartial }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !heard.isEmpty {
            await emitFinal(heard)
            return
        }

        if let text = await appleTranscribe(url: url), still(id) {
            await emitFinal(text)
            return
        }
        guard still(id) else { return }
        emitError("Could not hear that. Type instead, or try the mic again.")
    }

    private func appleTranscribe(url: URL) async -> String? {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return nil }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = false
        return await withCheckedContinuation { continuation in
            var resumed = false
            func finish(_ text: String?) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: text)
            }
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    finish(text.isEmpty ? nil : text)
                    return
                }
                if error != nil {
                    finish(nil)
                }
            }
        }
    }

    private struct Teardown {
        var engine: AVAudioEngine?
        var request: SFSpeechAudioBufferRecognitionRequest?
        var task: SFSpeechRecognitionTask?
        var hadTap: Bool
        var recordingURL: URL?
        var usesElevenLabs: Bool
    }

    private func runOnSessionQueue(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.sessionQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func tryOnSessionQueue(_ work: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.sessionQueue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func release(_ snapshot: Teardown) {
        snapshot.task?.cancel()
        snapshot.request?.endAudio()
        snapshot.engine?.stop()
        if snapshot.hadTap {
            snapshot.engine?.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardown(invalidate: Bool) -> Teardown {
        lock.withLock {
            if invalidate { session = UUID() }
            let snapshot = Teardown(
                engine: audioEngine,
                request: request,
                task: task,
                hadTap: tapInstalled,
                recordingURL: recordingURL,
                usesElevenLabs: usesElevenLabs
            )
            running = false
            tapInstalled = false
            audioEngine = nil
            request = nil
            task = nil
            audioFile = nil
            recordingURL = nil
            return snapshot
        }
    }

    private func installEngine(session id: UUID) throws {
        guard still(id) else { return }

        let elevenLabs = lock.withLock { usesElevenLabs }
        if !elevenLabs {
            let recognizer = SFSpeechRecognizer()
            guard let recognizer, recognizer.isAvailable else {
                emitError("Speech recognition is not available right now.")
                return
            }
            self.recognizer = recognizer
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            emitError("No microphone on this device. Type instead.")
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }

        // Recorded on both paths. Apple's live recognizer is cancelled at
        // teardown and can lose the tail of a sentence, so the file is what
        // makes a second pass possible when the partials came back empty.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lifo-\(id.uuidString).wav")
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        var appleRequest: SFSpeechAudioBufferRecognitionRequest?
        if !elevenLabs {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false
            appleRequest = request
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            appleRequest?.append(buffer)
            do { try audioFile.write(from: buffer) } catch { /* drop this frame */ }
            let rms = Self.rms(buffer)
            self?.emitLevelThrottled(rms)
            self?.observe(rms: rms, frames: buffer.frameLength, session: id)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        guard still(id) else {
            engine.stop()
            input.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }

        lock.withLock {
            self.audioEngine = engine
            self.request = appleRequest
            self.tapInstalled = true
            self.running = true
            self.recordingURL = url
            self.audioFile = audioFile
            self.sampleRate = format.sampleRate
        }

        if let appleRequest, let recognizer {
            let task = recognizer.recognitionTask(with: appleRequest) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.lock.withLock { self.lastPartial = text }
                    }
                    if result.isFinal {
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        Task { await self.emitFinal(text) }
                    } else {
                        self.emitPartial(text)
                    }
                }
                if let error {
                    let ns = error as NSError
                    if ns.code == 1 || ns.code == 209 || ns.code == 216 { return }
                    if !self.isRunning { return }
                    Self.log.error("recognition failed: \(error.localizedDescription, privacy: .public)")
                    self.emitError(error.localizedDescription)
                    self.cancel()
                }
            }
            lock.withLock { self.task = task }
        }
    }

    private func still(_ id: UUID) -> Bool {
        lock.withLock { session == id }
    }

    private func emitPartial(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onPartial?(text)
        }
    }

    private func emitFinal(_ text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { [weak self] in
                self?.onFinal?(text)
                continuation.resume()
            }
        }
    }

    private func emitEndOfSpeech() {
        DispatchQueue.main.async { [weak self] in
            self?.onEndOfSpeech?()
        }
    }

    private func emitError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }

    private func emitLevel(_ level: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
        }
    }

    private func emitLevelThrottled(_ level: CGFloat) {
        let now = Date()
        let due = lock.withLock { () -> Bool in
            let due = now.timeIntervalSince(lastLevelAt) > 0.08
            if due { lastLevelAt = now }
            return due
        }
        guard due else { return }
        emitLevel(level)
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        return CGFloat(min(max(sqrt(sum / Float(count)) * 8, 0), 1))
    }
}
