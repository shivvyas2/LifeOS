import SwiftUI
import AppSurfaces
import DesignSystem
import Persistence
import Integrations

/// One video, and the session that follows it.
///
/// Portrait stacks the player over the session: the workout's own details and
/// a single Start button before the timer runs, the HUD and the recorder's
/// controls once it does. Landscape hands the screen to the video and floats
/// the collapsed capsule at the top leading edge, the corner farthest from
/// YouTube's control bar and its branding.
struct VideoWorkoutScreen: View {
    let video: CatalogVideo
    @Bindable var model: ActivityRecorder

    @State private var hudExpanded = false
    @State private var playerFailed = false
    @State private var showControls = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The split decides what the recorder calls this session. A video is a
    /// strength session unless it plainly is not.
    static func activity(for split: String) -> RecordedActivity {
        switch split.lowercased() {
        case "cardio": .other
        case "mobility": .yoga
        default: .strength
        }
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(video.youtubeID)") }

    var body: some View {
        Group {
            if isLandscape, VideoWorkoutLayout.landscapeOverlay {
                landscapeOverlay
            } else {
                portrait
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isLandscape && VideoWorkoutLayout.landscapeOverlay ? .hidden : .visible, for: .navigationBar)
        .sheet(isPresented: $showControls) { controlsSheet }
        .tint(LifeOSTokens.accent)
    }

    // MARK: Portrait

    private var portrait: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    player
                        .aspectRatio(VideoWorkoutLayout.playerAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    openInYouTube
                    details
                    if model.hasSession || model.saved {
                        if let readout = model.readout {
                            elapsedLine
                            SessionHUD(readout: readout, activity: model.selection,
                                       zonesAvailable: model.zonesAvailable, showsTimer: false,
                                       countsAutomatically: model.source == .watch,
                                       onAddRep: { model.addRep() }, onRemoveRep: { model.removeRep() },
                                       onNextSet: { model.nextSet() },
                                       isExpanded: $hudExpanded)
                        }
                        ActivityControls(model: model, onDone: { dismiss() })
                    } else {
                        startButton
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(LifeOSType.secondary)
                            .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
                    }
                }
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .padding(20)
                .padding(.bottom, 24)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(LifeOSType.sectionTitle)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(video.channel) · \(video.durationMinutes) min")
                .font(LifeOSType.caption.weight(.medium))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            HStack(spacing: 6) {
                chip(video.split)
                chip(intensityName)
                ForEach(video.equipment.prefix(2), id: \.self) { chip($0) }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The clock on its own line, the way Begin Activity's hero carries it.
    /// Five readings plus a timer do not fit the capsule at phone width, and
    /// the reading that truncated was the battery percentage, which is the one
    /// number that must never be half a number.
    private var elapsedLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = model.timer?.elapsed(at: timeline.date) ?? 0
            VStack(alignment: .leading, spacing: 2) {
                Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                Text("Elapsed time")
                    .font(LifeOSType.caption)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel("Elapsed time, \(Duration.seconds(elapsed).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))")
        }
    }

    private var intensityName: String {
        switch video.intensity {
        case ...1: "Easy"
        case 2: "Moderate"
        default: "Hard"
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text.capitalized)
            .font(LifeOSType.eyebrow.weight(.medium))
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(LifeOSTokens.cardSurface.resolve(scheme), in: Capsule())
    }

    private var startButton: some View {
        Button { Task { await start() } } label: {
            HStack {
                Spacer()
                if model.busy { ProgressView() } else { Image(systemName: "play.fill") }
                Text(model.busy ? "Starting…" : "Start this workout")
                Spacer()
            }
            .font(LifeOSType.rowTitle).frame(minHeight: 56)
            .foregroundStyle(.white)
            .background(LifeOSTokens.accent, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
    }

    /// Always on the page, not only after a failure. A video the owner has
    /// barred from embedding says so inside the player, where nothing this
    /// screen can see reaches, and someone who simply prefers YouTube's own
    /// app should not have to hit an error first to get there.
    private var openInYouTube: some View {
        VStack(alignment: .leading, spacing: 2) {
            if playerFailed {
                Text("This video will not play here.")
                    .font(LifeOSType.caption)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
            Button("Open in YouTube", systemImage: "arrow.up.forward.app") {
                if let watchURL { openURL(watchURL) }
            }
            .font(LifeOSType.label).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Landscape

    private var landscapeOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            player.ignoresSafeArea()
            HStack(spacing: 0) {
                if model.hasSession, let readout = model.readout {
                    hudCapsule(readout)
                } else if !model.saved {
                    landscapeStart
                }
                Spacer(minLength: 0)
            }
            .padding(VideoWorkoutLayout.overlayInset)
        }
    }

    /// Collapsed, capped, and never expandable in landscape: a tap opens the
    /// controls sheet instead, because an expanded panel over the video would
    /// cover the very thing the person is watching.
    private func hudCapsule(_ readout: LiveSessionReadout) -> some View {
        SessionHUD(readout: readout, activity: model.selection, zonesAvailable: model.zonesAvailable,
                   showsTimer: false, countsAutomatically: model.source == .watch,
                   onAddRep: { model.addRep() }, onRemoveRep: { model.removeRep() },
                   onNextSet: { model.nextSet() },
                   isExpanded: .constant(false))
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxHeight: VideoWorkoutLayout.overlayMaxHeight)
            .clipShape(Capsule())
            .overlay {
                Color.clear
                    .contentShape(Capsule())
                    .onTapGesture { showControls = true }
                    .accessibilityElement()
                    .accessibilityLabel("Session controls")
                    .accessibilityAddTraits(.isButton)
            }
    }

    private var landscapeStart: some View {
        Button { Task { await start() } } label: {
            Label(model.busy ? "Starting…" : "Start this workout", systemImage: "play.fill")
                .font(LifeOSType.label)
                .padding(.horizontal, 14)
                .frame(height: VideoWorkoutLayout.overlayMaxHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(LifeOSTokens.accent, in: Capsule())
        .disabled(model.busy)
    }

    private var controlsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Following: \(video.title) · \(video.channel)")
                        .font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    ActivityControls(model: model, onDone: { showControls = false; dismiss() })
                    openInYouTube
                }
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .padding(20)
            }
            .background(LifeOSTokens.canvas.resolve(scheme))
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showControls = false } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Pieces

    private var player: some View {
        YouTubePlayerView(videoID: video.youtubeID) { playerFailed = true }
            .background(Color.black)
            .accessibilityLabel("\(video.title), YouTube player")
    }

    private func start() async {
        model.selection = Self.activity(for: video.split)
        // Passed to `start`, not set before it: a start that bails must not
        // leave this video stamped on whatever session comes next.
        await model.start(following: (id: video.youtubeID, split: video.split,
                                      title: video.title, channel: video.channel))
    }
}
