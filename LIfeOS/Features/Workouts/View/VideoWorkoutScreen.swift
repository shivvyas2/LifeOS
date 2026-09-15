import SwiftUI
import AppSurfaces
import DesignSystem
import Persistence
import Integrations

/// One video, and the session that follows it.
///
/// The rings float over the video in both orientations, at the top leading
/// edge, the corner farthest from YouTube's control bar and its branding.
/// Portrait keeps the workout's details, the clock and the recorder's controls
/// under the player; landscape hands the screen to the video and puts the
/// controls behind one glass button.
struct VideoWorkoutScreen: View {
    let video: CatalogVideo
    @Bindable var model: ActivityRecorder

    @State private var hudExpanded = true
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
                        .overlay(alignment: .topLeading) {
                            if model.hasSession, let readout = model.readout {
                                rings(readout, repControls: false).padding(VideoWorkoutLayout.overlayInset)
                            }
                        }
                    openInYouTube
                    details
                    if model.hasSession || model.saved {
                        if model.readout != nil {
                            elapsedLine
                            if model.selection == .strength, model.hasSession { repControlsRow }
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

    /// The clock on its own line, the way Begin Activity's hero carries it,
    /// so the rings over the video stay small.
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
            HStack(alignment: .top, spacing: 10) {
                if model.hasSession, let readout = model.readout {
                    rings(readout)
                    controlsButton
                } else if !model.saved {
                    landscapeStart
                }
                Spacer(minLength: 0)
            }
            .padding(VideoWorkoutLayout.overlayInset)
        }
    }

    private func rings(_ readout: LiveSessionReadout, repControls: Bool = true) -> some View {
        SessionRings(readout: readout, activity: model.selection, zonesAvailable: model.zonesAvailable,
                     countsAutomatically: model.source == .watch,
                     onAddRep: { model.addRep() }, onRemoveRep: { model.removeRep() },
                     onNextSet: { model.nextSet() }, showsRepControls: repControls, isExpanded: $hudExpanded)
            .fixedSize()
    }

    /// Under the video in portrait, where there is room, so the rings over
    /// the video stay as small as the rings.
    private var repControlsRow: some View {
        HStack(spacing: 10) {
            Button("−1") { model.removeRep() }.accessibilityLabel("Remove one rep")
            Button("+1") { model.addRep() }.accessibilityLabel("Add one rep")
            Button("Next set") { model.nextSet() }
        }
        .font(LifeOSType.label)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    /// Pause, finish and discard live in a sheet in landscape, behind one
    /// glass button, so nothing but the rings sits over the video.
    private var controlsButton: some View {
        Button { showControls = true } label: {
            Image(systemName: "ellipsis").font(.headline).foregroundStyle(.white)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("Session controls")
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
