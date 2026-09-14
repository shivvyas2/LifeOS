import SwiftUI
import AppSurfaces
import DesignSystem
import Persistence

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
            if isLandscape {
                if VideoWorkoutLayout.landscapeOverlay { landscapeOverlay } else { landscapeRail }
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
                    details
                    if model.hasSession || model.saved {
                        if let readout = model.readout {
                            SessionHUD(readout: readout, activity: model.selection,
                                       zonesAvailable: model.zonesAvailable,
                                       onAddRep: { model.addRep() }, onNextSet: { model.nextSet() },
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
                    if playerFailed { openInYouTube }
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

    private var openInYouTube: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This video will not play here.")
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
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
                   showsTimer: true, onAddRep: { model.addRep() }, onNextSet: { model.nextSet() },
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

    /// The fallback behind `landscapeOverlay`, kept compiling so the retreat
    /// from an overlay YouTube objects to is a flag flip.
    private var landscapeRail: some View {
        HStack(spacing: 0) {
            player
            VStack(alignment: .leading, spacing: 12) {
                if model.hasSession, let readout = model.readout {
                    SessionHUD(readout: readout, activity: model.selection,
                               zonesAvailable: model.zonesAvailable,
                               onAddRep: { model.addRep() }, onNextSet: { model.nextSet() },
                               isExpanded: $hudExpanded)
                    ActivityControls(model: model, onDone: { dismiss() })
                } else if !model.saved {
                    startButton
                }
                Spacer(minLength: 0)
            }
            .frame(width: 180)
            .padding(12)
        }
        .background(LifeOSTokens.canvas.resolve(scheme))
    }

    private var controlsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Following: \(video.title) · \(video.channel)")
                        .font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    ActivityControls(model: model, onDone: { showControls = false; dismiss() })
                    if playerFailed { openInYouTube }
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
        model.pendingVideoID = video.youtubeID
        model.pendingSplit = video.split
        model.following = (video.title, video.channel)
        await model.start()
    }
}
