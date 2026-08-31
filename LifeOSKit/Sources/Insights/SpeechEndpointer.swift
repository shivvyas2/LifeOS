import Foundation

/// Decides when a spoken turn is over, from nothing but the microphone level.
///
/// This is the whole of the "stop when I stop talking" rule, kept as a value
/// type with no audio types in it so it can be tested against a made-up
/// timeline instead of a real room. The listener feeds it one reading per
/// audio buffer and does what it says.
///
/// A single fixed level cannot work. The reading that means speech in a
/// bedroom means silence in a café, and one set high enough to clear a café is
/// never reached by someone talking quietly. So the room measures itself: the
/// noise floor is learned from the frames that are not voice, and the two
/// thresholds ride on top of it. Two, not one, because a frame has to be
/// clearly louder than the room to begin a sentence but only a little louder
/// to continue one, which is what keeps the soft tail of a word from reading
/// as the end of a thought.
public struct SpeechEndpointer: Sendable {

    /// The trade between cutting someone off and making them wait. Gathered
    /// and named here rather than left as numbers inside the audio callback.
    public struct Tuning: Sendable {
        /// Opening seconds spent listening to the room rather than for a
        /// voice. Only endpointing waits: the recording is already running, so
        /// nothing said in this window is lost.
        public var calibration: TimeInterval
        /// Trailing quiet that ends the turn. Long enough to survive the pause
        /// in the middle of a thought, short enough that the reply still feels
        /// like an answer and not a timeout.
        public var trailingSilence: TimeInterval
        /// Voice shorter than this is a cough, a chair, or a door. Ending on
        /// it would send a clip with no sentence in it.
        public var minSpeech: TimeInterval
        /// Mic opened and nothing said. Closing beats holding the microphone
        /// open under a screen that claims to be listening.
        public var silencePatience: TimeInterval
        /// A backstop, for the room loud enough that every frame reads as
        /// voice and the trailing-silence rule can never fire on its own.
        public var maxTurn: TimeInterval
        /// The floor is held inside this range. The ceiling matters most: it
        /// bounds the damage when calibration happens to land on speech, since
        /// a floor learned from a voice would put the bar above every later
        /// voice.
        public var floorRange: ClosedRange<Double>

        public init(
            calibration: TimeInterval = 0.4,
            trailingSilence: TimeInterval = 1.5,
            minSpeech: TimeInterval = 0.35,
            silencePatience: TimeInterval = 7,
            maxTurn: TimeInterval = 60,
            floorRange: ClosedRange<Double> = 0.004...0.12
        ) {
            self.calibration = calibration
            self.trailingSilence = trailingSilence
            self.minSpeech = minSpeech
            self.silencePatience = silencePatience
            self.maxTurn = maxTurn
            self.floorRange = floorRange
        }
    }

    public enum Verdict: Equatable, Sendable {
        case keepListening
        /// A sentence was spoken and has finished. Transcribe it.
        case finished
        /// Nothing worth transcribing was ever said. Close the mic and say so.
        case nothingHeard
    }

    public private(set) var noiseFloor: Double
    public private(set) var hasHeardSpeech = false

    private let tuning: Tuning
    private var calibrated = false
    private var quietestSoFar = Double.infinity
    private var speechStartedAt: TimeInterval = 0
    private var lastVoiceAt: TimeInterval = 0
    /// Latched once a verdict is returned, so the caller cannot be told to
    /// finish the same turn twice by the buffers still in flight behind it.
    private var decided = false

    public init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
        self.noiseFloor = tuning.floorRange.lowerBound
    }

    /// The level to clear to begin a sentence.
    public var openThreshold: Double { max(noiseFloor * 3 + 0.020, 0.055) }
    /// The lower level that counts as still talking, once talking has started.
    public var continueThreshold: Double { max(noiseFloor * 2 + 0.012, 0.035) }

    /// Feed one reading. `level` is 0...1, `elapsed` is seconds of audio since
    /// the microphone opened. Audio time, not wall-clock: it cannot drift, and
    /// it is what makes a timeline in a test the same thing as a real one.
    public mutating func observe(level: Double, at elapsed: TimeInterval) -> Verdict {
        guard !decided else { return .keepListening }
        let level = min(max(level, 0), 1)

        guard calibrate(level: level, at: elapsed) else { return .keepListening }

        if level > (hasHeardSpeech ? continueThreshold : openThreshold) {
            if !hasHeardSpeech {
                hasHeardSpeech = true
                speechStartedAt = elapsed
            }
            lastVoiceAt = elapsed
        } else {
            learnFloor(from: level)
        }

        let spokenFor = lastVoiceAt - speechStartedAt

        if elapsed > tuning.maxTurn {
            decided = true
            return hasHeardSpeech && spokenFor >= tuning.minSpeech ? .finished : .nothingHeard
        }

        guard hasHeardSpeech else {
            guard elapsed > tuning.silencePatience else { return .keepListening }
            decided = true
            return .nothingHeard
        }

        guard elapsed - lastVoiceAt > tuning.trailingSilence else { return .keepListening }

        guard spokenFor >= tuning.minSpeech else {
            // A blip, not a sentence. Forget it rather than hold the mic open
            // waiting for a sentence that already ended: with it forgotten the
            // turn goes back to waiting to be spoken to, and closes on its own
            // patience if nobody does.
            hasHeardSpeech = false
            speechStartedAt = 0
            lastVoiceAt = 0
            return .keepListening
        }

        decided = true
        return .finished
    }

    /// Listens to the room before listening for a voice. Returns false while
    /// still calibrating.
    private mutating func calibrate(level: Double, at elapsed: TimeInterval) -> Bool {
        guard !calibrated else { return true }
        guard elapsed >= tuning.calibration else {
            quietestSoFar = min(quietestSoFar, level)
            return false
        }
        calibrated = true
        if quietestSoFar.isFinite {
            noiseFloor = clamped(quietestSoFar)
        }
        return true
    }

    /// The floor learns from silence only. Letting speech into the estimate
    /// would raise it mid-sentence until the speaker's own voice read as quiet.
    /// It drops the moment the room does and climbs slowly, because a room
    /// that has gone quiet should be believed at once and one that has got
    /// louder should have to prove it.
    private mutating func learnFloor(from level: Double) {
        if level < noiseFloor {
            noiseFloor = clamped(level)
        } else {
            noiseFloor = clamped(noiseFloor + (level - noiseFloor) * 0.05)
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, tuning.floorRange.lowerBound), tuning.floorRange.upperBound)
    }
}
