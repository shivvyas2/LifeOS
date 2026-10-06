import Foundation

/// A fifteen-minute doubles match, swing by swing, for the phone-only demo:
/// what the Watch would send during a real session, without a Watch.
///
/// Deterministic from its seed, so a demo plays the same way every time and
/// the review it ends in can be captured. The swings are shaped like the
/// detector's output (eight wrist frames, a peak, a signed twist) and stay
/// under the replay limit, so the review treats them exactly as it treats a
/// real session's.
public struct BadmintonDemoScript: Equatable, Sendable {
    public static let length: TimeInterval = 15 * 60
    /// The demo's match: doubles, so the review shows a partner too.
    public static let match = BadmintonSession(format: .doubles, teammate: "Priya", opponents: ["Sam", "Alex"])

    public struct Rally: Equatable, Sendable {
        public var time: Double
        public var winner: BadmintonSide
        public init(time: Double, winner: BadmintonSide) { self.time = time; self.winner = winner }
    }
    /// What the live screen knows at one moment of the demo.
    public struct State: Equatable, Sendable {
        public var swingCount: Int
        public var peakRotation: Double?
        public var rallyWins: [BadmintonSide]
        public var heartRate: Int
        public var energyKcal: Double
    }

    public var swings: [SwingEvent]
    public var rallies: [Rally]

    public init(seed: UInt64 = 7) {
        var random = SplitMix(seed: seed)
        var swings: [SwingEvent] = []
        var rallies: [Rally] = []
        // A moment of stillness first, as the detector asks for.
        var start = 6.0
        while start < Self.length - 12, swings.count < SwingAnalysis.eventLimit {
            // Two swings most rallies, three now and then: the replay keeps at
            // most 120, and a quarter of an hour has to fit under that.
            let count = min(random.next() % 4 == 0 ? 3 : 2, SwingAnalysis.eventLimit - swings.count)
            var time = start
            for position in 0..<count {
                if position > 0 { time += 2.2 + random.unit() * 1.3 }
                let twist = 2.4 + random.unit() * 1.4
                swings.append(Self.swing(id: swings.count, time: time,
                                         rotation: 5.2 + random.unit() * 4.3,
                                         acceleration: 1.2 + random.unit() * 1.6,
                                         twist: random.unit() < 0.6 ? twist : -twist))
            }
            let end = time + 1
            rallies.append(Rally(time: end, winner: random.unit() < 0.6 ? .us : .them))
            start = end + 9 + random.unit() * 6
        }
        self.swings = swings
        self.rallies = rallies
    }

    public func state(at elapsed: Double) -> State {
        let played = swings.prefix { $0.time <= elapsed }
        let warmUp = min(max(elapsed, 0), 180) / 180
        let beat = 118 + warmUp * 32 + 10 * sin(elapsed / 11)
        return State(swingCount: played.count,
                     peakRotation: played.map(\.peakRotation).max(),
                     rallyWins: rallies.prefix { $0.time <= elapsed }.map(\.winner),
                     heartRate: Int(beat.rounded()),
                     energyKcal: max(elapsed, 0) / 60 * 7.2)
    }

    /// The review of the demo so far, numbered and sampled the way the Watch
    /// numbers and samples a real one.
    public func analysis(through elapsed: Double, profile: ActivityAthleteProfile? = nil) -> SwingAnalysis {
        var analysis = SwingAnalysis(profile: profile)
        analysis.sampledSeconds = elapsed
        analysis.events = swings.prefix { $0.time <= elapsed }.enumerated().map { index, swing in
            var event = swing; event.id = index; return event
        }
        return analysis
    }

    /// The id the demo's packets carry, so the recorder treats them as one
    /// session the way it treats a Watch's.
    public static let sessionID = UUID(uuidString: "6B4D1A70-DE30-4C11-9A5E-00BADD01DE70")!

    /// One second of the demo as the Watch would report it: the counts at
    /// this moment, and the rallies decided since `ralliesApplied` scored
    /// onto `session`. Paused, the score stands and no reading is sent, as
    /// a paused Watch sends none. No elapsed time travels: the phone owns
    /// the clock in a demo, where the Watch owns it in a real session.
    public func packet(at elapsed: Double, paused: Bool, session: BadmintonSession,
                       ralliesApplied: Int, now: Date) -> (packet: WatchPacket, ralliesApplied: Int) {
        let moment = state(at: elapsed)
        var packet = WatchPacket(sentAt: now)
        packet.sessionID = Self.sessionID
        packet.paused = paused
        packet.swingCount = moment.swingCount
        packet.peakWristRotation = moment.peakRotation
        packet.energyKcal = moment.energyKcal
        var session = session
        var applied = ralliesApplied
        if !paused {
            packet.heartRate = moment.heartRate
            packet.heartRateAt = now
            while applied < moment.rallyWins.count { session.record(moment.rallyWins[applied]); applied += 1 }
        }
        packet.badminton = session
        return (packet, applied)
    }

    /// One swing shaped like the detector keeps them: eight frames at least
    /// 0.12 s apart tracing a wrist turn, and the peaks the review charts.
    public static func swing(id: Int, time: Double, rotation: Double, acceleration: Double, twist: Double) -> SwingEvent {
        let frames = (0..<8).map { step in
            let angle = sin(Double(step) / 7 * .pi) * 1.8 * min(rotation / 7, 1.4)
            return WristFrame(t: Double(step) * 0.12, x: sin(angle / 2), y: 0, z: 0, w: cos(angle / 2))
        }
        return SwingEvent(id: id, time: time, duration: 0.96, peakRotation: rotation,
                          peakAcceleration: acceleration, frames: frames, twist: twist)
    }
}

/// SplitMix64: a few lines, identical on every platform, enough for a demo.
private struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Uniform in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// Whether the next badminton workout will analyze swings, and if not, the
/// one thing to change. The gate is three conditions the setup form keeps
/// apart; this names the first one that fails.
public struct SwingAnalysisStatus: Equatable, Sendable {
    public var isOn: Bool
    public var text: String

    public static func describe(_ profile: ActivityAthleteProfile?) -> SwingAnalysisStatus {
        guard let profile else {
            return SwingAnalysisStatus(isOn: false, text: "Swing analysis off. Set your playing hand and Watch wrist in Your activity setup.")
        }
        guard profile.motionEnabled else {
            return SwingAnalysisStatus(isOn: false, text: "Swing analysis off. Turn on experimental swing analysis in Your activity setup.")
        }
        let hand = profile.playingHand.rawValue
        guard profile.playingHand == profile.watchWrist else {
            return SwingAnalysisStatus(isOn: false, text: "Swing analysis off. Set Watch wrist to \(hand), your playing hand, and wear the Watch on your racket wrist.")
        }
        return SwingAnalysisStatus(isOn: true, text: "Swing analysis on. Wear the Watch on your \(hand) wrist, your racket hand, and hold still for a second after Start.")
    }
}

/// Why a past badminton session has no motion review, when it has none.
public enum BadmintonMotionState: Sendable { case none, unreadable, readable }

public enum BadmintonSessionStatus {
    /// How long the phone keeps expecting the Watch's summary after a session.
    public static let syncWindow: TimeInterval = 24 * 3600

    /// Nil when the session has a readable review; otherwise the reason it
    /// has none, in the person's terms.
    public static func reason(externalID: String, start: Date, motion: BadmintonMotionState, now: Date = .now) -> String? {
        switch motion {
        case .readable: return nil
        case .unreadable: return "Motion data could not be read"
        case .none:
            if externalID.hasPrefix("almanac-watch:") {
                return now.timeIntervalSince(start) < syncWindow ? "Waiting for your Watch to sync its motion" : "No motion arrived from your Watch"
            }
            if externalID.hasPrefix("almanac:") { return "Recorded on iPhone, no Watch motion" }
            return "Imported, no Watch motion"
        }
    }
}
